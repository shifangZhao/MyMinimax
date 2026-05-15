package com.agent.my_agent_app

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class AgentTaskService : Service() {
    companion object {
        const val TAG = "AgentTaskService"
        const val CHANNEL_ID = "agent_task_channel"
        const val EXTRA_TASK_ID = "task_id"
        const val EXTRA_TASK_TITLE = "task_title"
        const val EXTRA_TASK_DESCRIPTION = "task_description"
        const val NOTIFICATION_ID = 2001
        const val RESULT_NOTIFY_ID = 3001
        private const val ENGINE_ID = "agent_background_engine"
    }

    private var flutterEngine: FlutterEngine? = null
    private var agentChannel: MethodChannel? = null
    private var pendingTaskId: String? = null
    private var pendingTaskTitle: String? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        var taskId = intent?.getStringExtra(EXTRA_TASK_ID) ?: ""
        var title = intent?.getStringExtra(EXTRA_TASK_TITLE) ?: ""
        var description = intent?.getStringExtra(EXTRA_TASK_DESCRIPTION) ?: ""

        if (taskId.isEmpty()) {
            stopSelf()
            return START_NOT_STICKY
        }

        // 如果从 Alarm 启动（缺少 description），从 SharedPreferences 加载
        if (description.isEmpty()) {
            val prefs = getSharedPreferences("task_alarms", Context.MODE_PRIVATE)
            val contextJson = prefs.getString("task_context_$taskId", null)
            if (contextJson != null) {
                try {
                    val ctx = org.json.JSONObject(contextJson)
                    description = ctx.optString("taskDesc", description)
                    if (title.isEmpty()) title = ctx.optString("taskTitle", title)
                } catch (_: Exception) {}
            }
        }

        // 如果还是没有 title，从 alarms 列表查找
        if (title.isEmpty()) {
            val prefs = getSharedPreferences("task_alarms", Context.MODE_PRIVATE)
            val alarmsJson = prefs.getString("task_alarms_json", null)
            if (alarmsJson != null) {
                try {
                    val alarms = JSONArray(alarmsJson)
                    for (i in 0 until alarms.length()) {
                        val alarm = alarms.getJSONObject(i)
                        if (alarm.optString("taskId") == taskId) {
                            title = alarm.optString("title", "定时任务")
                            break
                        }
                    }
                } catch (_: Exception) {}
            }
        }

        pendingTaskId = taskId
        pendingTaskTitle = title

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Agent 执行中")
            .setContentText(title)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
        startForeground(NOTIFICATION_ID, notification)

        // 初始化或获取后台 FlutterEngine
        if (flutterEngine == null) {
            try {
                flutterEngine = MainActivity.EngineHolder.createBackgroundEngine(this)
                agentChannel = MethodChannel(
                    flutterEngine!!.dartExecutor.binaryMessenger,
                    "com.myminimax/agent_engine"
                )
            } catch (e: Exception) {
                Log.e(TAG, "Failed to create FlutterEngine: $e")
                showResultNotification(taskId, title, "Agent 引擎启动失败: ${e.message}")
                stopSelf()
                return START_NOT_STICKY
            }
        }

        // 通过 MethodChannel 让 Dart 后台执行任务
        agentChannel?.invokeMethod("executeTask", mapOf(
            "taskId" to taskId,
            "title" to title,
            "description" to description
        ), object : MethodChannel.Result {
            override fun success(result: Any?) {
                val resultMap = result as? Map<*, *>
                val finalResult = resultMap?.get("result") as? String ?: ""
                onTaskComplete(taskId, title, finalResult)
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                Log.e(TAG, "Agent error: $errorCode - $errorMessage")
                onTaskComplete(taskId, title, "执行失败: $errorMessage")
            }

            override fun notImplemented() {
                Log.e(TAG, "Agent method not implemented")
                onTaskComplete(taskId, title, "Agent 引擎方法未实现")
            }
        })

        return START_NOT_STICKY
    }

    private fun onTaskComplete(taskId: String, title: String, result: String) {
        showResultNotification(taskId, title, result)

        // 尝试回传结果给 Dart（App 在前台时）
        TaskResultRelay.post(taskId, result)

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        flutterEngine = null
        agentChannel = null
        MainActivity.EngineHolder.releaseBackgroundEngine()
        super.onDestroy()
    }

    // ═══════════════════════════════════════════
    // 通知
    // ═══════════════════════════════════════════

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Agent 任务",
                NotificationManager.IMPORTANCE_LOW
            ).apply { description = "Agent 后台任务执行中" }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)

            val resultChannel = NotificationChannel(
                "agent_result",
                "Agent 结果",
                NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "Agent 任务执行结果" }
            manager.createNotificationChannel(resultChannel)
        }
    }

    private fun showResultNotification(taskId: String, taskTitle: String, result: String) {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val displayResult = if (result.length > 200) result.take(200) + "…" else result

        val notification = NotificationCompat.Builder(this, "agent_result")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Agent: $taskTitle")
            .setContentText(displayResult)
            .setStyle(NotificationCompat.BigTextStyle().bigText(result))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(pendingIntent, true)
            .build()

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(RESULT_NOTIFY_ID, notification)

        // 保存完整对话记录到 SharedPreferences（供 App 打开后同步到定时任务会话）
        val prefs = getSharedPreferences("task_alarms", Context.MODE_PRIVATE)
        val resultsJson = prefs.getString("agent_results", "[]") ?: "[]"
        try {
            val results = JSONArray(resultsJson)
            results.put(JSONObject().apply {
                put("type", "task_execution")
                put("taskId", taskId)
                put("taskTitle", taskTitle)
                put("userMessage", "执行定时任务: $taskTitle")
                put("aiResponse", result)
                put("timestamp", System.currentTimeMillis())
            })
            while (results.length() > 50) results.remove(0)
            prefs.edit().putString("agent_results", results.toString()).apply()
        } catch (_: Exception) {}
    }
}
