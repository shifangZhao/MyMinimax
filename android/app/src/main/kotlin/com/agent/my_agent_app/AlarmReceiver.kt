package com.agent.my_agent_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * 闹钟广播接收器 - 处理定时任务提醒
 * Android 14+ 要求静态广播必须声明 exported 属性
 */
class AlarmReceiver : BroadcastReceiver() {
    
    companion object {
        const val EXTRA_TASK_ID = "task_id"
        const val EXTRA_TASK_TITLE = "task_title"
        private const val CHANNEL_ID = "alarm_channel"
        private const val CHANNEL_NAME = "任务提醒"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        context ?: return
        intent ?: return
        
        val taskId = intent.getStringExtra(EXTRA_TASK_ID) ?: return
        val taskTitle = intent.getStringExtra(EXTRA_TASK_TITLE) ?: "任务提醒"
        
        showNotification(context, taskId, taskTitle)
    }

    private fun showNotification(context: Context, taskId: String, taskTitle: String) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        // 创建通知渠道（Android 8.0+）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "定时任务提醒通知"
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(channel)
        }
        
        // 创建点击意图 - 打开应用
        val mainIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("tapped_task_id", taskId)
        }
        
        val pendingIntent = PendingIntent.getActivity(
            context,
            taskId.hashCode(),
            mainIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val notification = android.app.Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(taskTitle.ifEmpty { "任务提醒" })
            .setContentText("点击查看任务详情")
            .setPriority(android.app.Notification.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()
        
        notificationManager.notify(taskId.hashCode(), notification)
    }
}