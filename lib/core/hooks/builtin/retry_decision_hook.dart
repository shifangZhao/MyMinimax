import '../hook_pipeline.dart';

/// 重试决策 Hook — 工具失败时分析错误类型，决定重试策略
Future<void> retryDecisionHook(HookContext ctx) async {
  final error = ctx.error ?? ctx.data['error'] as String? ?? '';
  final lowerError = error.toLowerCase();

  // 不可重试的错误类型
  const nonRetryable = [
    '安全限制',
    '安全策略',
    'blocked by safety',
    '缺少参数',
    '不存在的文件',
    'file not found',
    'unknown tool',
    '禁止',
  ];

  for (final pattern in nonRetryable) {
    if (lowerError.contains(pattern.toLowerCase())) {
      ctx.data['shouldRetry'] = false;
      ctx.data['retryReason'] = '不可重试的错误: $pattern';
      return;
    }
  }

  // 可重试的错误
  final attemptCount = ctx.data['attemptCount'] as int? ?? 0;
  const maxAttempts = 3;

  if (attemptCount >= maxAttempts) {
    ctx.data['shouldRetry'] = false;
    ctx.data['retryReason'] = '已达最大重试次数 ($maxAttempts)';
    return;
  }

  // 决定退避时间
  const baseDelayMs = 1000;
  final delayMs = baseDelayMs * (1 << attemptCount); // 指数退避

  // 网络/超时类错误
  if (lowerError.contains('timeout') ||
      lowerError.contains('超时') ||
      lowerError.contains('connection') ||
      lowerError.contains('网络') ||
      lowerError.contains('dio')) {
    ctx.data['shouldRetry'] = true;
    ctx.data['retryDelayMs'] = delayMs;
    ctx.data['retryReason'] = '网络/超时，自动重试';
    return;
  }

  // 文件被占用
  if (lowerError.contains('permission') ||
      lowerError.contains('权限') ||
      lowerError.contains('access denied')) {
    ctx.data['shouldRetry'] = false;
    ctx.data['retryReason'] = '权限不足';
    return;
  }

  // 默认：如果是工具执行失败（非输入校验失败），可重试
  if (lowerError.contains('失败') || lowerError.contains('failed') || lowerError.contains('error')) {
    ctx.data['shouldRetry'] = attemptCount < maxAttempts;
    ctx.data['retryDelayMs'] = delayMs;
    ctx.data['retryReason'] = '执行失败，尝试重试';
  } else {
    ctx.data['shouldRetry'] = false;
  }
}
