import 'dart:convert';
import 'tool_registry.dart';
import '../../features/tools/domain/tool.dart';
import '../../features/settings/data/settings_repository.dart';
import '../mcp/mcp_client.dart';
import '../mcp/mcp_registry.dart';
import 'tool_module.dart';
import 'tool_groups.dart';

/// Agent 可调用的 MCP 配置工具。
///
/// 提供 mcp_list / mcp_register / mcp_unregister 三个工具，
/// 让智能体在对话中自主管理 MCP 服务器，配置持久化到 SharedPreferences。
class McpTools implements ToolModule {
  static final McpTools module = McpTools._();
  McpTools._();

  @override
  String get name => 'mcp_config';

  @override
  bool get isDynamic => false;

  @override
  Map<String, ToolGroup> get groupAssignments => {
    'mcp_list': ToolGroup.mcp,
    'mcp_register': ToolGroup.mcp,
    'mcp_unregister': ToolGroup.mcp,
  };

  @override
  List<ToolDefinition> get definitions => [
    ToolDefinition(
      name: 'mcp_list',
      description: '列出当前所有已配置的 MCP 服务器及其状态。\n'
          '返回 JSON 数组，每个服务器包含 name、url、description、headers（已脱敏）、来源等信息。',
      category: ToolCategory.system,
      tags: ['mcp', 'meta'],
      inputSchema: {
        'type': 'object',
        'properties': {},
        'required': [],
      },
    ),
    ToolDefinition(
      name: 'mcp_register',
      description: '注册一个新的 MCP 服务器并立即生效。有两种传参方式：\n'
          '\n'
          '方式一（推荐）— 使用 config 对象，字段与 UI 的 JSON 模板一致：\n'
          '  {"config": {"name": "...", "url": "...", "description": "...", "timeout": 30, "headers": {...}}}\n'
          '\n'
          '方式二 — 使用独立字段（向后兼容）：\n'
          '  {"name": "...", "url": "...", "description": "...", "headers": {...}}\n'
          '\n'
          '注册后，该服务器的工具会自动注入到 ToolRegistry 中供后续 tool_calls 使用。\n'
          '配置会持久化保存，下次启动时自动加载。\n'
          '\n'
          '当前仅支持 HTTP transport（url 模式）。',
      category: ToolCategory.system,
      tags: ['mcp', 'meta', 'network'],
      inputSchema: {
        'type': 'object',
        'properties': {
          'config': {
            'type': 'object',
            'description': 'MCP 服务器完整配置对象。包含 name(必填)、url(必填)、description(可选)、timeout(可选，默认30秒)、headers(可选，HTTP headers对象)。',
            'properties': {
              'name': {'type': 'string', 'description': '服务器名称'},
              'url': {'type': 'string', 'description': 'MCP 服务器的 HTTP endpoint URL'},
              'description': {'type': 'string', 'description': '可选描述'},
              'timeout': {'type': 'integer', 'description': '超时秒数，默认30'},
              'headers': {'type': 'object', 'description': '可选的 HTTP headers'},
            },
            'required': ['name', 'url'],
          },
          'name': {
            'type': 'string',
            'description': '（方式二）服务器名称，用于标识和工具命名。',
          },
          'url': {
            'type': 'string',
            'description': '（方式二）MCP 服务器的 HTTP endpoint URL。',
          },
          'description': {
            'type': 'string',
            'description': '（方式二）可选描述。',
          },
          'headers': {
            'type': 'object',
            'description': '（方式二）可选的 HTTP headers。',
          },
        },
      },
    ),
    ToolDefinition(
      name: 'mcp_unregister',
      description: '移除一个已注册的 MCP 服务器，包括其提供的所有工具。\n'
          '该操作会同时移除持久化配置，下次启动不再加载。',
      category: ToolCategory.system,
      tags: ['mcp', 'meta'],
      inputSchema: {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': '要移除的服务器名称。先用 mcp_list 查看可移除的服务器。',
          },
        },
        'required': ['name'],
      },
    ),
  ];

  // ── execute ──

  static Future<ToolResult> execute(
    String toolName,
    Map<String, dynamic> params,
  ) async {
    try {
      switch (toolName) {
        case 'mcp_list':
          return await _list();
        case 'mcp_register':
          return await _register(params);
        case 'mcp_unregister':
          return await _unregister(params);
        default:
          return ToolResult(
            toolName: toolName,
            success: false,
            output: '',
            error: 'Unknown MCP tool: $toolName',
          );
      }
    } catch (e) {
      return ToolResult(
        toolName: toolName,
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  static Future<ToolResult> _list() async {
    final repo = SettingsRepository();
    final servers = await repo.getMcpServersConfig();

    final result = <Map<String, dynamic>>[];
    for (final s in servers) {
      final name = s['name'] as String? ?? '';
      // 脱敏 headers
      final rawHeaders = s['headers'] as Map<String, dynamic>?;
      final safeHeaders = <String, String>{};
      if (rawHeaders != null) {
        for (final e in rawHeaders.entries) {
          final v = e.value.toString();
          safeHeaders[e.key] = v.length > 20 ? '${v.substring(0, 17)}...' : v;
        }
      }
      result.add({
        'name': name,
        'url': s['url'] ?? '',
        'description': s['description'] ?? '',
        'headers': safeHeaders,
        'timeout': s['timeout'] ?? 30,
        'registered': McpRegistry.instance.serverNames.contains(name),
      });
    }

    return ToolResult(
      toolName: 'mcp_list',
      success: true,
      output: '共 ${result.length} 个 MCP 服务器:\n${const JsonEncoder.withIndent("  ").convert(result)}',
    );
  }

  static Future<ToolResult> _register(Map<String, dynamic> params) async {
    // 优先从 config 对象提取，fallback 到独立字段
    final cfg = params['config'] as Map<String, dynamic>?;
    final name = ((cfg?['name'] ?? params['name']) as String?)?.trim();
    final url = ((cfg?['url'] ?? params['url']) as String?)?.trim();

    if (name == null || name.isEmpty) {
      return const ToolResult(toolName: 'mcp_register', success: false, output: '', error: 'name 参数不能为空');
    }
    if (url == null || url.isEmpty) {
      return const ToolResult(toolName: 'mcp_register', success: false, output: '', error: 'url 参数不能为空');
    }

    // 基本 URL 格式校验
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return ToolResult(toolName: 'mcp_register', success: false, output: '', error: 'url 必须以 http:// 或 https:// 开头: $url');
    }

    final description = (cfg?['description'] ?? params['description']) as String?;
    final rawHeaders = (cfg?['headers'] ?? params['headers']) as Map<String, dynamic>?;
    final headers = rawHeaders?.map((k, v) => MapEntry(k, v.toString()));
    final timeout = (cfg?['timeout'] ?? params['timeout']) is int
        ? (cfg?['timeout'] ?? params['timeout']) as int
        : 30;

    try {
      final config = {
        'name': name,
        'url': url,
        if (description != null && description.isNotEmpty) 'description': description,
        if (headers != null && headers.isNotEmpty) 'headers': headers,
        'timeout': timeout,
      };

      // 1. 持久化
      final repo = SettingsRepository();
      await repo.addMcpServer(config);

      // 2. 运行时注册
      final serverConfig = McpServerConfig.fromJson(name, config);
      McpRegistry.instance.register(serverConfig);

      // 3. 发现工具
      final discovered = await McpRegistry.instance.discoverAllTools();

      // 4. 重建工具模块
      final schemas = McpRegistry.instance.allToolSchemas;
      ToolRegistry.instance.clearDynamicModules();
      if (schemas.isNotEmpty) {
        ToolRegistry.instance.registerModule(McpToolModule.fromSchemas(schemas));
      }

      final toolCount = discovered[name]?.tools.length ?? 0;
      return ToolResult(
        toolName: 'mcp_register',
        success: true,
        output: 'MCP 服务器 "$name" 注册成功。'
            '发现 $toolCount 个工具，已注入到工具注册表。'
            '${toolCount > 0 ? "\n工具列表: ${discovered[name]?.tools.map((t) => t.name).join(", ") ?? ""}" : ""}',
      );
    } catch (e) {
      return ToolResult(
        toolName: 'mcp_register',
        success: false,
        output: '',
        error: '注册失败: $e',
      );
    }
  }

  static Future<ToolResult> _unregister(Map<String, dynamic> params) async {
    final name = (params['name'] as String?)?.trim();

    if (name == null || name.isEmpty) {
      return const ToolResult(toolName: 'mcp_unregister', success: false, output: '', error: 'name 参数不能为空');
    }

    try {
      // 1. 持久化
      final repo = SettingsRepository();
      await repo.removeMcpServer(name);

      // 2. 运行时注销
      McpRegistry.instance.unregister(name);

      // 3. 重建工具模块
      final schemas = McpRegistry.instance.allToolSchemas;
      ToolRegistry.instance.clearDynamicModules();
      if (schemas.isNotEmpty) {
        ToolRegistry.instance.registerModule(McpToolModule.fromSchemas(schemas));
      }

      return ToolResult(
        toolName: 'mcp_unregister',
        success: true,
        output: 'MCP 服务器 "$name" 已移除。',
      );
    } catch (e) {
      return ToolResult(
        toolName: 'mcp_unregister',
        success: false,
        output: '',
        error: '注销失败: $e',
      );
    }
  }
}
