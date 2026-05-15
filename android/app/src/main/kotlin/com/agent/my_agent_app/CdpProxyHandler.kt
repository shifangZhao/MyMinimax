package com.agent.my_agent_app

import android.content.Context
import android.net.LocalSocket
import android.net.LocalSocketAddress
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * CDP 代理 — TCP → WebView DevTools Unix 套接字
 *
 * WebView (Chromium) 的 DevTools 在抽象 Unix 域套接字上监听 CDP 协议。
 * 名称格式：@webview_devtools_remote_<PID>
 * 代理在 localhost TCP 端口与 DevTools Unix 套接字之间双向转发字节。
 * 零协议解析，零额外依赖。
 */
class CdpProxyHandler(private val context: Context) {
    private var proxyThread: Thread? = null
    private var proxyRunning = false
    private var proxyPort = 9223
    private var devToolsSocket: String? = null

    fun handle(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startProxy" -> {
                val port = call.argument<Int>("port") ?: 9223
                startProxy(port, result)
            }
            "stopProxy" -> {
                stopProxy()
                result.success(true)
            }
            "isProxyRunning" -> result.success(proxyRunning)
            "getProxyPort" -> result.success(proxyPort)
            "enableWebViewDebugging" -> {
                enableWebViewDebugging()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    fun stop() {
        stopProxy()
    }

    private fun enableWebViewDebugging() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
            android.webkit.WebView.setWebContentsDebuggingEnabled(true)
            Log.i("CdpProxy", "WebView debugging enabled")
        }
    }

    private fun findDevToolsSocket(): String? {
        // Strategy 1: Scan /proc/net/unix
        try {
            val file = java.io.File("/proc/net/unix")
            if (file.exists()) {
                for (line in file.readLines()) {
                    if (line.contains("webview_devtools_remote")) {
                        val parts = line.trim().split(Regex("\\s+"))
                        val path = parts.lastOrNull() ?: continue
                        if (path.startsWith("@webview_devtools_remote_")) {
                            Log.i("CdpProxy", "Found DevTools socket via /proc/net/unix: $path")
                            return path.substring(1)
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.w("CdpProxy", "Socket scan failed: ${e.message}")
        }

        // Strategy 2: Probe common names
        for (suffix in listOf(android.os.Process.myPid().toString(), "0")) {
            val name = "webview_devtools_remote_$suffix"
            try {
                val testSocket = LocalSocket()
                testSocket.connect(LocalSocketAddress(name, LocalSocketAddress.Namespace.ABSTRACT))
                testSocket.close()
                Log.i("CdpProxy", "Found DevTools socket by probing: $name")
                return name
            } catch (_: Exception) {}
        }
        return null
    }

    private fun startProxy(port: Int, result: MethodChannel.Result) {
        if (proxyRunning && proxyPort == port) {
            Log.d("CdpProxy", "Proxy already running on port $port")
            result.success(mapOf("port" to port, "ready" to true))
            return
        }

        enableWebViewDebugging()
        devToolsSocket = findDevToolsSocket()
        if (devToolsSocket == null) {
            Log.w("CdpProxy", "DevTools socket not found yet. WebView may not be created.")
        }
        proxyPort = port

        proxyThread = Thread {
            try {
                val serverSocket = java.net.ServerSocket()
                serverSocket.reuseAddress = true
                serverSocket.bind(java.net.InetSocketAddress("127.0.0.1", port))
                proxyRunning = true
                Log.i("CdpProxy", "Proxy listening on 127.0.0.1:$port")
                runOnUiThread { result.success(mapOf("port" to port, "ready" to true)) }

                while (proxyRunning) {
                    try {
                        val client = serverSocket.accept()
                        Log.d("CdpProxy", "Client connected")
                        Thread {
                            try {
                                var socketName = devToolsSocket
                                if (socketName == null) {
                                    for (retry in 1..5) {
                                        socketName = findDevToolsSocket()
                                        if (socketName != null) break
                                        Log.d("CdpProxy", "Waiting for DevTools socket (attempt $retry/5)...")
                                        Thread.sleep(600)
                                    }
                                }
                                if (socketName == null) {
                                    Log.w("CdpProxy", "DevTools socket still not available after retries")
                                    client.close()
                                    return@Thread
                                }
                                devToolsSocket = socketName

                                val unixSocket = LocalSocket()
                                unixSocket.connect(LocalSocketAddress(socketName, LocalSocketAddress.Namespace.ABSTRACT))
                                Log.d("CdpProxy", "Connected to DevTools socket: $socketName")

                                val clientIn = client.getInputStream()
                                val clientOut = client.getOutputStream()
                                val unixIn = unixSocket.inputStream
                                val unixOut = unixSocket.outputStream

                                val fwd1 = Thread {
                                    try {
                                        val buf = ByteArray(8192)
                                        var n: Int
                                        while (clientIn.read(buf).also { n = it } != -1) {
                                            unixOut.write(buf, 0, n)
                                            unixOut.flush()
                                        }
                                    } catch (_: Exception) {}
                                }
                                val fwd2 = Thread {
                                    try {
                                        val buf = ByteArray(8192)
                                        var n: Int
                                        while (unixIn.read(buf).also { n = it } != -1) {
                                            clientOut.write(buf, 0, n)
                                            clientOut.flush()
                                        }
                                    } catch (_: Exception) {}
                                }
                                fwd1.start(); fwd2.start()
                                fwd1.join(); fwd2.join()
                            } catch (e: Exception) {
                                Log.d("CdpProxy", "Session closed: ${e.message}")
                            } finally {
                                try { client.close() } catch (_: Exception) {}
                            }
                        }.start()
                    } catch (e: Exception) {
                        if (proxyRunning) Log.w("CdpProxy", "Accept error: ${e.message}")
                    }
                }
                serverSocket.close()
            } catch (e: Exception) {
                Log.e("CdpProxy", "Proxy start failed: ${e.message}", e)
                proxyRunning = false
                runOnUiThread { result.error("PROXY_ERROR", e.message, null) }
            }
        }.apply {
            name = "CdpProxy-Main"
            isDaemon = true
            start()
        }
    }

    private fun stopProxy() {
        proxyRunning = false
        try { proxyThread?.interrupt() } catch (_: Exception) {}
        proxyThread = null
        devToolsSocket = null
        Log.i("CdpProxy", "Stopped")
    }

    private fun runOnUiThread(action: () -> Unit) {
        (context as? android.app.Activity)?.runOnUiThread(action)
    }
}
