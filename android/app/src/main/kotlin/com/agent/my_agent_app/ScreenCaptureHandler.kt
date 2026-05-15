package com.agent.my_agent_app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class ScreenCaptureHandler(private val activity: Activity) {
    private var mediaProjection: MediaProjection? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingOutputPath: String? = null
    private var isCapturing = false
    private var captureHandler: Handler? = null
    private var captureRunnable: Runnable? = null
    
    // Android 14+ 截屏检测回调
    private var screenCaptureCallback: Activity.ScreenCaptureCallback? = null

    companion object {
        const val REQUEST_CODE = 2001
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capture" -> {
                if (isCapturing) {
                    result.error("CAPTURE_IN_PROGRESS", "截屏操作正在进行中", null)
                    return
                }
                pendingOutputPath = call.argument<String>("outputPath")
                pendingResult = result
                if (mediaProjection != null) {
                    captureScreen()
                } else {
                    requestMediaProjection()
                }
            }
            "hasPermission" -> result.success(mediaProjection != null)
            "release" -> {
                mediaProjection?.stop()
                mediaProjection = null
                result.success(null)
            }
            // Android 14+ 截屏检测
            "registerScreenCaptureCallback" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    screenCaptureCallback = Activity.ScreenCaptureCallback {
                        Log.d("ScreenCapture", "Screen capture detected by system")
                    }
                    activity.registerScreenCaptureCallback(
                        activity.mainExecutor,
                        screenCaptureCallback!!
                    )
                    result.success(true)
                } else {
                    result.success(false) // 不支持
                }
            }
            "unregisterScreenCaptureCallback" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    screenCaptureCallback?.let {
                        activity.unregisterScreenCaptureCallback(it)
                        screenCaptureCallback = null
                    }
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_CODE || pendingResult == null) return

        if (resultCode != Activity.RESULT_OK || data == null) {
            pendingResult?.error("PERMISSION_DENIED", "用户拒绝了屏幕录制权限", null)
            pendingResult = null
            pendingOutputPath = null
            return
        }

        try {
            val manager = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            mediaProjection = manager.getMediaProjection(resultCode, data)
            if (mediaProjection == null) {
                pendingResult?.error("CAPTURE_ERROR", "获取截屏服务失败", null)
                pendingResult = null
                pendingOutputPath = null
                return
            }
            captureScreen()
        } catch (e: Exception) {
            Log.e("ScreenCapture", "Failed to init MediaProjection", e)
            pendingResult?.error("CAPTURE_ERROR", "获取截屏权限失败: ${e.message}", null)
            pendingResult = null
            pendingOutputPath = null
        }
    }

    private fun requestMediaProjection() {
        try {
            val manager = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            activity.startActivityForResult(manager.createScreenCaptureIntent(), REQUEST_CODE)
        } catch (e: Exception) {
            pendingResult?.error("CAPTURE_ERROR", "无法启动截屏权限请求: ${e.message}", null)
            pendingResult = null
        }
    }

    private fun captureScreen() {
        val projection = mediaProjection
        if (projection == null) {
            pendingResult?.error("CAPTURE_ERROR", "截屏权限未授予", null)
            pendingResult = null
            pendingOutputPath = null
            return
        }

        isCapturing = true
        captureHandler = Handler(Looper.getMainLooper())

        val metrics = activity.resources.displayMetrics
        val width = metrics.widthPixels
        val height = metrics.heightPixels
        val density = metrics.densityDpi

        val imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 1)
        var virtualDisplay: android.hardware.display.VirtualDisplay? = null
        try {
            virtualDisplay = projection.createVirtualDisplay(
                "screen_capture",
                width, height, density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                imageReader.surface, null, null
            )
        } catch (e: Exception) {
            imageReader.close()
            isCapturing = false
            pendingResult?.error("CAPTURE_ERROR", "创建虚拟显示器失败: ${e.message}", null)
            pendingResult = null
            pendingOutputPath = null
            return
        }

        captureRunnable = Runnable {
            try {
                val image = imageReader.acquireLatestImage()
                if (image == null) {
                    pendingResult?.error("CAPTURE_ERROR", "截屏失败：无法获取图像帧", null)
                } else {
                    try {
                        val planes = image.planes
                        val buffer = planes[0].buffer
                        val pixelStride = planes[0].pixelStride
                        val rowStride = planes[0].rowStride
                        val rowPadding = rowStride - pixelStride * width

                        val bitmap = Bitmap.createBitmap(
                            width + rowPadding / pixelStride, height,
                            Bitmap.Config.ARGB_8888
                        )
                        bitmap.copyPixelsFromBuffer(buffer)

                        val outputPath = pendingOutputPath?.takeIf { it.isNotEmpty() }
                            ?: "${activity.cacheDir.absolutePath}/screenshot_${System.currentTimeMillis()}.png"

                        File(outputPath).parentFile?.mkdirs()
                        FileOutputStream(outputPath).use { out ->
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                        }
                        bitmap.recycle()

                        Log.i("ScreenCapture", "Screenshot saved: $outputPath")
                        pendingResult?.success(outputPath)
                    } finally {
                        image.close()
                    }
                }
            } catch (e: Exception) {
                Log.e("ScreenCapture", "Capture failed", e)
                pendingResult?.error("CAPTURE_ERROR", "截屏失败: ${e.message}", null)
            } finally {
                try { virtualDisplay?.release() } catch (_: Exception) {}
                imageReader.close()
                pendingResult = null
                pendingOutputPath = null
                isCapturing = false
            }
        }
        captureHandler?.postDelayed(captureRunnable!!, 150)
    }

    fun dispose() {
        captureRunnable?.let { captureHandler?.removeCallbacks(it) }
        captureRunnable = null
        captureHandler = null
        isCapturing = false
        mediaProjection?.stop()
        mediaProjection = null
        // Android 14+ 清理截屏回调
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            screenCaptureCallback?.let {
                try {
                    activity.unregisterScreenCaptureCallback(it)
                } catch (_: Exception) {}
                screenCaptureCallback = null
            }
        }
    }
}
