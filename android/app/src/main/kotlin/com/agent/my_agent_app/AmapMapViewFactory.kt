package com.agent.my_agent_app

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class AmapMapViewFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(
    io.flutter.plugin.common.StandardMessageCodec.INSTANCE
) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val channel = MethodChannel(messenger, "com.myminimax/amap_view_$viewId")
        val apiKey = args as? String
        return AmapNativeMapView(context, channel, apiKey)
    }
}
