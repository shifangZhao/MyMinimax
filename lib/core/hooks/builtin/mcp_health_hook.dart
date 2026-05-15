// ignore_for_file: avoid_dynamic_calls

import '../hook_pipeline.dart';

/// MCP 健康 Hook — fetchUrl/search 等网络工具调用前检查 MCP 连通性
///
/// 需要传入 McpClient 实例，在注册时闭包捕获。
Future<void> Function(HookContext) createMcpHealthHook(dynamic mcpClient) {
  return (HookContext ctx) async {
    final toolName = ctx.toolName;
    if (toolName == null) return;

    // 仅网络相关工具需要 MCP 检查
    const networkTools = {'fetchUrl', 'webSearch'};
    if (!networkTools.contains(toolName)) return;

    final health = mcpClient.health;
    if (health.status.name == 'unhealthy' && !health.canRetry) {
      ctx.data['blocked'] = true;
      ctx.data['blockReason'] = 'MCP 服务不可用（下次重试: ${health.nextRetryAfter}）';
      return;
    }

    // 触发一次健康探测
    final ok = await mcpClient.checkHealth();
    ctx.data['mcpHealthy'] = ok;

    if (!ok && !mcpClient.failOpen) {
      ctx.data['blocked'] = true;
      ctx.data['blockReason'] = 'MCP 服务健康检查失败，failOpen 已关闭';
    }
  };
}
