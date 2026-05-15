import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../storage/database_helper.dart';

/// Structured execution trace for a single agent session.
///
/// Use [begin] at session start, record events during execution,
/// then [flush] to persist to SQLite.
class AgentTracer {

  AgentTracer({
    required this.conversationId,
    required DatabaseHelper db,
    String? traceId,
  })  : _db = db,
        traceId = traceId ?? const Uuid().v4() {
    _sw.start();
  }
  final String traceId;
  final String conversationId;
  final List<Map<String, dynamic>> _events = [];
  final Stopwatch _sw = Stopwatch();
  final DatabaseHelper _db;

  void recordLlmCall({
    required String model,
    required int round,
    int? inputTokens,
    int? outputTokens,
    int? thinkingChars,
    int? thinkingBudget,
    int? latencyMs,
    bool? truncated,
    String? finishReason,
  }) {
    _events.add({
      'type': 'llm_call',
      'timestamp': _sw.elapsedMilliseconds,
      'round': round,
      'model': model,
      'input_tokens': inputTokens,
      'output_tokens': outputTokens,
      'thinking_chars': thinkingChars,
      'thinking_budget': thinkingBudget,
      'latency_ms': latencyMs,
      'truncated': truncated,
      'finish_reason': finishReason,
      'cache_read': _latestCacheRead,
      'cache_create': _latestCacheCreate,
      'cache_fresh': _latestCacheFresh,
    });
  }

  int _latestCacheRead = 0;
  int _latestCacheCreate = 0;
  int _latestCacheFresh = 0;

  /// 从 message_start 事件中捕获缓存性能指标，下次 [recordLlmCall] 时写入。
  void recordCacheUsage({
    required int cacheRead,
    required int cacheCreate,
    required int cacheFresh,
  }) {
    _latestCacheRead = cacheRead;
    _latestCacheCreate = cacheCreate;
    _latestCacheFresh = cacheFresh;
  }

  void recordToolCall({
    required String toolName,
    required bool success,
    required int latencyMs,
    String? argsPreview,
    String? resultPreview,
    String? error,
    int? round,
  }) {
    _events.add({
      'type': 'tool_call',
      'timestamp': _sw.elapsedMilliseconds,
      'round': round,
      'tool_name': toolName,
      'success': success,
      'latency_ms': latencyMs,
      'args_preview': _truncate(argsPreview, 200),
      'result_preview': _truncate(resultPreview, 200),
      'error': error,
    });
  }

  void recordError({
    required String category,
    required String message,
    bool recoverable = false,
    bool wasRetried = false,
    bool retrySuccess = false,
  }) {
    _events.add({
      'type': 'error',
      'timestamp': _sw.elapsedMilliseconds,
      'category': category,
      'message': message,
      'recoverable': recoverable,
      'was_retried': wasRetried,
      'retry_success': retrySuccess,
    });
  }

  void recordLoopDetection({
    required String nudge,
    required String severity, // 'soft' | 'hard'
    int? round,
  }) {
    _events.add({
      'type': 'loop_detection',
      'timestamp': _sw.elapsedMilliseconds,
      'round': round,
      'nudge': nudge,
      'severity': severity,
    });
  }

  void recordContextCompaction({
    required int tokensBefore,
    required int tokensAfter,
    required int messagesBefore,
    required int messagesAfter,
  }) {
    _events.add({
      'type': 'context_compaction',
      'timestamp': _sw.elapsedMilliseconds,
      'tokens_before': tokensBefore,
      'tokens_after': tokensAfter,
      'messages_before': messagesBefore,
      'messages_after': messagesAfter,
    });
  }

  /// Persist the trace to SQLite. Returns the trace ID.
  Future<String> flush() async {
    _sw.stop();
    final traceData = {
      'trace_id': traceId,
      'conversation_id': conversationId,
      'duration_ms': _sw.elapsedMilliseconds,
      'event_count': _events.length,
      'events': _events,
    };
    await _db.insertAgentTrace(
      id: traceId,
      conversationId: conversationId,
      traceData: jsonEncode(traceData),
    );
    return traceId;
  }

  /// Number of events recorded so far.
  int get eventCount => _events.length;

  static String _truncate(String? s, int maxLen) {
    if (s == null || s.isEmpty) return '';
    if (s.length <= maxLen) return s;
    return '${s.substring(0, maxLen)}...';
  }
}
