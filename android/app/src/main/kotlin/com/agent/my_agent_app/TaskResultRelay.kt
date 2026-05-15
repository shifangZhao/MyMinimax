package com.agent.my_agent_app

import io.flutter.plugin.common.EventChannel

/// 任务结果中转站：持有 EventChannel.EventSink，供 AgentTaskService 推送结果到 Dart。
/// 不依赖 Activity 生命周期 — EventSink 由 Flutter Engine 管理。
object TaskResultRelay {
    var sink: EventChannel.EventSink? = null

    fun post(taskId: String, result: String) {
        try {
            sink?.success(mapOf(
                "taskId" to taskId,
                "result" to result
            ))
        } catch (_: Exception) {}
    }
}
