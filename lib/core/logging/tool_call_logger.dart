/// 结构化工具调用日志
///
/// 每次工具调用记录到 tool_calls 表，支持 start/end 分段写入以精确计算耗时。
library;

import 'dart:math';
import '../storage/database_helper.dart';

class ToolCallLogger {

  ToolCallLogger(this._db);
  final DatabaseHelper _db;
  final Map<String, DateTime> _activeTimers = {};

  /// 开始一次工具调用，返回 correlation ID
  Future<String> logCallStart({
    required String conversationId,
    required String toolName,
    required String inputSummary,
    String? messageId,
    double? riskScore,
  }) async {
    final guid = _generateId();
    _activeTimers[guid] = DateTime.now();

    await _db.insertToolCall(
      id: guid,
      conversationId: conversationId,
      messageId: messageId,
      toolName: toolName,
      inputSummary: _truncate(inputSummary, 500),
      success: false,
      riskScore: riskScore,
    );
    return guid;
  }

  /// 结束一次工具调用，写入结果和耗时
  Future<void> logCallEnd(
    String correlationId, {
    required bool success,
    required String outputSummary,
  }) async {
    final startTime = _activeTimers.remove(correlationId);
    final durationMs = startTime != null
        ? DateTime.now().difference(startTime).inMilliseconds
        : 0;

    await _db.updateToolCallEnd(
      id: correlationId,
      success: success,
      outputSummary: _truncate(outputSummary, 500),
      durationMs: durationMs,
    );
  }

  Future<List<Map<String, dynamic>>> getRecentCalls(
    String conversationId, {
    int limit = 50,
  }) =>
      _db.getToolCallsForConversation(conversationId, limit: limit);

  Future<Map<String, dynamic>> getStats(String conversationId) =>
      _db.getToolCallStats(conversationId);

  Future<void> deleteForConversation(String conversationId) =>
      _db.deleteToolCallsForConversation(conversationId);

  int get activeCalls => _activeTimers.length;

  String _truncate(String text, int maxLen) =>
      text.length <= maxLen ? text : '${text.substring(0, maxLen)}...';

  String _generateId() {
    final now = DateTime.now();
    return 'tool_${now.millisecondsSinceEpoch}_${_randomHex(6)}';
  }

  String _randomHex(int length) {
    final r = Random();
    return List.generate(length, (_) => r.nextInt(16).toRadixString(16)).join();
  }
}
