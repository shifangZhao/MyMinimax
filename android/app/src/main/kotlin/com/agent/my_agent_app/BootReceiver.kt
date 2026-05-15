package com.agent.my_agent_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val prefs = context.getSharedPreferences("task_alarms", Context.MODE_PRIVATE)
        val alarmsJson = prefs.getString("alarms", null) ?: return

        try {
            val alarms = JSONArray(alarmsJson)
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            for (i in 0 until alarms.length()) {
                val alarm = alarms.getJSONObject(i)
                val taskId = alarm.getString("taskId")
                val title = alarm.getString("title")
                val dueMs = alarm.getLong("dueMs")

                if (dueMs <= System.currentTimeMillis()) continue

                val alarmIntent = Intent(context, AlarmReceiver::class.java).apply {
                    putExtra(AlarmReceiver.EXTRA_TASK_ID, taskId)
                    putExtra(AlarmReceiver.EXTRA_TASK_TITLE, title)
                }
                val pendingIntent = PendingIntent.getBroadcast(
                    context, i, alarmIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP, dueMs, pendingIntent
                    )
                } else {
                    alarmManager.setExact(AlarmManager.RTC_WAKEUP, dueMs, pendingIntent)
                }
            }
        } catch (_: Exception) {}
    }
}
