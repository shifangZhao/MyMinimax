/// MCP 配置加载器
///
/// 从工作目录加载 `.mcp.json` 文件，注册发现的 MCP 服务器。
/// 兼容 Claude Code / VS Code / Cursor 的 mcp.json 格式。
///
/// 文件格式:
/// ```json
/// {
///   "mcpServers": {
///     "server-name": {
///       "url": "https://mcp.example.com/mcp",
///       "headers": { "Authorization": "Bearer xxx" },
///       "description": "可选描述",
///       "disabledTools": ["dangerous_tool"]
///     }
///   }
/// }
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'mcp_client.dart';
import 'mcp_registry.dart';

class McpLoadResult {

  McpLoadResult({required this.loaded, required this.skipped, required this.errors});
  final List<String> loaded;
  final List<String> skipped;
  final List<String> errors;

  String summarize() =>
      'MCP loaded: ${loaded.length} servers, '
      'skipped ${skipped.length}, errors ${errors.length} / '
      'MCP 加载: ${loaded.length} 个服务器, '
      '跳过 ${skipped.length}, 错误 ${errors.length}';
}

class McpLoader {
  /// 要扫描的配置文件路径（相对于工作目录）
  static const configSearchPaths = [
    '.mcp.json',         // 项目本地
    '.claude/mcp.json',  // Claude Code 兼容
  ];

  /// 从工作目录加载所有 MCP 配置
  static Future<McpLoadResult> loadFromWorkspace(String workspacePath) async {
    final loaded = <String>[];
    final skipped = <String>[];
    final errors = <String>[];

    for (final relativePath in configSearchPaths) {
      final configPath = p.join(workspacePath, relativePath);
      final file = File(configPath);
      if (!await file.exists()) continue;

      try {
        final raw = await file.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final result = _parseAndRegister(json, configPath);
        loaded.addAll(result.loaded);
        skipped.addAll(result.skipped);
        errors.addAll(result.errors);
      } catch (e) {
        print('[mcp] error: \$e');
        errors.add('$relativePath: $e');
      }
    }

    return McpLoadResult(loaded: loaded, skipped: skipped, errors: errors);
  }

  /// 解析 JSON 并注册服务器
  static McpLoadResult _parseAndRegister(Map<String, dynamic> json, String sourcePath) {
    final loaded = <String>[];
    final skipped = <String>[];
    final errors = <String>[];

    final servers = json['mcpServers'] as Map<String, dynamic>?;
    if (servers == null) return McpLoadResult(loaded: loaded, skipped: skipped, errors: errors);

    for (final entry in servers.entries) {
      final name = entry.key;
      final value = entry.value as Map<String, dynamic>?;
      if (value == null) {
        skipped.add(name);
        continue;
      }

      try {
        // 只支持 HTTP 类型服务器
        if (value['url'] is String) {
          final config = McpServerConfig.fromJson(name, value);
          McpRegistry.instance.register(config);
          loaded.add(name);
        } else if (value['command'] is String) {
          // stdio 服务器在移动端暂不支持
          skipped.add('$name (stdio server not supported on mobile / stdio 服务器不支持移动端)');
        } else {
          errors.add('$name: missing url or command field / 缺少 url 或 command 字段');
        }
      } catch (e) {
        print('[mcp] error: \$e');
        errors.add('$name: $e');
      }
    }

    return McpLoadResult(loaded: loaded, skipped: skipped, errors: errors);
  }

  /// 从内存直接注册
  static void registerServersFromJson(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    _parseAndRegister(json, '(memory)');
  }

  /// 重新加载（清空后重新扫描）
  static Future<McpLoadResult> reload(String workspacePath) async {
    McpRegistry.instance.clear();
    return loadFromWorkspace(workspacePath);
  }
}
