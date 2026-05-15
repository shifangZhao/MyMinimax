/// MCP 服务器注册中心 — 管理多个 MCP 服务器
///
/// 职责:
/// 1. 注册/移除 MCP 服务器
/// 2. 统一工具发现 (tools/list)
/// 3. 工具路由 (tools/call → 正确的服务器)
/// 4. 全局工具列表供给 ToolRegistry
library;

import 'mcp_client.dart';
import 'mcp_protocol.dart';
import '../tools/tool_module.dart';
import '../tools/tool_registry.dart';
import '../tools/tool_groups.dart';
import '../../features/tools/domain/tool.dart';

class McpRegistry {
  McpRegistry._();
  static final McpRegistry _defaultInstance = McpRegistry._();
  static McpRegistry? _override;

  static McpRegistry get instance => _override ?? _defaultInstance;
  static void setTestInstance(McpRegistry v) => _override = v;
  static void reset() => _override = null;

  final Map<String, McpClient> _servers = {};
  final Map<String, String> _toolToServer = {}; // toolName → serverName

  // ---- 服务器管理 ----

  McpClient? register(McpServerConfig config) {
    // 同名则覆盖
    final client = McpClient(config: config);
    _servers[config.name] = client;
    return client;
  }

  void unregister(String serverName) {
    _servers.remove(serverName);
    _toolToServer.removeWhere((_, s) => s == serverName);
  }

  McpClient? getServer(String name) => _servers[name];
  List<McpClient> get allServers => _servers.values.toList();
  List<String> get serverNames => _servers.keys.toList();
  int get serverCount => _servers.length;

  // ---- 工具发现 ----

  /// 连接所有服务器并发现工具
  Future<Map<String, McpDiscoveredTools>> discoverAllTools() async {
    final results = <String, McpDiscoveredTools>{};
    for (final server in _servers.values) {
      try {
        final discovered = await server.connectAndDiscover();
        results[server.config.name] = discovered;

        // 建立工具→服务器映射
        for (final tool in discovered.tools) {
          final qualifiedName = 'mcp__${server.config.name}__${tool.name}';
          _toolToServer[qualifiedName] = server.config.name;
          _toolToServer[tool.name] = server.config.name; // 简短名（备用）
        }
      } catch (e) {
        print('[mcp] error: \$e');
        // 单个服务器失败不影响其他
        results[server.config.name] = McpDiscoveredTools(
          serverName: server.config.name,
          tools: [],
        );
      }
    }
    return results;
  }

  /// 获取所有已发现工具的 Anthropic schema 列表（合并所有服务器）
  List<Map<String, dynamic>> get allToolSchemas {
    final schemas = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final server in _servers.values) {
      for (final tool in server.tools) {
        final qualifiedName = 'mcp__${server.config.name}__${tool.name}';
        if (seen.contains(qualifiedName)) continue;
        seen.add(qualifiedName);

        final schema = tool.toAnthropicSchema();
        schema['name'] = qualifiedName;
        schema['description'] =
            '[MCP:${server.config.name}] ${tool.description ?? ""}';
        schemas.add(schema);
      }
    }
    return schemas;
  }

  // ---- 工具路由 ----

  /// 解析工具名，返回 (serverClient, toolName)
  (McpClient?, String) resolveTool(String toolName) {
    // mcp__server__tool 格式
    final parts = toolName.split('__');
    if (parts.length >= 3 && parts[0] == 'mcp') {
      final serverName = parts[1];
      final actualTool = parts.sublist(2).join('__');
      final client = _servers[serverName];
      return (client, actualTool);
    }

    // 简短名查找
    final serverName = _toolToServer[toolName];
    if (serverName != null) {
      return (_servers[serverName], toolName);
    }

    return (null, toolName);
  }

  /// 调用工具（自动路由到正确的服务器）
  Future<ToolCallResult> callTool(String toolName, Map<String, dynamic> arguments) async {
    final (client, actualTool) = resolveTool(toolName);
    if (client == null) {
      throw McpException('MCP server not found for tool: $toolName / 未找到工具对应的 MCP 服务器: $toolName');
    }
    return client.callTool(actualTool, arguments);
  }

  // ---- 健康检查 ----

  Future<Map<String, bool>> checkAllHealth() async {
    final results = <String, bool>{};
    for (final server in _servers.values) {
      results[server.config.name] = await server.ping();
    }
    return results;
  }

  List<McpClient> get unhealthyServers =>
      _servers.values.where((s) => !s.health.isConnected).toList();

  // ---- 工具过滤 ----

  /// 返回不属于本地 ToolRegistry 的工具（即 MCP 远程特有的工具）
  Set<String> get mcpToolNames => _toolToServer.keys.toSet();

  void clear() {
    for (final s in _servers.values) {
      s.disconnect();
    }
    _servers.clear();
    _toolToServer.clear();
  }
}

// ────────────────────────────────────────────
// McpToolModule — 将 MCP 工具包装为声明式模块
// ────────────────────────────────────────────

class McpToolModule implements ToolModule {
  final List<ToolDefinition> _definitions;

  McpToolModule(this._definitions);

  /// 从 MCP allToolSchemas 创建模块。
  /// [schemas] 来自 McpRegistry.instance.allToolSchemas。
  factory McpToolModule.fromSchemas(List<Map<String, dynamic>> schemas) {
    final defs = <ToolDefinition>[];
    for (final schema in schemas) {
      defs.add(ToolDefinition(
        name: schema['name'] as String,
        description: schema['description'] as String? ?? '',
        category: ToolCategory.custom,
        inputSchema: schema['input_schema'] as Map<String, dynamic>? ?? {},
        baseRisk: 0.08,
        tags: ['mcp'],
        source: ToolSource.mcp,
      ));
    }
    return McpToolModule(defs);
  }

  @override
  String get name => 'mcp';

  @override
  bool get isDynamic => true;

  @override
  List<ToolDefinition> get definitions => _definitions;

  @override
  Map<String, ToolGroup> get groupAssignments {
    final map = <String, ToolGroup>{};
    for (final d in _definitions) {
      map[d.name] = ToolGroup.mcp;
    }
    return map;
  }
}
