package com.agent.my_agent_app

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

class NotificationListenerService : NotificationListenerService() {
    companion object {
        private const val PREFS_NAME = "notif_buffer"
        private const val MAX_BUFFER = 100
        private const val KEY_NOTIFICATIONS = "notifications"

        fun isEnabled(context: Context): Boolean {
            val componentName = ComponentName(context, NotificationListenerService::class.java)
            val flat = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners"
            )
            return flat?.contains(componentName.flattenToString()) == true
        }

        fun getNotifications(context: Context, limit: Int = 50): List<Map<String, Any>> {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val json = prefs.getString(KEY_NOTIFICATIONS, "[]") ?: "[]"
            return try {
                val arr = JSONArray(json)
                val list = mutableListOf<Map<String, Any>>()
                val start = maxOf(0, arr.length() - limit)
                for (i in start until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    list.add(mapOf(
                        "packageName" to obj.optString("packageName", ""),
                        "appName" to obj.optString("appName", ""),
                        "title" to obj.optString("title", ""),
                        "text" to obj.optString("text", ""),
                        "timestamp" to obj.optLong("timestamp", 0L),
                        "key" to obj.optString("key", ""),
                    ))
                }
                list
            } catch (_: Exception) {
                emptyList()
            }
        }

        fun clearNotifications(context: Context) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit().putString(KEY_NOTIFICATIONS, "[]").apply()
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        sbn ?: return
        val notification = sbn.notification
        val extras = notification.extras
        val entry = JSONObject().apply {
            put("packageName", sbn.packageName)
            put("appName", getAppName(sbn.packageName))
            put("title", extras.getString(Notification.EXTRA_TITLE) ?: "")
            put("text", extras.getString(Notification.EXTRA_TEXT) ?: "")
            put("timestamp", sbn.postTime)
            put("key", sbn.key)
        }
        appendToBuffer(entry)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
    }

    private fun getAppName(packageName: String): String {
        return try {
            packageManager.getApplicationLabel(
                packageManager.getApplicationInfo(packageName, 0)
            ).toString()
        } catch (_: Exception) {
            packageName
        }
    }

    private fun appendToBuffer(entry: JSONObject) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val existing = prefs.getString(KEY_NOTIFICATIONS, "[]") ?: "[]"
        try {
            val arr = JSONArray(existing)
            arr.put(entry)
            while (arr.length() > MAX_BUFFER) arr.remove(0)
            prefs.edit().putString(KEY_NOTIFICATIONS, arr.toString()).apply()
        } catch (_: Exception) {}
    }
}
