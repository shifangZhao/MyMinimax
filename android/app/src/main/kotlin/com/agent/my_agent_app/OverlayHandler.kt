package com.agent.my_agent_app

import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class OverlayHandler(private val context: Context) {
    private var overlayView: View? = null
    private var isRemoving = false
    private val windowManager by lazy { context.getSystemService(Context.WINDOW_SERVICE) as WindowManager }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "show" -> showOverlay(
                call.argument<String>("title") ?: "",
                call.argument<String>("text") ?: "",
                result
            )
            "hide" -> hideOverlay(result)
            "isVisible" -> result.success(overlayView != null)
            else -> result.notImplemented()
        }
    }

    private fun showOverlay(title: String, text: String, result: MethodChannel.Result) {
        if (!Settings.canDrawOverlays(context)) {
            result.error("PERMISSION", "悬浮窗权限未授予，请在设置中开启", null)
            return
        }

        // Remove existing overlay first
        if (overlayView != null) {
            try {
                windowManager.removeView(overlayView)
            } catch (_: Exception) {}
            overlayView = null
        }

        val layout = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(10), dp(12), dp(10))
            // Dark background with rounded corners
            val bg = android.graphics.drawable.GradientDrawable().apply {
                setColor(0xF0222222.toInt())
                cornerRadius = dp(12).toFloat()
                setStroke(1, 0x44FFFFFF.toInt())
            }
            background = bg
            // Add shadow effect
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                elevation = dp(8).toFloat()
            }
        }

        val titleView = TextView(context).apply {
            this.text = title.ifEmpty { "MyMinimax" }
            textSize = 13f
            setTextColor(0xFFE0E0E0.toInt())
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
        layout.addView(titleView)

        if (text.isNotEmpty()) {
            val textView = TextView(context).apply {
                this.text = text
                textSize = 12f
                setTextColor(0xFFAAAAAA.toInt())
                maxLines = 3
                ellipsize = android.text.TextUtils.TruncateAt.END
            }
            layout.addView(textView)
        }

        // Tap to open the main app
        layout.setOnClickListener {
            try {
                val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
                if (intent != null) context.startActivity(intent)
            } catch (_: Exception) {}
            hideOverlaySilent()
        }

        // Drag to dismiss
        var initialX = 0f
        var initialY = 0f
        var isDragging = false
        layout.setOnTouchListener { view, event ->
            try {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = event.rawX
                        initialY = event.rawY
                        isDragging = false
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - initialX
                        val dy = event.rawY - initialY
                        if (kotlin.math.abs(dx) > 10 || kotlin.math.abs(dy) > 10) {
                            isDragging = true
                            val params = view.layoutParams as WindowManager.LayoutParams
                            params.x = (params.x + dx).toInt()
                            params.y = (params.y + dy).toInt()
                            windowManager.updateViewLayout(view, params)
                            initialX = event.rawX
                            initialY = event.rawY
                        }
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (!isDragging) {
                            view.performClick()
                        }
                        true
                    }
                    else -> false
                }
            } catch (e: Exception) {
                android.util.Log.e("OverlayHandler", "Touch event failed", e)
                true
            }
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 16
            y = 200
        }

        try {
            windowManager.addView(layout, params)
            overlayView = layout
            result.success(true)
        } catch (e: Exception) {
            result.error("ERROR", "悬浮窗创建失败: ${e.message}", null)
        }
    }

    private fun hideOverlay(result: MethodChannel.Result) {
        if (overlayView != null) {
            try {
                windowManager.removeView(overlayView)
            } catch (_: Exception) {}
            overlayView = null
        }
        result.success(true)
    }

    private fun hideOverlaySilent() {
        if (overlayView != null) {
            try {
                windowManager.removeView(overlayView)
            } catch (_: Exception) {}
            overlayView = null
        }
    }

    private fun dp(px: Int): Int {
        return (px * context.resources.displayMetrics.density + 0.5f).toInt()
    }
}
