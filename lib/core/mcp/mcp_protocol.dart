/// MCP (Model Context Protocol) 协议类型定义
///
/// 基于 MCP 开放标准规范 (2024-11-05+):
/// - JSON-RPC 2.0 消息格式
/// - 标准生命周期: initialize → initialized → tools/list → tools/call
/// - 支持 HTTP transport (Streamable HTTP)
library;

import 'dart:convert';

// ============================================================
// JSON-RPC 2.0 基础类型
// ============================================================

class JsonRpcRequest {

  JsonRpcRequest({required this.method, this.id, this.params});
  final String jsonrpc = '2.0';
  final dynamic id;
  final String method;
  final Map<String, dynamic>? params;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'jsonrpc': jsonrpc, 'method': method};
    if (id != null) m['id'] = id;
    if (params != null) m['params'] = params;
    return m;
  }
}

class JsonRpcResponse {

  JsonRpcResponse({this.id, this.result, this.error});

  factory JsonRpcResponse.fromJson(Map<String, dynamic> json) {
    return JsonRpcResponse(
      id: json['id'],
      result: json['result'] as Map<String, dynamic>?,
      error: json['error'] != null
          ? JsonRpcError.fromJson(json['error'] as Map<String, dynamic>)
          : null,
    );
  }
  final String jsonrpc = '2.0';
  final dynamic id;
  final Map<String, dynamic>? result;
  final JsonRpcError? error;

  bool get isError => error != null;
}

class JsonRpcError {

  JsonRpcError({required this.code, required this.message, this.data});

  factory JsonRpcError.fromJson(Map<String, dynamic> json) {
    return JsonRpcError(
      code: json['code'] as int,
      message: json['message'] as String,
      data: json['data'],
    );
  }
  final int code;
  final String message;
  final dynamic data;
}

// ============================================================
// MCP 标准方法名
// ============================================================

class McpMethods {
  static const initialize = 'initialize';
  static const initialized = 'notifications/initialized';
  static const toolsList = 'tools/list';
  static const toolsCall = 'tools/call';
  static const resourcesList = 'resources/list';
  static const resourcesRead = 'resources/read';
  static const promptsList = 'prompts/list';
  static const promptsGet = 'prompts/get';
  static const ping = 'ping';
}

// ============================================================
// MCP initialize
// ============================================================

class InitializeParams {

  InitializeParams({
    this.protocolVersion = '2024-11-05',
    this.capabilities = const ClientCapabilities(),
    ClientInfo? clientInfo,
  }) : clientInfo = clientInfo ?? const ClientInfo();
  final String protocolVersion;
  final ClientCapabilities capabilities;
  final ClientInfo clientInfo;

  Map<String, dynamic> toJson() => {
        'protocolVersion': protocolVersion,
        'capabilities': capabilities.toJson(),
        'clientInfo': clientInfo.toJson(),
      };
}

class ClientCapabilities {

  const ClientCapabilities({this.roots, this.sampling});
  final Map<String, dynamic>? roots;
  final Map<String, dynamic>? sampling;

  Map<String, dynamic> toJson() => {
        if (roots != null) 'roots': roots,
        if (sampling != null) 'sampling': sampling,
      };
}

class ClientInfo {

  const ClientInfo({this.name = 'minimax-agent', this.version = '1.0.0'});
  final String name;
  final String version;

  Map<String, dynamic> toJson() => {'name': name, 'version': version};
}

class InitializeResult {

  InitializeResult({
    required this.protocolVersion,
    required this.capabilities,
    required this.serverInfo,
    this.instructions,
  });

  factory InitializeResult.fromJson(Map<String, dynamic> json) {
    return InitializeResult(
      protocolVersion: json['protocolVersion'] as String,
      capabilities: ServerCapabilities.fromJson(json['capabilities'] as Map<String, dynamic>),
      serverInfo: ServerInfo.fromJson(json['serverInfo'] as Map<String, dynamic>),
      instructions: json['instructions'] as String?,
    );
  }
  final String protocolVersion;
  final ServerCapabilities capabilities;
  final ServerInfo serverInfo;
  final String? instructions;
}

class ServerCapabilities {

  ServerCapabilities({this.tools, this.resources, this.prompts, this.logging});

  factory ServerCapabilities.fromJson(Map<String, dynamic> json) {
    return ServerCapabilities(
      tools: json['tools'] as Map<String, dynamic>?,
      resources: json['resources'] as Map<String, dynamic>?,
      prompts: json['prompts'] as Map<String, dynamic>?,
      logging: json['logging'] as Map<String, dynamic>?,
    );
  }
  final Map<String, dynamic>? tools;
  final Map<String, dynamic>? resources;
  final Map<String, dynamic>? prompts;
  final Map<String, dynamic>? logging;

  bool get supportsTools => tools != null;
  bool get supportsResources => resources != null;
  bool get supportsPrompts => prompts != null;
}

class ServerInfo {

  ServerInfo({required this.name, required this.version});

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    return ServerInfo(
      name: json['name'] as String,
      version: json['version'] as String,
    );
  }
  final String name;
  final String version;
}

// ============================================================
// MCP tools/list
// ============================================================

class ToolsListResult {

  ToolsListResult({required this.tools, this.nextCursor});

  factory ToolsListResult.fromJson(Map<String, dynamic> json) {
    return ToolsListResult(
      tools: (json['tools'] as List)
          .map((t) => McpTool.fromJson(t as Map<String, dynamic>))
          .toList(),
      nextCursor: json['nextCursor'] as String?,
    );
  }
  final List<McpTool> tools;
  final String? nextCursor;
}

class McpTool {

  McpTool({required this.name, required this.inputSchema, this.description});

  factory McpTool.fromJson(Map<String, dynamic> json) {
    return McpTool(
      name: json['name'] as String,
      description: json['description'] as String?,
      inputSchema: json['inputSchema'] as Map<String, dynamic>? ?? {},
    );
  }
  final String name;
  final String? description;
  final Map<String, dynamic> inputSchema;

  /// 转为 Anthropic 兼容的 tool schema
  Map<String, dynamic> toAnthropicSchema() => {
        'name': name,
        'description': description ?? '',
        'input_schema': inputSchema,
      };
}

// ============================================================
// MCP tools/call
// ============================================================

class ToolCallParams {

  ToolCallParams({required this.name, required this.arguments});
  final String name;
  final Map<String, dynamic> arguments;

  Map<String, dynamic> toJson() => {'name': name, 'arguments': arguments};
}

class ToolCallResult {

  ToolCallResult({required this.content, this.isError});

  factory ToolCallResult.fromJson(Map<String, dynamic> json) {
    return ToolCallResult(
      content: (json['content'] as List)
          .map((c) => ToolCallContent.fromJson(c as Map<String, dynamic>))
          .toList(),
      isError: json['isError'] as bool?,
    );
  }
  final List<ToolCallContent> content;
  final bool? isError;

  /// 提取文本内容
  String get text => content
      .where((c) => c.type == 'text')
      .map((c) => c.text ?? '')
      .join('\n');
}

class ToolCallContent {

  ToolCallContent({required this.type, this.text, this.data, this.mimeType});

  factory ToolCallContent.fromJson(Map<String, dynamic> json) {
    return ToolCallContent(
      type: json['type'] as String,
      text: json['text'] as String?,
      data: json['data'] as String?,
      mimeType: json['mimeType'] as String?,
    );
  }
  final String type;
  final String? text;
  final String? data;
  final String? mimeType;
}

// ============================================================
// 辅助
// ============================================================

String encodeJsonRpc(dynamic message) {
  return jsonEncode(message is Map ? message : (message as dynamic).toJson());
}

Map<String, dynamic> decodeJsonRpc(String raw) {
  return jsonDecode(raw) as Map<String, dynamic>;
}
