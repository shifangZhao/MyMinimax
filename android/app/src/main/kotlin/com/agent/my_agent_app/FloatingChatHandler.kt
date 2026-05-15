package com.agent.my_agent_app

import android.content.Context
import android.content.Intent
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings
import android.view.*
import android.text.SpannableString
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.*
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.min

class FloatingChatHandler(private val context: Context) {

    // ── 懒加载：避免 Activity 构造阶段 base context 未 attach 导致 NPE ──

    private val windowManager by lazy {
        context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    private val inputMethodManager by lazy {
        context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
    }

    // ── 小米后台弹出窗口检测 ──
    private val isMiui by lazy {
        val mfr = Build.MANUFACTURER.lowercase()
        mfr.contains("xiaomi") || mfr.contains("redmi") || mfr.contains("poco")
    }

    private fun checkMiuiBackgroundPopupPerm(): Boolean {
        if (!isMiui) return true
        try {
            val ops = context.getSystemService(Context.APP_OPS_SERVICE) as android.app.AppOpsManager
            val m = android.app.AppOpsManager::class.java.getDeclaredMethod(
                "checkOpNoThrow", Int::class.javaPrimitiveType, Int::class.javaPrimitiveType, String::class.java
            )
            val result = m.invoke(ops, 10021, android.os.Process.myUid(), context.packageName) as Int
            return result == android.app.AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            android.util.Log.w("FloatingChat", "MIUI bg popup check failed", e)
            return true // 检测失败时不阻塞
        }
    }

    private fun openMiuiPopupPermission() {
        try {
            val intent = Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                setClassName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.permissions.PermissionsEditorActivity"
                )
                putExtra("extra_pkgname", context.packageName)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            // 降级：打开应用详情
            try {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = android.net.Uri.fromParts("package", context.packageName, null)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(intent)
            } catch (_: Exception) {}
        }
    }

    // ── State ──
    private var ballView: View? = null
    private var panelView: View? = null
    private var isPanelOpen = false
    private var isBallVisible = false
    private var isGenerating = false
    private var userLeftApp = false
    private var statusText = ""
    private var currentToolName = ""
    private var titleView: TextView? = null
    private var inputEditText: EditText? = null

    // Panel dimensions (px)
    private var panelWidth = 0
    private var panelHeight = 0
    private val minWidth by lazy { dp(280) }
    private val minHeight by lazy { dp(200) }
    private val maxWidth by lazy { context.resources.displayMetrics.widthPixels }
    private val maxHeight by lazy { (context.resources.displayMetrics.heightPixels * 0.8).toInt() }

    // Panel position persistence
    private val prefs by lazy {
        context.getSharedPreferences("floating_chat_prefs", Context.MODE_PRIVATE)
    }
    private var panelX = -1
    private var panelY = -1

    // RecyclerView adapter
    private val messageItems = mutableListOf<MessageItem>()
    private var streamingItemIndex = -1
    private var messageAdapter: MessageAdapter? = null

    // Flutter MethodChannel
    private var channel: MethodChannel? = null

    // ── Public setup ──

    fun setChannel(ch: MethodChannel) {
        channel = ch
    }

    fun hideAllViews() {
        userLeftApp = false
        hideBall()
        hidePanel()
    }

    fun showBallIfUserLeft() {
        userLeftApp = true
        if (!isPanelOpen) {
            showBall()
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "showBall" -> { if (userLeftApp) showBall(); result.success(true) }
                "hideBall" -> { hideBall(); result.success(true) }
                "hideAll" -> { hideBall(); hidePanel(); result.success(true) }
                "appendMessage" -> {
                    val role = call.argument<String>("role") ?: "assistant"
                    val content = call.argument<String>("content") ?: ""
                    appendMessage(role, content)
                    result.success(true)
                }
                "updateStreaming" -> {
                    val content = call.argument<String>("content") ?: ""
                    updateStreaming(content)
                    result.success(true)
                }
                "streamDone" -> {
                    finishStreaming()
                    result.success(true)
                }
                "setGenerating" -> {
                    isGenerating = call.argument<Boolean>("value") ?: false
                    updateStatusBar()
                    result.success(true)
                }
                "syncMessages" -> {
                    val msgs = call.argument<List<Map<String, String>>>("messages")
                    if (msgs != null) syncMessages(msgs)
                    result.success(true)
                }
                "updateStatus" -> {
                    statusText = call.argument<String>("status") ?: ""
                    currentToolName = call.argument<String>("tool") ?: ""
                    updateStatusBar()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            android.util.Log.e("FloatingChat", "handle failed: ${call.method}", e)
            try { result.success(false) } catch (_: Exception) {}
        }
    }

    // ── Ball (Modern gradient pill) ──

    private fun showBall() {
        if (!Settings.canDrawOverlays(context)) return
        if (ballView != null) return
        isBallVisible = true

        val ballSize = dp(52)
        val ball = FrameLayout(context).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xCC1E1E2E.toInt())
            }
            elevation = dp(6).toFloat()
        }

        // App icon
        val icon = ImageView(context).apply {
            setImageResource(context.resources.getIdentifier(
                "ic_launcher", "mipmap", context.packageName
            ))
            scaleType = ImageView.ScaleType.FIT_CENTER
            clipToOutline = true
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setOval(0, 0, view.width, view.height)
                }
            }
            alpha = 0.9f
        }
        ball.addView(icon, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        ))

        setupBallDrag(ball)
        ball.setOnLongClickListener { openMainApp(); true }

        // 加载上次保存的球位置，没有则默认吸附到右边缘
        val savedBallX = prefs.getInt("ball_x", -1)
        val savedBallY = prefs.getInt("ball_y", -1)
        val screenW = context.resources.displayMetrics.widthPixels
        val screenH = context.resources.displayMetrics.heightPixels

        val params = WindowManager.LayoutParams(
            ballSize, ballSize,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            if (savedBallX >= 0 && savedBallY >= 0) {
                x = savedBallX
                y = savedBallY.coerceIn(dp(80), screenH - ballSize - dp(80))
                // 判断上次在哪一侧
                val centerX = x + ballSize / 2
                ballRetreatedSide = if (centerX < screenW / 2) -1 else 1
            } else {
                x = screenW - ballSize  // 窗口在右边缘内
                y = dp(200)
                ballRetreatedSide = 1  // 右侧缩进
            }
        }

        try {
            windowManager.addView(ball, params)
            ballView = ball
            // 初始缩进状态
            if (ballRetreatedSide != 0) {
                val retreatOffset = if (ballRetreatedSide == -1)
                    -(ballSize - dp(16)).toFloat() else (ballSize - dp(16)).toFloat()
                ball.translationX = retreatOffset
            }
            android.util.Log.i("FloatingChat", "Ball shown successfully")
        } catch (e: Exception) {
            android.util.Log.e("FloatingChat", "showBall addView failed", e)
            isBallVisible = false
        }
    }

    private fun hideBall() {
        ballView?.let {
            try { windowManager.removeView(it) } catch (_: Exception) {}
        }
        ballView = null
        isBallVisible = false
    }

    private var ballRetreatedSide: Int = 0 // 0=none, -1=left, 1=right

    private fun setupBallDrag(view: View) {
        var initialX = 0
        var initialY = 0
        var touchStartX = 0f
        var touchStartY = 0f
        var isDragging = false
        val ballSize = dp(52)

        view.setOnTouchListener { _, event ->
            try {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        // 缩进状态 → 先动画弹出
                        if (ballRetreatedSide != 0) {
                            view.animate().translationX(0f).setDuration(120).start()
                            ballRetreatedSide = 0
                        }
                        val params = view.layoutParams as WindowManager.LayoutParams
                        initialX = params.x
                        initialY = params.y
                        touchStartX = event.rawX
                        touchStartY = event.rawY
                        isDragging = false
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - touchStartX
                        val dy = event.rawY - touchStartY
                        if (abs(dx) > 8 || abs(dy) > 8) {
                            isDragging = true
                            val params = view.layoutParams as WindowManager.LayoutParams
                            params.x = (initialX + dx).toInt()
                            params.y = (initialY + dy).toInt()
                            windowManager.updateViewLayout(view, params)
                        }
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (isDragging) {
                            snapBallToEdge(view)
                        } else {
                            channel?.invokeMethod("onBallTapped", emptyMap<String, Any>())
                            showPanel()
                        }
                        true
                    }
                    else -> false
                }
            } catch (e: Exception) {
                android.util.Log.e("FloatingChat", "Touch event error", e)
                true
            }
        }
    }

    private fun snapBallToEdge(view: View) {
        val params = view.layoutParams as WindowManager.LayoutParams
        val screenWidth = context.resources.displayMetrics.widthPixels
        val ballSize = dp(52)
        val ballCenter = params.x + ballSize / 2
        val isLeft = ballCenter < screenWidth / 2

        // 窗口 x 保持在屏幕内
        params.x = if (isLeft) 0 else screenWidth - ballSize
        val screenHeight = context.resources.displayMetrics.heightPixels
        params.y = params.y.coerceIn(dp(80), screenHeight - ballSize - dp(80))
        windowManager.updateViewLayout(view, params)

        // 通过 translationX 把球推出屏幕，只露 dp(16)
        val retreatOffset = if (isLeft) -(ballSize - dp(16)).toFloat()
            else (ballSize - dp(16)).toFloat()
        view.animate().translationX(retreatOffset).setDuration(150).start()
        ballRetreatedSide = if (isLeft) -1 else 1

        // 保存展开态位置（下次恢复用）
        prefs.edit().putInt("ball_x", params.x).putInt("ball_y", params.y).apply()
    }

    // ── Panel (Modern glassmorphism) ──

    private fun showPanel() {
        if (!Settings.canDrawOverlays(context)) {
            android.util.Log.w("FloatingChat", "showPanel blocked: canDrawOverlays false")
            channel?.invokeMethod("onPanelError", mapOf("error" to "overlay_permission_denied"))
            return
        }
        if (isPanelOpen) {
            android.util.Log.w("FloatingChat", "showPanel blocked: already open")
            return
        }

        // 小米：检查后台弹出窗口权限
        if (isMiui && !checkMiuiBackgroundPopupPerm()) {
            android.util.Log.w("FloatingChat", "showPanel blocked: MIUI background popup denied, opening settings")
            openMiuiPopupPermission()
            channel?.invokeMethod("onPanelError", mapOf("error" to "miui_background_popup_denied"))
            return
        }

        try {
            showPanelInternal()
        } catch (e: Exception) {
            android.util.Log.e("FloatingChat", "showPanel failed", e)
            if (panelView != null) {
                try { windowManager.removeView(panelView) } catch (_: Exception) {}
                panelView = null
            }
            isPanelOpen = false
            channel?.invokeMethod("onPanelError", mapOf("error" to (e.message ?: "unknown")))
        }
    }

    private fun showPanelInternal() {
        android.util.Log.i("FloatingChat", "showPanelInternal start")

        if (panelWidth == 0) panelWidth = dp(320)
        if (panelHeight == 0) panelHeight = dp(440)

        val panel = FrameLayout(context).apply {
            background = GradientDrawable().apply {
                orientation = GradientDrawable.Orientation.TOP_BOTTOM
                colors = intArrayOf(
                    0xE81E1E2E.toInt(),
                    0xE8141420.toInt()
                )
                cornerRadius = dp(20).toFloat()
                setStroke(dp(1), 0x33FFFFFF.toInt())
            }
            elevation = dp(12).toFloat()
            clipToOutline = true
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setRoundRect(0, 0, view.width, view.height, dp(20).toFloat())
                }
            }
        }

        // ── Header ──
        val header = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(8))
        }

        val topRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        titleView = TextView(context).apply {
            text = "My Minimax"
            textSize = 15f
            setTextColor(0xFFFFFFFF.toInt())
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            letterSpacing = 0.5f
        }
        topRow.addView(titleView, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        topRow.addView(makeCircleButton("−") { collapseToBall() })
        topRow.addView(makeCircleButton("×") { hideAllViews(); openMainApp() },
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                marginStart = dp(4)
            })

        header.addView(topRow)

        // Status bar
        val statusBar = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(4), 0, dp(4))
        }

        val statusDot = View(context).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xFF6366F1.toInt())
            }
        }
        statusBar.addView(statusDot, FrameLayout.LayoutParams(dp(8), dp(8)).apply {
            gravity = Gravity.CENTER_VERTICAL
        })

        val statusLabel = TextView(context).apply {
            id = View.generateViewId()
            text = ""
            textSize = 11f
            setTextColor(0xAAFFFFFF.toInt())
            setPadding(dp(8), 0, 0, 0)
        }
        statusBar.addView(statusLabel, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        header.addView(statusBar)
        panel.addView(header, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { gravity = Gravity.TOP })

        // ── Message list ──
        val recycler = RecyclerView(context).apply {
            layoutManager = LinearLayoutManager(context)
            messageAdapter = MessageAdapter(messageItems)
            adapter = messageAdapter
            setPadding(dp(12), dp(4), dp(12), dp(4))
            setBackgroundColor(Color.TRANSPARENT)
        }
        panel.addView(recycler, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT
        ).apply {
            topMargin = dp(64)
            bottomMargin = dp(56)
        })

        // ── Input bar ──
        val inputBar = FrameLayout(context).apply {
            setPadding(dp(8), dp(6), dp(8), dp(10))
            setBackgroundColor(0x11000000.toInt())
        }

        val inputBg = EditText(context).apply {
            hint = "输入消息..."
            setHintTextColor(0x88FFFFFF.toInt())
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 14f
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                colors = intArrayOf(0x22FFFFFF.toInt(), 0x18FFFFFF.toInt())
                cornerRadius = dp(12).toFloat()
                setStroke(dp(1), 0x33FFFFFF.toInt())
            }
            setPadding(dp(16), dp(10), dp(16), dp(10))
            maxLines = 4
            imeOptions = EditorInfo.IME_ACTION_SEND
            setOnEditorActionListener { _, actionId, _ ->
                if (actionId == EditorInfo.IME_ACTION_SEND) {
                    sendMessage(this.text.toString())
                    this.text.clear()
                    true
                } else false
            }
            setOnTouchListener { v, _ ->
                // 点击输入框时尝试弹出键盘
                v.requestFocus()
                try {
                    inputMethodManager.showSoftInput(v, InputMethodManager.SHOW_IMPLICIT)
                } catch (_: Exception) {}
                false
            }
        }
        inputEditText = inputBg
        inputBar.addView(inputBg, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { gravity = Gravity.BOTTOM })

        val sendBtn = makeCircleButton("↑") {
            sendMessage(inputBg.text.toString())
            inputBg.text.clear()
        }
        inputBar.addView(sendBtn, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.END
            bottomMargin = dp(2)
            rightMargin = dp(2)
        })

        panel.addView(inputBar, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { gravity = Gravity.BOTTOM })

        // ── Resize & Drag ──
        setupPanelCornerResize(panel)
        setupPanelDrag(header, panel)

        // ── Window params ──
        // 加载上次保存的位置，没有则居中
        loadPanelPosition()
        val params = WindowManager.LayoutParams(
            panelWidth, panelHeight,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            val screenW = context.resources.displayMetrics.widthPixels
            val screenH = context.resources.displayMetrics.heightPixels
            if (panelX >= 0 && panelY >= 0) {
                x = panelX.coerceIn(-dp(100), screenW - dp(100))
                y = panelY.coerceIn(-dp(40), screenH - dp(40))
            } else {
                x = (screenW - panelWidth) / 2
                y = (screenH - panelHeight) / 2 + dp(40)
            }
        }

        android.util.Log.i("FloatingChat", "Adding panel to window: ${params.width}x${params.height} at (${params.x}, ${params.y})")

        windowManager.addView(panel, params)
        panelView = panel
        isPanelOpen = true

        android.util.Log.i("FloatingChat", "Panel added successfully, hiding ball")
        hideBall()

        channel?.invokeMethod("onPanelStateChanged", mapOf("open" to true))
        updateStatusBar()
        scrollToBottom()
    }

    private fun hidePanel() {
        inputEditText = null
        panelView?.let {
            try { windowManager.removeView(it) } catch (_: Exception) {}
        }
        panelView = null
        isPanelOpen = false
        channel?.invokeMethod("onPanelStateChanged", mapOf("open" to false))
    }

    private fun collapseToBall() {
        hidePanel()
        showBall()
    }

    // ── Corner resize ──

    private fun setupPanelCornerResize(panel: FrameLayout) {
        var resizeCorner = 0
        var initialW = 0
        var initialH = 0
        var initialX = 0
        var initialY = 0
        var touchStartX = 0f
        var touchStartY = 0f

        panel.setOnTouchListener { view, event ->
            try {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        val cornerSize = dp(44)
                        val vw = view.width
                        val vh = view.height
                        val x = event.x.toInt()
                        val y = event.y.toInt()

                        val nearLeft = x < cornerSize
                        val nearRight = x > vw - cornerSize
                        val nearTop = y < cornerSize
                        val nearBottom = y > vh - cornerSize

                        resizeCorner = 0
                        if (nearTop && nearLeft) resizeCorner = Gravity.TOP or Gravity.START
                        else if (nearTop && nearRight) resizeCorner = Gravity.TOP or Gravity.END
                        else if (nearBottom && nearLeft) resizeCorner = Gravity.BOTTOM or Gravity.START
                        else if (nearBottom && nearRight) resizeCorner = Gravity.BOTTOM or Gravity.END

                        if (resizeCorner != 0) {
                            val p = panel.layoutParams as WindowManager.LayoutParams
                            initialW = p.width
                            initialH = p.height
                            initialX = p.x
                            initialY = p.y
                            touchStartX = event.rawX
                            touchStartY = event.rawY
                            true
                        } else {
                            false
                        }
                    }
                    MotionEvent.ACTION_MOVE -> {
                        if (resizeCorner == 0) return@setOnTouchListener false
                        val p = panel.layoutParams as WindowManager.LayoutParams
                        val rawDx = (event.rawX - touchStartX).toInt()
                        val rawDy = (event.rawY - touchStartY).toInt()

                        val top = (resizeCorner and Gravity.TOP) == Gravity.TOP
                        val bottom = (resizeCorner and Gravity.BOTTOM) == Gravity.BOTTOM
                        val left = (resizeCorner and Gravity.START) == Gravity.START || (resizeCorner and Gravity.LEFT) == Gravity.LEFT
                        val right = (resizeCorner and Gravity.END) == Gravity.END || (resizeCorner and Gravity.RIGHT) == Gravity.RIGHT

                        when {
                            right -> panelWidth = (initialW + rawDx).coerceIn(minWidth, maxWidth)
                            left -> {
                                val newWidth = (initialW - rawDx).coerceIn(minWidth, maxWidth)
                                val newX = initialX + (initialW - newWidth)
                                p.x = newX.coerceIn(-dp(100), context.resources.displayMetrics.widthPixels - dp(100))
                                panelWidth = newWidth
                            }
                        }
                        when {
                            bottom -> panelHeight = (initialH + rawDy).coerceIn(minHeight, maxHeight)
                            top -> {
                                val newHeight = (initialH - rawDy).coerceIn(minHeight, maxHeight)
                                val newY = initialY + (initialH - newHeight)
                                p.y = newY.coerceIn(-dp(40), context.resources.displayMetrics.heightPixels - dp(40))
                                panelHeight = newHeight
                            }
                        }

                        p.width = panelWidth
                        p.height = panelHeight
                        windowManager.updateViewLayout(panel, p)
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (resizeCorner == 0) return@setOnTouchListener false
                        resizeCorner = 0
                        val p = panel.layoutParams as WindowManager.LayoutParams
                        savePanelPosition(p.x, p.y)
                        true
                    }
                    else -> false
                }
            } catch (e: Exception) {
                android.util.Log.e("FloatingChat", "Panel resize error", e)
                false
            }
        }
    }

    // ── Panel drag ──

    private fun setupPanelDrag(dragHandle: View, panel: View) {
        var initialX = 0
        var initialY = 0
        var touchStartX = 0f
        var touchStartY = 0f

        dragHandle.setOnTouchListener { _, event ->
            try {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        val p = panel.layoutParams as WindowManager.LayoutParams
                        initialX = p.x
                        initialY = p.y
                        touchStartX = event.rawX
                        touchStartY = event.rawY
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val p = panel.layoutParams as WindowManager.LayoutParams
                        p.x = initialX + (event.rawX - touchStartX).toInt()
                        p.y = initialY + (event.rawY - touchStartY).toInt()
                        windowManager.updateViewLayout(panel, p)
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        val p = panel.layoutParams as WindowManager.LayoutParams
                        savePanelPosition(p.x, p.y)
                        true
                    }
                    else -> false
                }
            } catch (e: Exception) {
                android.util.Log.e("FloatingChat", "Panel drag error", e)
                false
            }
        }
    }

    // ── Status bar ──

    private fun updateStatusBar() {
        try {
            panelView?.let { panel ->
                for (i in 0 until (panel as ViewGroup).childCount) {
                    val child = panel.getChildAt(i)
                    if (child is LinearLayout && child.orientation == LinearLayout.VERTICAL) {
                        for (j in 0 until child.childCount) {
                            val row = child.getChildAt(j)
                            if (row is LinearLayout && row.orientation == LinearLayout.HORIZONTAL) {
                                for (k in 0 until row.childCount) {
                                    val v = row.getChildAt(k)
                                    if (v is TextView && v.textSize < 13f && v.id != View.NO_ID) {
                                        v.text = when {
                                            currentToolName.isNotEmpty() -> "🔧 $currentToolName"
                                            statusText.isNotEmpty() -> "💭 $statusText"
                                            isGenerating -> "⚡ 生成中..."
                                            else -> ""
                                        }
                                        return
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("FloatingChat", "updateStatusBar failed", e)
        }
    }

    // ── Messages ──

    data class MessageItem(val role: String, val content: String, val isStreaming: Boolean = false)

    private fun appendMessage(role: String, content: String) {
        if (streamingItemIndex >= 0) {
            messageItems.removeAt(streamingItemIndex)
            streamingItemIndex = -1
        }
        val label = if (role == "user") "你" else "Agent"
        messageItems.add(MessageItem(label, content))
        messageAdapter?.notifyDataSetChanged()
        scrollToBottom()
    }

    private fun updateStreaming(content: String) {
        if (streamingItemIndex < 0) {
            messageItems.add(MessageItem("Agent", content, isStreaming = true))
            streamingItemIndex = messageItems.size - 1
        } else {
            messageItems[streamingItemIndex] = MessageItem("Agent", content, isStreaming = true)
        }
        messageAdapter?.notifyItemChanged(streamingItemIndex)
        scrollToBottom()
    }

    private fun finishStreaming() {
        if (streamingItemIndex >= 0) {
            val item = messageItems[streamingItemIndex]
            messageItems[streamingItemIndex] = item.copy(isStreaming = false)
            messageAdapter?.notifyItemChanged(streamingItemIndex)
            streamingItemIndex = -1
        }
        isGenerating = false
        updateStatusBar()
    }

    private fun syncMessages(msgs: List<Map<String, String>>) {
        messageItems.clear()
        streamingItemIndex = -1
        for (msg in msgs) {
            val role = msg["role"] ?: "assistant"
            val content = msg["content"] ?: ""
            val label = if (role == "user") "你" else "Agent"
            messageItems.add(MessageItem(label, content))
        }
        messageAdapter?.notifyDataSetChanged()
        scrollToBottom()
    }

    private fun scrollToBottom() {
        try {
            panelView?.let { panel ->
                for (i in 0 until (panel as ViewGroup).childCount) {
                    val child = panel.getChildAt(i)
                    if (child is RecyclerView) {
                        val adapter = child.adapter ?: return
                        if (adapter.itemCount > 0) {
                            child.post { child.scrollToPosition(adapter.itemCount - 1) }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("FloatingChat", "scrollToBottom failed", e)
        }
    }

    private fun sendMessage(text: String) {
        if (text.isBlank()) return
        try {
            appendMessage("user", text)
            channel?.invokeMethod("onSendMessage", mapOf("text" to text))
            isGenerating = true
            updateStatusBar()
        } catch (e: Exception) {
            android.util.Log.e("FloatingChat", "sendMessage failed", e)
        }
    }

    // ── RecyclerView Adapter ──

    inner class MessageAdapter(private val items: List<MessageItem>) :
        RecyclerView.Adapter<MessageAdapter.ViewHolder>() {

        inner class ViewHolder(val textView: TextView) : RecyclerView.ViewHolder(textView)

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
            val tv = TextView(parent.context).apply {
                textSize = 12f
                setPadding(dp(10), dp(6), dp(10), dp(6))
                setTextColor(0xFFE0E0E0.toInt())
                setLineSpacing(4f, 1f)
            }
            return ViewHolder(tv)
        }

        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
            val item = items[position]
            val isUser = item.role == "你"
            val roleColor = if (isUser) 0xFF60A5FA.toInt() else 0xFFA78BFA.toInt()
            val roleTag = SpannableString("[${item.role}] ").apply {
                setSpan(ForegroundColorSpan(roleColor), 0, length, SpannableString.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            val streamPrefix = if (item.isStreaming) "⚡ " else ""
            val contentText = SpannableString(streamPrefix + item.content)
            holder.textView.text = TextUtils.concat(roleTag, contentText)
        }

        override fun getItemCount(): Int = items.size
    }

    // ── Helpers ──

    private fun openMainApp() {
        try {
            hideBall()
            hidePanel()
            val intent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?.apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
            if (intent != null) context.startActivity(intent)
        } catch (e: Exception) {
            android.util.Log.e("FloatingChat", "openMainApp failed", e)
            showBall()
        }
    }

    private fun makeCircleButton(text: String, onClick: () -> Unit): TextView {
        return TextView(context).apply {
            this.text = text
            textSize = 18f
            setTextColor(0xCCFFFFFF.toInt())
            gravity = Gravity.CENTER
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0x28FFFFFF.toInt())
            }
            background = bg
            width = dp(32)
            height = dp(32)
            setOnClickListener { onClick() }
        }
    }

    private fun loadPanelPosition() {
        panelX = prefs.getInt("panel_x", -1)
        panelY = prefs.getInt("panel_y", -1)
    }

    private fun savePanelPosition(x: Int, y: Int) {
        panelX = x
        panelY = y
        prefs.edit().putInt("panel_x", x).putInt("panel_y", y).apply()
    }

    private fun dp(px: Int): Int {
        return (px * context.resources.displayMetrics.density + 0.5f).toInt()
    }
}
