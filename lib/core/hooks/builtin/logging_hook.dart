import 'dart:convert';
import '../hook_pipeline.dart';
import '../../logging/tool_call_logger.dart';
import '../../storage/database_helper.dart';

/// 日志 Hook — afterToolUse 时记录工具调用到 tool_calls 表
///
/// async=true: 不阻塞主流程
Future<void> Function(HookContext) createLoggingHook(DatabaseHelper db) {
  final logger = ToolCallLogger(db);

  return (HookContext ctx) async {
    final toolName = ctx.toolName;
    if (toolName == null) return;

    final convId = ctx.conversationId ?? 'unknown';
    final params = ctx.toolParams ?? {};
    final success = ctx.data['success'] == true;
    final output = ctx.data['output'] as String? ?? '';
    final callId = ctx.data['callId'] as String?;

    if (callId != null) {
      await logger.logCallEnd(callId, success: success, outputSummary: output);
    } else {
      // 没有 callId 时直接写入完整记录
      await db.insertToolCall(
        id: 'tool_${DateTime.now().millisecondsSinceEpoch}_late',
        conversationId: convId,
        toolName: toolName,
        inputSummary: jsonEncode(params),
        outputSummary: output,
        success: success,
        durationMs: null,
      );
    }
  };
}
