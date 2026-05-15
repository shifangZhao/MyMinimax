package com.agent.my_agent_app

import android.content.ContentValues
import android.content.Context
import android.provider.CalendarContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class CalendarHandler(private val context: Context) {
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "query" -> queryEvents(call, result)
            "create" -> createEvent(call, result)
            "delete" -> deleteEvent(call.argument("eventId") ?: "", result)
            else -> result.notImplemented()
        }
    }

    private fun queryEvents(call: MethodCall, result: MethodChannel.Result) {
        try {
            val startMs = call.argument<Long>("startMs") ?: (System.currentTimeMillis() - 86400000L)
            val endMs = call.argument<Long>("endMs") ?: (System.currentTimeMillis() + 7L * 86400000L)

            val projection = arrayOf(
                CalendarContract.Instances.EVENT_ID,
                CalendarContract.Instances.TITLE,
                CalendarContract.Instances.DESCRIPTION,
                CalendarContract.Instances.BEGIN,
                CalendarContract.Instances.END,
                CalendarContract.Instances.EVENT_LOCATION,
                CalendarContract.Instances.ALL_DAY,
                CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
            )

            val cursor = CalendarContract.Instances.query(
                context.contentResolver,
                projection,
                startMs, endMs
            ) ?: run {
                result.success(emptyList<Map<String, Any>>())
                return
            }

            val events = mutableListOf<Map<String, Any>>()
            cursor.use {
                while (it.moveToNext()) {
                    events.add(mapOf(
                        "eventId" to it.getLong(it.getColumnIndexOrThrow(CalendarContract.Instances.EVENT_ID)),
                        "title" to (it.getString(it.getColumnIndexOrThrow(CalendarContract.Instances.TITLE)) ?: ""),
                        "description" to (it.getString(it.getColumnIndexOrThrow(CalendarContract.Instances.DESCRIPTION)) ?: ""),
                        "beginMs" to it.getLong(it.getColumnIndexOrThrow(CalendarContract.Instances.BEGIN)),
                        "endMs" to it.getLong(it.getColumnIndexOrThrow(CalendarContract.Instances.END)),
                        "location" to (it.getString(it.getColumnIndexOrThrow(CalendarContract.Instances.EVENT_LOCATION)) ?: ""),
                        "allDay" to (it.getInt(it.getColumnIndexOrThrow(CalendarContract.Instances.ALL_DAY)) == 1),
                        "calendarName" to (it.getString(it.getColumnIndexOrThrow(CalendarContract.Instances.CALENDAR_DISPLAY_NAME)) ?: ""),
                    ))
                }
            }
            result.success(events)
        } catch (e: SecurityException) {
            result.error("PERMISSION", "日历权限未授予", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun createEvent(call: MethodCall, result: MethodChannel.Result) {
        try {
            val title = call.argument<String>("title") ?: ""
            val description = call.argument<String>("description") ?: ""
            val startMs = call.argument<Long>("startMs") ?: System.currentTimeMillis()
            val endMs = call.argument<Long>("endMs") ?: (startMs + 3600000L)

            if (title.isEmpty()) {
                result.error("INVALID", "标题不能为空", null)
                return
            }

            val values = ContentValues().apply {
                put(CalendarContract.Events.DTSTART, startMs)
                put(CalendarContract.Events.DTEND, endMs)
                put(CalendarContract.Events.TITLE, title)
                put(CalendarContract.Events.DESCRIPTION, description)
                put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
                put(CalendarContract.Events.CALENDAR_ID, 1) // Default calendar
            }

            val uri = context.contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
            if (uri != null) {
                val eventId = uri.lastPathSegment ?: ""
                result.success(mapOf(
                    "eventId" to eventId,
                    "message" to "日历事件已创建: $title"
                ))
            } else {
                result.error("ERROR", "创建日历事件失败", null)
            }
        } catch (e: SecurityException) {
            result.error("PERMISSION", "日历写入权限未授予", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun deleteEvent(eventId: String, result: MethodChannel.Result) {
        try {
            if (eventId.isEmpty()) {
                result.error("INVALID", "eventId 不能为空", null)
                return
            }

            val deleted = context.contentResolver.delete(
                CalendarContract.Events.CONTENT_URI,
                CalendarContract.Events._ID + " = ?",
                arrayOf(eventId)
            )

            if (deleted > 0) {
                result.success("日历事件已删除")
            } else {
                result.error("NOT_FOUND", "日历事件不存在", null)
            }
        } catch (e: SecurityException) {
            result.error("PERMISSION", "日历写入权限未授予", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
}
