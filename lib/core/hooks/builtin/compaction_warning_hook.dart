import '../hook_pipeline.dart';

/// 压缩预警 Hook — 上下文压缩前保存摘要信息
Future<void> compactionWarningHook(HookContext ctx) async {
  final tokenCount = ctx.data['tokenCount'] as int? ?? 0;
  final threshold = ctx.data['threshold'] as int? ?? 197800;
  final conversationId = ctx.conversationId ?? 'unknown';

  if (tokenCount > threshold) {
    ctx.data['needsCompaction'] = true;
    ctx.data['compactionReason'] =
        '会话 $conversationId 的 token 数 ($tokenCount) 超过阈值 ($threshold)，'
        '建议压缩上下文以释放空间';
  }
}
