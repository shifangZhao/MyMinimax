package com.agent.my_agent_app

import android.content.res.AssetManager
import android.util.Log

class OcrEngine {
    companion object {
        init {
            System.loadLibrary("my_ocr")
        }
    }

    private external fun nLoadModel(assetManager: AssetManager, useGpu: Boolean): Boolean
    private external fun nRecognize(imagePath: String): String
    external fun nDispose()

    var isLoaded: Boolean = false
        private set

    fun load(assetManager: AssetManager, useGpu: Boolean = false): Boolean {
        isLoaded = nLoadModel(assetManager, useGpu)
        return isLoaded
    }

    fun recognize(imagePath: String): String {
        if (!isLoaded) return ""
        return try {
            nRecognize(imagePath)
        } catch (e: Exception) {
            Log.e("OcrEngine", "nRecognize failed", e)
            ""
        }
    }

    fun dispose() {
        nDispose()
        isLoaded = false
    }
}
