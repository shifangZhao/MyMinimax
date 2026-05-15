import 'dart:convert';
import '../../features/tools/domain/tool.dart';
import 'tool_loop_detector.dart';

/// Result of executing one round of tool calls.
class ToolExecutionResult {

  const ToolExecutionResult({
    required this.toolResultBlocks,
    this.fatalError,
  });
  final List<Map<String, dynamic>> toolResultBlocks;
  final String? fatalError;
}

/// 错误分类
enum ErrorCategory {
  transient,    // 超时/网络错误，可重试
  pathNotFound,  // 文件路径不存在
  permission,    // 权限不足
  invalidArgs,   // 参数错误
  rateLimit,     // 频率限制
  unknown,
}

/// 错误诊断
class ErrorDiagnosis {
  const ErrorDiagnosis({
    required this.category,
    required this.cause,
    required this.suggestion,
  });
  final ErrorCategory category;
  final String cause;
  final String suggestion;
}

/// Handles execution of tool_use blocks: calls the injected [executeTool]
/// callback, classifies transient errors for retry, tracks per-tool error
/// streaks, and records each call in the [ToolLoopDetector].
class ToolExecutionHandler {
  final Map<String, int> _errorStreak = {};

  /// Execute all tool_use blocks in [blocks].
  ///
  /// [onToolStart] is called before each tool with (toolName, argsJson).
  /// [onFatal] is called if the error streak reaches the hard-stop threshold.
  /// [executeTool] is the tool execution callback injected by the caller.
  /// [loopDetector] is optional and receives each completed call.
  Future<ToolExecutionResult> executeTools({
    required List<Map<String, dynamic>> blocks,
    required Future<ToolResult> Function(String name, Map<String, dynamic> args) executeTool,
    ToolLoopDetector? loopDetector,
    void Function(String toolName, String argsJson)? onToolStart,
    void Function(String reason)? onFatal,
  }) async {
    final toolResultBlocks = <Map<String, dynamic>>[];

    for (final tb in blocks) {
      final toolName = tb['name'] as String;
      final toolId = tb['id'] as String;
      final rawInput = tb['input'];
      final args = rawInput is Map ? Map<String, dynamic>.from(rawInput) : <String, dynamic>{};
      final isTruncated = tb['_truncated'] == true;

      onToolStart?.call(toolName, jsonEncode(args));

      // Execute with transient retry
      ToolResult result;
      try {
        result = await executeTool(toolName, args);
      } catch (e) {
        print('[tool] error: \$e');
        result = ToolResult(toolName: toolName, success: false, output: '', error: e.toString());
      }
      if (!result.success && _isTransientError(result.error)) {
        try {
          result = await executeTool(toolName, args);
        } catch (e) {
          print('[tool] error: \$e');
          result = ToolResult(toolName: toolName, success: false, output: '', error: e.toString());
        }
      }

      // Error streak tracking
      String? failNudge;
      if (!result.success) {
        final failCount = (_errorStreak[toolName] ?? 0) + 1;
        _errorStreak[toolName] = failCount;

        if (failCount >= 3 && failCount < 6) {
          final diag = _classifyError(result.error);
          failNudge = "\n\n[SYSTEM: TOOL FAILURE DIAGNOSIS]\n"
              "错误类型: ${diag.category.name}\n"
              "错误信息: ${result.error ?? 'unknown'}\n"
              "可能原因: ${diag.cause}\n"
              "建议: ${diag.suggestion}\n"
              "已连续失败 $failCount 次 — 停止调用此工具，换个方式或向用户解释。";
        }
        if (failCount >= 6) {
          _errorStreak.clear();
          onFatal?.call('$toolName 已连续失败 $failCount 次，已自动暂停。请换个方式提问。');
          return ToolExecutionResult(
            toolResultBlocks: toolResultBlocks,
            fatalError: '$toolName consecutive failure limit reached',
          );
        }
      } else {
        _errorStreak.remove(toolName);
      }

      // Build result content
      final resultContent = result.success
          ? result.output
          : 'Error: ${result.error ?? 'unknown'}${failNudge ?? ''}${isTruncated ? '\n\n⚠ This tool call was truncated — input may be incomplete.' : ''}';

      toolResultBlocks.add({
        'type': 'tool_result',
        'tool_use_id': toolId,
        'content': resultContent,
      });

      loopDetector?.record(toolName, args, resultContent);
    }

    return ToolExecutionResult(toolResultBlocks: toolResultBlocks);
  }

  void clearErrors() => _errorStreak.clear();

  static bool _isTransientError(String? error) {
    if (error == null) return false;
    final lower = error.toLowerCase();
    return lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('connection') ||
        lower.contains('network') ||
        lower.contains('dns') ||
        lower.contains('refused') ||
        lower.contains('reset') ||
        lower.contains('unreachable') ||
        lower.contains('eof') ||
        lower.contains('broken pipe');
  }

  static ErrorDiagnosis _classifyError(String? error) {
    if (error == null) {
      return ErrorDiagnosis(category: ErrorCategory.unknown, cause: '未知错误', suggestion: '检查工具参数和网络连接');
    }

    final lower = error.toLowerCase();

    // 路径不存在
    if (lower.contains('not found') ||
        lower.contains('不存在') ||
        lower.contains('no such file') ||
        lower.contains('路径')) {
      return ErrorDiagnosis(
        category: ErrorCategory.pathNotFound,
        cause: '文件或路径不存在',
        suggestion: '确认路径是否正确，尝试列出父目录内容检查可用文件',
      );
    }

    // 权限不足
    if (lower.contains('permission') ||
        lower.contains('权限') ||
        lower.contains('access denied') ||
        lower.contains('readonly')) {
      return ErrorDiagnosis(
        category: ErrorCategory.permission,
        cause: '权限不足或文件只读',
        suggestion: '检查文件权限设置，尝试更换目录或使用管理员权限',
      );
    }

    // 参数错误
    if (lower.contains('invalid') ||
        lower.contains('缺少') ||
        lower.contains('missing') ||
        lower.contains('参数')) {
      return ErrorDiagnosis(
        category: ErrorCategory.invalidArgs,
        cause: '参数格式或值错误',
        suggestion: '检查工具参数格式和必填字段，确保参数类型正确',
      );
    }

    // 频率限制
    if (lower.contains('rate limit') ||
        lower.contains('too many') ||
        lower.contains('quota') ||
        lower.contains('频率')) {
      return ErrorDiagnosis(
        category: ErrorCategory.rateLimit,
        cause: '触发频率限制',
        suggestion: '降低操作频率，等待后重试',
      );
    }

    // 瞬态错误
    if (_isTransientError(error)) {
      return ErrorDiagnosis(
        category: ErrorCategory.transient,
        cause: '网络超时或连接问题',
        suggestion: '检查网络连接，等待后重试',
      );
    }

    return ErrorDiagnosis(
      category: ErrorCategory.unknown,
      cause: '未知错误类型',
      suggestion: '检查错误信息，尝试更换工具或简化操作',
    );
  }
}
