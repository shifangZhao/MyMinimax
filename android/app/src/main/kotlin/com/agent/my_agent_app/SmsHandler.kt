package com.agent.my_agent_app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Telephony
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class SmsHandler(private val context: Context) {
    companion object {
        private const val TAG = "SmsHandler"
        private const val PENDING_TIMEOUT_MS = 60_000L // 1 minute
    }

    // Pending delete state — set when user needs to make us default first
    private var pendingSmsId: String? = null
    private var pendingResult: MethodChannel.Result? = null
    private var previousDefaultPackage: String? = null
    private var pendingStartMs: Long = 0L

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "readInbox" -> readInbox(call, result)
            "getConversations" -> getConversations(call, result)
            "send" -> sendSms(
                call.argument<String>("phoneNumber") ?: "",
                call.argument<String>("message") ?: "",
                result
            )
            "deleteSms" -> deleteSms(call.argument<String>("smsId") ?: "", result)
            else -> result.notImplemented()
        }
    }

    /**
     * Called from MainActivity.onResume().
     * If there's a pending delete and we've become the default SMS app,
     * execute the delete and restore the previous default.
     */
    fun processPendingDelete() {
        val smsId = pendingSmsId ?: return
        val result = pendingResult ?: return

        // Timeout check
        if (System.currentTimeMillis() - pendingStartMs > PENDING_TIMEOUT_MS) {
            Log.w(TAG, "Pending delete timed out")
            clearPending()
            result.error("TIMEOUT", "操作超时，请重试", null)
            return
        }

        // Check if we're now the default SMS app
        if (!isDefaultSmsApp()) {
            // Not yet — user may still be in the dialog
            return
        }

        // We're now default — execute delete
        try {
            val deleted = context.contentResolver.delete(
                Telephony.Sms.CONTENT_URI,
                "_id = ?",
                arrayOf(smsId)
            )
            Log.i(TAG, "Delete result: $deleted rows for SMS $smsId")

            // Restore the previous default SMS app
            restoreDefaultSmsApp()

            clearPending()

            if (deleted > 0) {
                result.success("短信已删除")
            } else {
                result.error("NOT_FOUND", "短信不存在", null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Delete after becoming default failed", e)
            restoreDefaultSmsApp()
            clearPending()
            result.error("ERROR", e.message, null)
        }
    }

    /**
     * Returns true if there's an active pending delete operation.
     */
    fun hasPendingDelete(): Boolean = pendingSmsId != null

    private fun isDefaultSmsApp(): Boolean {
        return try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
                Telephony.Sms.getDefaultSmsPackage(context) == context.packageName
            } else {
                true // pre-KitKat no restriction
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun restoreDefaultSmsApp() {
        val prev = previousDefaultPackage
        if (prev.isNullOrEmpty() || prev == context.packageName) return
        try {
            // Launch ACTION_CHANGE_DEFAULT targeting the original app
            val intent = Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT)
            intent.putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, prev)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            Log.i(TAG, "Restoring default SMS app to: $prev")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to restore default SMS app: $e")
        }
    }

    private fun launchChangeDefaultDialog() {
        val intent = Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT)
        intent.putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, context.packageName)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    private fun deleteSms(smsId: String, result: MethodChannel.Result) {
        if (smsId.isEmpty()) {
            result.error("INVALID", "smsId 不能为空", null)
            return
        }

        // Attempt 1: Direct delete (works if we're the default SMS app)
        try {
            val deleted = context.contentResolver.delete(
                Telephony.Sms.CONTENT_URI,
                "_id = ?",
                arrayOf(smsId)
            )
            if (deleted > 0) {
                result.success("短信已删除")
                return
            }
            // deleted == 0 could mean not found OR permission issue
            // Fall through to default-app flow
        } catch (e: SecurityException) {
            // Not default SMS app — fall through to the prompt flow
        } catch (e: Exception) {
            // Other error on direct attempt — fall through
        }

        // Attempt 2: Prompt user to make us default, then delete
        try {
            previousDefaultPackage = try {
                Telephony.Sms.getDefaultSmsPackage(context)
            } catch (_: Exception) { null }

            // If we're somehow already default, try once more
            if (previousDefaultPackage == context.packageName) {
                try {
                    val deleted = context.contentResolver.delete(
                        Telephony.Sms.CONTENT_URI,
                        "_id = ?",
                        arrayOf(smsId)
                    )
                    if (deleted > 0) {
                        result.success("短信已删除")
                    } else {
                        result.error("NOT_FOUND", "短信不存在", null)
                    }
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
                return
            }

            // Save pending state
            pendingSmsId = smsId
            pendingResult = result
            pendingStartMs = System.currentTimeMillis()

            // Launch system dialog for user to set this app as default SMS app
            launchChangeDefaultDialog()

            // result will be called from processPendingDelete() after user returns
        } catch (e: Exception) {
            clearPending()
            result.error("ERROR", e.message, null)
        }
    }

    private fun clearPending() {
        pendingSmsId = null
        pendingResult = null
        previousDefaultPackage = null
        pendingStartMs = 0L
    }

    // ── readInbox, getConversations, sendSms ────────────────────

    private fun readInbox(call: MethodCall, result: MethodChannel.Result) {
        try {
            val limit = call.argument<Int>("limit") ?: 50
            val senderFilter = call.argument<String>("senderFilter")

            val projection = arrayOf(
                Telephony.Sms._ID,
                Telephony.Sms.ADDRESS,
                Telephony.Sms.BODY,
                Telephony.Sms.DATE,
                Telephony.Sms.DATE_SENT,
                Telephony.Sms.READ,
                Telephony.Sms.TYPE
            )

            val selection = if (senderFilter != null && senderFilter.isNotEmpty()) {
                Telephony.Sms.ADDRESS + " LIKE ?"
            } else {
                null
            }
            val selectionArgs = if (senderFilter != null && senderFilter.isNotEmpty()) {
                arrayOf("%$senderFilter%")
            } else {
                null
            }

            val cursor = context.contentResolver.query(
                Telephony.Sms.CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                Telephony.Sms.DATE + " DESC LIMIT $limit"
            )

            val messages = mutableListOf<Map<String, Any>>()
            cursor?.use {
                while (it.moveToNext()) {
                    val type = it.getInt(it.getColumnIndexOrThrow(Telephony.Sms.TYPE))
                    messages.add(mapOf(
                        "smsId" to it.getString(it.getColumnIndexOrThrow(Telephony.Sms._ID)),
                        "address" to (it.getString(it.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)) ?: ""),
                        "body" to (it.getString(it.getColumnIndexOrThrow(Telephony.Sms.BODY)) ?: ""),
                        "date" to it.getLong(it.getColumnIndexOrThrow(Telephony.Sms.DATE)),
                        "dateSent" to it.getLong(it.getColumnIndexOrThrow(Telephony.Sms.DATE_SENT)),
                        "read" to (it.getInt(it.getColumnIndexOrThrow(Telephony.Sms.READ)) == 1),
                        "type" to (if (type == Telephony.Sms.MESSAGE_TYPE_INBOX) "inbox" else "sent")
                    ))
                }
            }
            result.success(messages)
        } catch (e: SecurityException) {
            result.error("PERMISSION", "短信权限未授予", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun getConversations(call: MethodCall, result: MethodChannel.Result) {
        try {
            val limit = call.argument<Int>("limit") ?: 20

            val uri = Telephony.Sms.Conversations.CONTENT_URI
            val projection = arrayOf(
                Telephony.Sms.Conversations.SNIPPET,
                Telephony.Sms.Conversations.MESSAGE_COUNT
            )

            val cursor = context.contentResolver.query(
                uri,
                projection,
                null, null,
                Telephony.Sms.Conversations.DEFAULT_SORT_ORDER + " LIMIT $limit"
            )

            val conversations = mutableListOf<Map<String, Any>>()
            cursor?.use {
                while (it.moveToNext()) {
                    conversations.add(mapOf(
                        "snippet" to (it.getString(it.getColumnIndexOrThrow(Telephony.Sms.Conversations.SNIPPET)) ?: ""),
                        "messageCount" to it.getInt(it.getColumnIndexOrThrow(Telephony.Sms.Conversations.MESSAGE_COUNT))
                    ))
                }
            }
            result.success(conversations)
        } catch (e: Exception) {
            try {
                val limit = call.argument<Int>("limit") ?: 20
                val projection = arrayOf(
                    Telephony.Sms.ADDRESS,
                    Telephony.Sms.BODY,
                    Telephony.Sms.DATE
                )
                val cursor = context.contentResolver.query(
                    Telephony.Sms.CONTENT_URI,
                    projection,
                    null, null,
                    Telephony.Sms.DATE + " DESC"
                )

                val conversations = mutableListOf<Map<String, Any>>()
                val seen = mutableSetOf<String>()
                cursor?.use {
                    while (it.moveToNext() && conversations.size < limit) {
                        val addr = it.getString(it.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)) ?: ""
                        if (seen.add(addr)) {
                            conversations.add(mapOf(
                                "address" to addr,
                                "snippet" to (it.getString(it.getColumnIndexOrThrow(Telephony.Sms.BODY)) ?: ""),
                                "lastDate" to it.getLong(it.getColumnIndexOrThrow(Telephony.Sms.DATE))
                            ))
                        }
                    }
                }
                result.success(conversations)
            } catch (e2: SecurityException) {
                result.error("PERMISSION", "短信权限未授予", null)
            } catch (e2: Exception) {
                result.error("ERROR", e2.message, null)
            }
        }
    }

    private fun sendSms(phoneNumber: String, message: String, result: MethodChannel.Result) {
        try {
            if (phoneNumber.isEmpty()) {
                result.error("INVALID", "电话号码不能为空", null)
                return
            }
            if (message.isEmpty()) {
                result.error("INVALID", "短信内容不能为空", null)
                return
            }

            val values = android.content.ContentValues().apply {
                put(Telephony.Sms.ADDRESS, phoneNumber)
                put(Telephony.Sms.BODY, message)
            }
            context.contentResolver.insert(Telephony.Sms.Sent.CONTENT_URI, values)

            try {
                val smsManager = android.telephony.SmsManager.getDefault()
                smsManager.sendTextMessage(phoneNumber, null, message, null, null)
            } catch (_: Exception) {}

            result.success("短信已发送到: $phoneNumber")
        } catch (e: SecurityException) {
            result.error("PERMISSION", "短信发送权限未授予", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }
}
