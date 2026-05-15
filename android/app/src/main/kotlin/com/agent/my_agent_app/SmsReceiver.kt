package com.agent.my_agent_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// Minimal receiver — only used to qualify this app as a candidate
// for the default SMS app picker (required by Android SMS role).
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {}
}
