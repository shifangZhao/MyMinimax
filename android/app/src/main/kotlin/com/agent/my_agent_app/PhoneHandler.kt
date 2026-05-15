package com.agent.my_agent_app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.CallLog
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PhoneHandler(private val context: Context) {
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "call" -> makeCall(call.argument<String>("phoneNumber") ?: "", result)
            "getCallLog" -> getCallLog(call.argument<Int>("limit") ?: 50, result)
            else -> result.notImplemented()
        }
    }

    private fun makeCall(phoneNumber: String, result: MethodChannel.Result) {
        try {
            if (phoneNumber.isEmpty()) {
                result.error("INVALID", "电话号码不能为空", null)
                return
            }
            val intent = Intent(Intent.ACTION_CALL).apply {
                data = Uri.parse("tel:$phoneNumber")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            result.success("正在拨号: $phoneNumber")
        } catch (e: SecurityException) {
            result.error("PERMISSION", "电话权限未授予", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun getCallLog(limit: Int, result: MethodChannel.Result) {
        try {
            val projection = arrayOf(
                CallLog.Calls.NUMBER,
                CallLog.Calls.TYPE,
                CallLog.Calls.DATE,
                CallLog.Calls.DURATION,
                CallLog.Calls.CACHED_NAME,
                CallLog.Calls.CACHED_NUMBER_LABEL,
            )

            val cursor = context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                projection,
                null, null,
                CallLog.Calls.DATE + " DESC LIMIT $limit"
            )

            val calls = mutableListOf<Map<String, Any>>()
            cursor?.use {
                while (it.moveToNext()) {
                    val type = it.getInt(it.getColumnIndexOrThrow(CallLog.Calls.TYPE))
                    val typeStr = when (type) {
                        CallLog.Calls.INCOMING_TYPE -> "incoming"
                        CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                        CallLog.Calls.MISSED_TYPE -> "missed"
                        else -> "unknown"
                    }
                    calls.add(mapOf(
                        "number" to (it.getString(it.getColumnIndexOrThrow(CallLog.Calls.NUMBER)) ?: ""),
                        "type" to typeStr,
                        "date" to it.getLong(it.getColumnIndexOrThrow(CallLog.Calls.DATE)),
                        "duration" to it.getLong(it.getColumnIndexOrThrow(CallLog.Calls.DURATION)),
                        "name" to (it.getString(it.getColumnIndexOrThrow(CallLog.Calls.CACHED_NAME)) ?: ""),
                    ))
                }
            }
            result.success(calls)
        } catch (e: SecurityException) {
            result.error("PERMISSION", "通话记录权限未授予", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
}
