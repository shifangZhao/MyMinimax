package com.agent.my_agent_app

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipInputStream

class VoskHandler(private val context: Context) {
    private var model: Model? = null
    private var recognizer: Recognizer? = null
    private var speechService: SpeechService? = null
    private var recognizedText = ""
    private var partialSink: EventChannel.EventSink? = null

    fun setPartialSink(sink: EventChannel.EventSink?) {
        partialSink = sink
    }

    fun handle(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> {
                val modelPath = call.argument<String>("modelPath") ?: ""
                init(modelPath, result)
            }
            "start" -> startListening(result)
            "stop" -> stopListening(result)
            "isAvailable" -> result.success(recognizer != null)
            "dispose" -> {
                dispose()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        try { speechService?.stop() } catch (_: Exception) {}
        speechService = null
        recognizer?.close()
        recognizer = null
        model?.close()
        model = null
    }

    private fun init(modelPath: String, result: MethodChannel.Result) {
        try {
            dispose()

            val modelDir = File(modelPath)
            val modelConf = File(modelDir, "conf/model.conf")
            val extractDir = modelDir.parentFile ?: modelDir

            if (!modelConf.exists()) {
                Log.i("Vosk", "Extracting model from assets zip to $extractDir...")
                try { extractDir.deleteRecursively() } catch (_: Exception) {}
                if (!extractDir.mkdirs()) {
                    result.error("INIT_ERROR", "无法创建模型目录，可能是存储空间不足", null)
                    return
                }
                val buffer = ByteArray(8192)
                try {
                    context.assets.open("vosk_model.zip").use { zipStream ->
                        ZipInputStream(zipStream).use { zis ->
                            var entry = zis.nextEntry
                            var extractedSize = 0L
                            while (entry != null) {
                                if (!entry.isDirectory) {
                                    val outFile = File(extractDir, entry.name)
                                    outFile.parentFile?.mkdirs()
                                    FileOutputStream(outFile).use { fos ->
                                        var len = zis.read(buffer)
                                        while (len > 0) {
                                            fos.write(buffer, 0, len)
                                            extractedSize += len
                                            len = zis.read(buffer)
                                        }
                                    }
                                }
                                entry = zis.nextEntry
                            }
                            Log.i("Vosk", "Extracted $extractedSize bytes")
                        }
                    }
                } catch (e: Exception) {
                    Log.e("Vosk", "Failed to extract model from assets", e)
                    result.error("INIT_ERROR", "模型解压失败: ${e.message}", null)
                    return
                }
            }

            if (!modelConf.exists()) {
                result.error("INIT_ERROR", "模型配置文件不存在", null)
                return
            }
            val finalMdl = File(modelDir, "am/final.mdl")
            if (!finalMdl.exists()) {
                result.error("INIT_ERROR", "模型文件 am/final.mdl 不存在", null)
                return
            }

            try {
                model = Model(modelPath)
                recognizer = Recognizer(model, 16000.0f)
                Log.i("Vosk", "Initialized successfully")
                result.success(true)
            } catch (e: Exception) {
                Log.e("Vosk", "Model/Recognizer creation failed", e)
                result.error("INIT_ERROR", "模型加载失败: ${e.message}", null)
            }
        } catch (e: Exception) {
            Log.e("Vosk", "Init failed", e)
            result.error("INIT_ERROR", e.message, null)
        }
    }

    private fun startListening(result: MethodChannel.Result) {
        try {
            val rec = recognizer
            if (rec == null) {
                result.error("NOT_INIT", "Vosk 未初始化", null)
                return
            }
            try { speechService?.stop() } catch (_: Exception) {}
            speechService = null
            recognizedText = ""

            try {
                speechService = SpeechService(rec, 16000.0f)
            } catch (e: Exception) {
                Log.e("Vosk", "Failed to create SpeechService (mic in use?)", e)
                speechService = null
                result.error("START_ERROR", "麦克风被占用，请重试", null)
                return
            }
            speechService!!.startListening(object : RecognitionListener {
                override fun onPartialResult(hypothesis: String) {
                    try {
                        val text = org.json.JSONObject(hypothesis).optString("text", "")
                        if (text.isNotEmpty()) {
                            recognizedText = text
                            try { partialSink?.success(text) } catch (_: Exception) {}
                        }
                    } catch (_: Exception) {}
                }
                override fun onResult(hypothesis: String) {
                    try {
                        val text = org.json.JSONObject(hypothesis).optString("text", "")
                        if (text.isNotEmpty()) {
                            Log.i("Vosk", "Recognized: $text")
                            recognizedText = text
                        }
                    } catch (_: Exception) {}
                }
                override fun onFinalResult(hypothesis: String) {
                    try {
                        val text = org.json.JSONObject(hypothesis).optString("text", "")
                        if (text.isNotEmpty()) recognizedText = text
                    } catch (_: Exception) {}
                }
                override fun onError(exception: Exception) {
                    Log.e("Vosk", "Recognition error", exception)
                }
                override fun onTimeout() {}
            })
            result.success(true)
        } catch (e: Exception) {
            Log.e("Vosk", "Start failed", e)
            try { result.error("START_ERROR", e.message, null) } catch (_: Exception) {}
        }
    }

    private fun stopListening(result: MethodChannel.Result) {
        try {
            try { speechService?.stop() } catch (_: Exception) {}
            speechService = null
            val text = recognizedText
            recognizedText = ""
            try { partialSink = null } catch (_: Exception) {}
            Log.i("Vosk", "Stop, returning: '$text'")
            result.success(text)
        } catch (e: Exception) {
            Log.e("Vosk", "Stop failed", e)
            try { result.error("STOP_ERROR", e.message, null) } catch (_: Exception) {}
        }
    }
}
