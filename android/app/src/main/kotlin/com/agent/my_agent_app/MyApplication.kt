package com.agent.my_agent_app

import android.util.Log
import com.amap.api.location.AMapLocationClient
import com.amap.api.maps.MapsInitializer
import io.flutter.app.FlutterApplication

/// Custom Application class that initializes Amap privacy compliance
/// before any map API is called, as required by Amap SDK best practices.
class MyApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        // 全局未捕获异常处理器 — 记录崩溃信息
        val prevHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            Log.e("MapCrash", ">>> UNCAUGHT EXCEPTION on thread=${thread.name}", throwable)
            prevHandler?.uncaughtException(thread, throwable)
        }
        // 高德地图隐私合规 — 必须在任何 AMap API 调用之前执行
        MapsInitializer.updatePrivacyShow(this, true, true)
        MapsInitializer.updatePrivacyAgree(this, true)
        AMapLocationClient.updatePrivacyShow(this, true, true)
        AMapLocationClient.updatePrivacyAgree(this, true)
    }
}
