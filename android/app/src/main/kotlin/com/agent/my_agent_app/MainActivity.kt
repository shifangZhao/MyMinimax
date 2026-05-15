package com.agent.my_agent_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Base64
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

class MainActivity : FlutterActivity() {
    private val PERMISSION_CHANNEL = "com.agent.my_agent_app/permissions"
    private val FILE_MANAGER_CHANNEL = "com.myminimax/file_manager"
    private val SAF_CHANNEL = "com.myminimax/saf"
    private val VOSK_CHANNEL = "com.myminimax/vosk"
    private val VOSK_PARTIAL_CHANNEL = "com.myminimax/vosk_partial"
    private val ALARM_CHANNEL = "com.myminimax/alarm"
    private val CONTACTS_CHANNEL = "com.myminimax/contacts"
    private val CALENDAR_CHANNEL = "com.myminimax/calendar"
    private val PHONE_CHANNEL = "com.myminimax/phone"
    private val LOCATION_CHANNEL = "com.myminimax/location"
    private val SHARE_CHANNEL = "com.myminimax/share"
    private val SMS_CHANNEL = "com.myminimax/sms"
    private val OVERLAY_CHANNEL = "com.myminimax/overlay"
    private val FLOATING_CHAT_CHANNEL = "com.myminimax/floating_chat"
    private val NOTIF_LISTENER_CHANNEL = "com.myminimax/notification_listener"
    private val PDF_CHANNEL = "com.myminimax/pdf"
    private val DOC_CHANNEL = "com.myminimax/doc"
    private val OCR_CHANNEL = "com.myminimax/ocr"
    private val SCREEN_CAPTURE_CHANNEL = "com.myminimax/screen_capture"
    private val CHROMIUM_CHANNEL = "com.myminimax/chromium"
    private val AMAP_VIEW_TYPE = "com.myminimax/amap_view"
    private val PERMISSION_REQUEST_CODE = 1001

    private var pendingPermission: String? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    // OCR engine
    private var ocrEngine: OcrEngine? = null

    // Delegated handlers
    private val contactsHandler = ContactsHandler(this)
    private val calendarHandler = CalendarHandler(this)
    private val phoneHandler = PhoneHandler(this)
    private val locationHandler = LocationHandler(this)
    private val smsHandler = SmsHandler(this)
    private val overlayHandler = OverlayHandler(this)
    private val floatingChatHandler = FloatingChatHandler(this)
    private val safHandler = SafHandler(this)
    private val voskHandler = VoskHandler(this)
    private val cdpProxyHandler = CdpProxyHandler(this)
    private val screenCaptureHandler = ScreenCaptureHandler(this)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── 权限通道 ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> {
                    val permission = call.argument<String>("permission") ?: ""
                    result.success(isPermissionGranted(permission))
                }
                "requestPermission" -> {
                    val permission = call.argument<String>("permission") ?: ""
                    pendingPermission = permission
                    pendingPermissionResult = result
                    requestPermission(permission)
                }
                "openSettings" -> { openAppSettings(); result.success(true) }
                "openOverlaySettings" -> { openOverlaySettings(); result.success(true) }
                "openNotificationListenerSettings" -> { openNotificationListenerSettings(); result.success(true) }
                "checkSpecialPermission" -> {
                    val permission = call.argument<String>("permission") ?: ""
                    result.success(checkSpecialPermission(permission))
                }
                "isPermissionPermanentlyDenied" -> {
                    val permission = call.argument<String>("permission") ?: ""
                    val neverAskAgain = !ActivityCompat.shouldShowRequestPermissionRationale(this, permission)
                    result.success(neverAskAgain)
                }
                else -> result.notImplemented()
            }
        }

        // ── 文件管理器通道 ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_MANAGER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openFolder" -> openFileManager(call.argument<String>("path") ?: "", result)
                else -> result.notImplemented()
            }
        }

        // ── SAF 通道（委托）──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAF_CHANNEL).setMethodCallHandler { call, result ->
            safHandler.handle(call, result)
        }

        // ── PDF 通道 ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PDF_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "extractPdfText" -> handleExtractPdfText(call.argument<String>("path") ?: "", result)
                "renderPageAsImage" -> handleRenderPageAsImage(
                    call.argument<String>("path") ?: "",
                    call.argument<Int>("page") ?: 0,
                    call.argument<String>("outputPath") ?: "",
                    result
                )
                "getPageCount" -> handleGetPageCount(call.argument<String>("path") ?: "", result)
                else -> result.notImplemented()
            }
        }

        // ── DOC 通道 ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOC_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "extractDocText" -> handleExtractDocText(call.argument<String>("path") ?: "", result)
                else -> result.notImplemented()
            }
        }

        // ── OCR 通道 ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OCR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "loadModel" -> handleOcrLoad(result)
                "recognize" -> handleOcrRecognize(call.argument<String>("imagePath") ?: "", result)
                "dispose" -> handleOcrDispose(result)
                "isLoaded" -> result.success(ocrEngine?.isLoaded ?: false)
                else -> result.notImplemented()
            }
        }

        // ── Vosk 通道（委托）──
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, VOSK_PARTIAL_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { voskHandler.setPartialSink(events) }
            override fun onCancel(arguments: Any?) { voskHandler.setPartialSink(null) }
        })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOSK_CHANNEL).setMethodCallHandler { call, result ->
            voskHandler.handle(call, result)
        }

        // ── 定时任务通道（简化版 - 闹钟仅用于 App 打开时触发通知）──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAlarm" -> {
                    setAlarm(
                        call.argument<String>("taskId") ?: "",
                        call.argument<String>("title") ?: "",
                        call.argument<Long>("dueMs") ?: 0L,
                        call.argument<Int>("notifyId") ?: 0
                    )
                    result.success(true)
                }
                "cancelAlarm" -> { cancelAlarm(call.argument<Int>("notifyId") ?: 0); result.success(true) }
                "cancelAll" -> { cancelAllAlarms(); result.success(true) }
                "syncAlarms" -> { syncAlarms(call.argument<String>("alarms") ?: "[]"); result.success(true) }
                "getTappedTaskId" -> result.success(getTappedTaskId())
                "canScheduleExactAlarms" -> {
                    val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    result.success(am.canScheduleExactAlarms())
                }
                "requestExactAlarmPermission" -> {
                    // Android 14+ 引导用户授权精确闹钟
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        if (!am.canScheduleExactAlarms()) {
                            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(intent)
                        }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // ── 委托通道（已有独立 Handler）──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTACTS_CHANNEL).setMethodCallHandler { call, result -> contactsHandler.handle(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALENDAR_CHANNEL).setMethodCallHandler { call, result -> calendarHandler.handle(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PHONE_CHANNEL).setMethodCallHandler { call, result -> phoneHandler.handle(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_CHANNEL).setMethodCallHandler { call, result -> locationHandler.handle(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL).setMethodCallHandler { call, result -> smsHandler.handle(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL).setMethodCallHandler { call, result -> overlayHandler.handle(call, result) }

        // ── 悬浮对话通道 ──
        val floatingChatChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FLOATING_CHAT_CHANNEL)
        floatingChatHandler.setChannel(floatingChatChannel)
        floatingChatChannel.setMethodCallHandler { call, result -> floatingChatHandler.handle(call, result) }

        // ── 通知监听通道 ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIF_LISTENER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isPermissionGranted" -> result.success(NotificationListenerService.isEnabled(this))
                "getRecentNotifications" -> {
                    val limit = call.argument<Int>("limit") ?: 50
                    result.success(NotificationListenerService.getNotifications(this, limit))
                }
                "clearNotifications" -> { NotificationListenerService.clearNotifications(this); result.success(true) }
                "postNotification" -> {
                    postNotification(call.argument<String>("title") ?: "", call.argument<String>("body") ?: "")
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // ── 分享接收通道 ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingShare" -> {
                    val prefs = getSharedPreferences("share_intent", Context.MODE_PRIVATE)
                    val text = prefs.getString("shared_text", null)
                    val uri = prefs.getString("shared_uri", null)
                    val mime = prefs.getString("shared_mime", null)
                    if (text != null || uri != null) {
                        val map = HashMap<String, String?>()
                        map["text"] = text
                        map["uri"] = uri
                        if (uri != null && mime != null && mime.startsWith("image/")) {
                            try {
                                val imageUri = Uri.parse(uri)
                                val inputStream = contentResolver.openInputStream(imageUri)
                                val bytes = inputStream?.readBytes()
                                inputStream?.close()
                                if (bytes != null && bytes.isNotEmpty()) {
                                    map["imageBase64"] = Base64.encodeToString(bytes, Base64.NO_WRAP)
                                    map["imageMimeType"] = mime
                                    map["imageFileName"] = uri.substring(uri.lastIndexOf('/') + 1)
                                    map["imageSize"] = bytes.size.toString()
                                }
                            } catch (e: Exception) {
                                Log.w("ShareReceiver", "Cannot read image bytes: $e")
                            }
                        }
                        result.success(map)
                        prefs.edit().clear().apply()
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ── 截屏通道 ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CAPTURE_CHANNEL).setMethodCallHandler { call, result ->
            screenCaptureHandler.handle(call, result)
        }

        // ── CDP 代理通道（委托）──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHROMIUM_CHANNEL).setMethodCallHandler { call, result ->
            cdpProxyHandler.handle(call, result)
        }

        // ── 高德地图 PlatformView ──
        AmapNativeMapView.loadApiKeyFromPrefs(this)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            AMAP_VIEW_TYPE,
            AmapMapViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )

        handleShareIntent(intent)
    }

    // ==================== 生命周期 ====================

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShareIntent(intent)
        tappedTaskId = intent.getStringExtra("tapped_task_id")
    }

    override fun onResume() {
        super.onResume()
        smsHandler.processPendingDelete()
        floatingChatHandler.hideAllViews()
        userLeftApp = false
    }

    private var userLeftApp = false

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        userLeftApp = true
        floatingChatHandler.showBallIfUserLeft()
    }

    override fun onPause() {
        super.onPause()
    }

    override fun onDestroy() {
        voskHandler.dispose()
        cdpProxyHandler.stop()
        screenCaptureHandler.dispose()
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        safHandler.handleActivityResult(requestCode, resultCode, data)
        screenCaptureHandler.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
            pendingPermission = null
        }
    }

    // ==================== 闹钟 ====================

    private fun setAlarm(taskId: String, title: String, dueMs: Long, notifyId: Int) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmReceiver::class.java).apply {
            putExtra(AlarmReceiver.EXTRA_TASK_ID, taskId)
            putExtra(AlarmReceiver.EXTRA_TASK_TITLE, title)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            this, notifyId, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Android 14+ 处理精确闹钟权限
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            if (alarmManager.canScheduleExactAlarms()) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, dueMs, pendingIntent)
            } else {
                // 降级为非精确闹钟
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, dueMs, pendingIntent)
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, dueMs, pendingIntent)
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, dueMs, pendingIntent)
        }
    }

    private fun cancelAlarm(notifyId: Int) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            this, notifyId, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)
    }

    private fun cancelAllAlarms() {
        val prefs = getSharedPreferences("task_alarms", Context.MODE_PRIVATE)
        val alarmsJson = prefs.getString("alarms", "[]") ?: "[]"
        try {
            val alarms = JSONArray(alarmsJson)
            for (i in 0 until alarms.length()) {
                cancelAlarm(alarms.getJSONObject(i).getInt("notifyId"))
            }
        } catch (_: Exception) {}
        prefs.edit().putString("alarms", "[]").apply()
    }

    private fun syncAlarms(alarmsJson: String) {
        cancelAllAlarms()
        getSharedPreferences("task_alarms", Context.MODE_PRIVATE).edit().putString("alarms", alarmsJson).apply()
        try {
            val alarms = JSONArray(alarmsJson)
            for (i in 0 until alarms.length()) {
                val alarm = alarms.getJSONObject(i)
                val dueMs = alarm.getLong("dueMs")
                if (dueMs > System.currentTimeMillis()) {
                    setAlarm(alarm.getString("taskId"), alarm.getString("title"), dueMs, alarm.getInt("notifyId"))
                }
            }
        } catch (_: Exception) {}
    }

    private var tappedTaskId: String? = null

    private fun getTappedTaskId(): String? {
        if (tappedTaskId == null) tappedTaskId = intent.getStringExtra("tapped_task_id")
        val id = tappedTaskId
        tappedTaskId = null
        return id
    }

    // ==================== 权限 ====================

    private fun isPermissionGranted(permission: String): Boolean =
        ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED

    private fun requestPermission(permission: String) {
        if (isPermissionGranted(permission)) {
            pendingPermissionResult?.success(true)
            pendingPermissionResult = null
            pendingPermission = null
            return
        }
        ActivityCompat.requestPermissions(this, arrayOf(permission), PERMISSION_REQUEST_CODE)
    }

    private fun openAppSettings() {
        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", packageName, null)
        })
    }

    private fun openOverlaySettings() {
        startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
            data = Uri.fromParts("package", packageName, null)
        })
    }

    private fun openNotificationListenerSettings() {
        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
    }

    private fun checkSpecialPermission(permission: String): Boolean = when (permission) {
        "android.permission.SYSTEM_ALERT_WINDOW" -> Settings.canDrawOverlays(this)
        "notification_listener" -> NotificationListenerService.isEnabled(this)
        else -> false
    }

    // ==================== 文件管理器 ====================

    private fun openFileManager(path: String, result: MethodChannel.Result) {
        try {
            val uri = Uri.parse("file://$path")
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "resource/folder")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent); result.success(true)
            } else {
                val fallback = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "*/*")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                if (fallback.resolveActivity(packageManager) != null) {
                    startActivity(fallback); result.success(true)
                } else {
                    result.error("NO_APP", "没有可打开文件夹的应用", null)
                }
            }
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    // ==================== 通知 ====================

    private fun postNotification(title: String, body: String) {
        try {
            val channelId = "agent_notifications"
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                manager.createNotificationChannel(android.app.NotificationChannel(
                    channelId, "MiniMax Agent", android.app.NotificationManager.IMPORTANCE_DEFAULT
                ))
            }
            val pendingIntent = PendingIntent.getActivity(
                this, 0,
                Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            manager.notify(System.currentTimeMillis().toInt(), android.app.Notification.Builder(this, channelId)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title.ifEmpty { "MiniMax Agent" })
                .setContentText(body)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setPriority(android.app.Notification.PRIORITY_DEFAULT)
                .build()
            )
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to post notification", e)
        }
    }

    // ==================== PDF / DOC ====================

    private fun handleExtractPdfText(path: String, result: MethodChannel.Result) {
        try {
            val file = java.io.File(path)
            if (!file.exists()) { result.error("NOT_FOUND", "PDF 文件不存在: $path", null); return }
            val fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            val renderer = PdfRenderer(fd)
            for (i in 0 until renderer.pageCount) { renderer.openPage(i).close() }
            renderer.close(); fd.close()
            result.success("")
        } catch (e: Exception) {
            Log.e("PDF", "extractPdfText failed: $path", e)
            result.error("PDF_ERROR", e.message, null)
        }
    }

    private fun handleRenderPageAsImage(path: String, pageIndex: Int, outputPath: String, result: MethodChannel.Result) {
        try {
            val file = java.io.File(path)
            if (!file.exists()) { result.error("NOT_FOUND", "PDF 文件不存在: $path", null); return }
            val fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            val renderer = PdfRenderer(fd)
            if (pageIndex < 0 || pageIndex >= renderer.pageCount) {
                renderer.close(); fd.close()
                result.error("INVALID_PAGE", "页码无效: $pageIndex (共 ${renderer.pageCount} 页)", null)
                return
            }
            val page = renderer.openPage(pageIndex)
            val bitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            java.io.FileOutputStream(java.io.File(outputPath)).use { out ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            }
            page.close(); renderer.close(); fd.close(); bitmap.recycle()
            result.success(outputPath)
        } catch (e: Exception) {
            Log.e("PDF", "renderPageAsImage failed: $path page $pageIndex", e)
            result.error("PDF_RENDER_ERROR", e.message, null)
        }
    }

    private fun handleGetPageCount(path: String, result: MethodChannel.Result) {
        try {
            val file = java.io.File(path)
            if (!file.exists()) { result.error("NOT_FOUND", "PDF 文件不存在: $path", null); return }
            val fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            val renderer = PdfRenderer(fd)
            val count = renderer.pageCount
            renderer.close(); fd.close()
            result.success(count)
        } catch (e: Exception) {
            Log.e("PDF", "getPageCount failed: $path", e)
            result.error("PDF_ERROR", e.message, null)
        }
    }

    private fun handleExtractDocText(path: String, result: MethodChannel.Result) {
        try {
            val file = java.io.File(path)
            if (!file.exists()) { result.error("NOT_FOUND", "DOC 文件不存在: $path", null); return }
            val hwpfDoc = org.apache.poi.hwpf.HWPFDocument(java.io.FileInputStream(file))
            val extractor = org.apache.poi.hwpf.extractor.WordExtractor(hwpfDoc)
            result.success(extractor.text)
            extractor.close(); hwpfDoc.close()
        } catch (e: Exception) {
            Log.e("DOC", "extractDocText failed: $path", e)
            result.error("DOC_ERROR", e.message, null)
        }
    }

    // ==================== OCR ====================

    private fun handleOcrLoad(result: MethodChannel.Result) {
        try {
            Log.i("OCR", "handleOcrLoad called")
            if (ocrEngine == null) ocrEngine = OcrEngine()
            if (ocrEngine!!.isLoaded) {
                Log.i("OCR", "Model already loaded")
                result.success(true); return
            }
            Log.i("OCR", "Loading model...")
            val loaded = ocrEngine!!.load(assets, false)
            Log.i("OCR", "Model load result: $loaded")
            if (loaded) {
                result.success(true)
            } else {
                result.error("OCR_LOAD_ERROR", "模型加载失败", null)
            }
        } catch (e: Exception) {
            Log.e("OCR", "load failed", e)
            result.error("OCR_LOAD_ERROR", e.message, null)
        }
    }

    private fun handleOcrRecognize(imagePath: String, result: MethodChannel.Result) {
        try {
            Log.i("OCR", "Starting recognize: $imagePath")
            if (ocrEngine == null || !ocrEngine!!.isLoaded) {
                Log.e("OCR", "Engine not loaded")
                result.error("OCR_NOT_READY", "OCR 模型未加载", null)
                return
            }
            val text = ocrEngine!!.recognize(imagePath)
            Log.i("OCR", "Recognize done: ${text.take(50)}")
            result.success(text)
        } catch (e: Exception) {
            Log.e("OCR", "recognize failed: $imagePath", e)
            result.error("OCR_ERROR", e.message, null)
        }
    }

    private fun handleOcrDispose(result: MethodChannel.Result) {
        try { ocrEngine?.dispose(); ocrEngine = null; result.success(true) }
        catch (e: Exception) { result.error("OCR_ERROR", e.message, null) }
    }

    // ==================== 分享 ====================

    private fun handleShareIntent(intent: Intent?) {
        if (intent == null || intent.action != Intent.ACTION_SEND) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        val mimeType = intent.type
        val imageUri: Uri? = if (mimeType?.startsWith("image/") == true) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        } else null
        if (text != null || imageUri != null) {
            getSharedPreferences("share_intent", Context.MODE_PRIVATE).edit().apply {
                putString("shared_text", text)
                if (imageUri != null) {
                    putString("shared_uri", imageUri.toString())
                    putString("shared_mime", mimeType)
                }
                apply()
            }
        }
    }

    companion object EngineHolder {
        private var backgroundEngine: FlutterEngine? = null

        fun createBackgroundEngine(context: Context): FlutterEngine {
            backgroundEngine?.let { return it }
            val engine = FlutterEngine(context.applicationContext)
            engine.dartExecutor.executeDartEntrypoint(
                io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint.createDefault()
            )
            GeneratedPluginRegistrant.registerWith(engine)
            backgroundEngine = engine
            return engine
        }

        fun releaseBackgroundEngine() {
            backgroundEngine?.destroy()
            backgroundEngine = null
        }
    }
}
