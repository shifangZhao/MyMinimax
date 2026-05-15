/// MCP 客户端 — 实现 MCP 协议规范
///
/// 每个 McpClient 实例对应一个 MCP 服务器连接。
/// 支持 HTTP transport (Streamable HTTP)。
///
/// 生命周期:
///   1. initialize → 握手、获取服务器能力
///   2. tools/list → 发现工具
///   3. tools/call → 执行工具
library;

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'mcp_protocol.dart';

// ============================================================
// 连接状态
// ============================================================

enum McpConnectionState { disconnected, connecting, connected, failed }

class McpHealthState {

  McpHealthState({
    this.connectionState = McpConnectionState.disconnected,
    this.lastCheck,
    this.nextRetryAfter,
    this.consecutiveFailures = 0,
    this.lastError,
  });
  McpConnectionState connectionState;
  DateTime? lastCheck;
  DateTime? nextRetryAfter;
  int consecutiveFailures;
  String? lastError;

  bool get isConnected => connectionState == McpConnectionState.connected;
  bool get canRetry =>
      nextRetryAfter == null || DateTime.now().isAfter(nextRetryAfter!);

  Duration get backoffDuration {
    const base = Duration(seconds: 30);
    const max = Duration(minutes: 10);
    final d = base * (1 << (consecutiveFailures - 1));
    return d > max ? max : d;
  }
}

// ============================================================
// 服务器配置
// ============================================================

class McpServerConfig {

  const McpServerConfig({
    required this.name,
    required this.url,
    this.headers,
    this.description,
    this.timeout = const Duration(seconds: 30),
    this.disabledTools = const {},
  });

  factory McpServerConfig.fromJson(String name, Map<String, dynamic> json) {
    return McpServerConfig(
      name: name,
      url: json['url'] as String,
      headers: (json['headers'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v.toString())),
      description: json['description'] as String?,
      timeout: json['timeout'] != null
          ? Duration(seconds: json['timeout'] as int)
          : const Duration(seconds: 30),
      disabledTools: (json['disabledTools'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toSet() ??
          const {},
    );
  }
  final String name;
  final String url; // HTTP endpoint
  final Map<String, String>? headers;
  final String? description;
  final Duration timeout;

  /// 禁用的工具名集合（可选）
  final Set<String> disabledTools;
}

// ============================================================
// 工具发现结果
// ============================================================

class McpDiscoveredTools {

  McpDiscoveredTools({
    required this.serverName,
    required this.tools,
    DateTime? discoveredAt,
  }) : discoveredAt = discoveredAt ?? DateTime.now();
  final String serverName;
  final List<McpTool> tools;
  final DateTime discoveredAt;

  List<Map<String, dynamic>> get anthropicSchemas =>
      tools.map((t) => t.toAnthropicSchema()).toList();
}

// ============================================================
// MCP Client
// ============================================================

class McpClient {

  McpClient({required this.config})
      : _dio = Dio(BaseOptions(
          baseUrl: config.url,
          headers: config.headers,
          connectTimeout: config.timeout,
          receiveTimeout: config.timeout,
          responseType: ResponseType.plain,
        ));
  final McpServerConfig config;
  final Dio _dio;
  final McpHealthState health = McpHealthState();

  ServerInfo? _serverInfo;
  ServerCapabilities? _capabilities;
  List<McpTool> _tools = [];
  int _requestId = 0;

  // ---- 公开属性 ----

  ServerInfo? get serverInfo => _serverInfo;
  ServerCapabilities? get capabilities => _capabilities;
  List<McpTool> get tools => List.unmodifiable(_tools);
  bool get isInitialized => health.isConnected;

  // ---- 连接生命周期 ----

  /// 执行 MCP 握手
  Future<InitializeResult> initialize() async {
    health.connectionState = McpConnectionState.connecting;

    try {
      final req = JsonRpcRequest(
        id: _nextId(),
        method: McpMethods.initialize,
        params: InitializeParams(
          clientInfo: const ClientInfo(name: 'minimax-agent', version: '1.0.0'),
        ).toJson(),
      );

      final res = await _send(req);
      if (res.isError) {
        throw McpException(
          'initialize failed: ${res.error?.message} / initialize 失败: ${res.error?.message}',
          code: res.error?.code,
        );
      }

      final initResult = InitializeResult.fromJson(res.result!);
      _serverInfo = initResult.serverInfo;
      _capabilities = initResult.capabilities;

      // 发送 initialized 通知
      await _send(JsonRpcRequest(method: McpMethods.initialized));

      _markHealthy();
      return initResult;
    } catch (e) {
      _markFailed(e.toString());
      rethrow;
    }
  }

  /// 发现工具
  Future<List<McpTool>> discoverTools() async {
    if (!health.isConnected) {
      await initialize();
    }

    try {
      final req = JsonRpcRequest(
        id: _nextId(),
        method: McpMethods.toolsList,
      );

      final res = await _send(req);
      if (res.isError) {
        throw McpException(
          'tools/list failed: ${res.error?.message} / tools/list 失败: ${res.error?.message}',
          code: res.error?.code,
        );
      }

      final listResult = ToolsListResult.fromJson(res.result!);
      _tools = listResult.tools
          .where((t) => !config.disabledTools.contains(t.name))
          .toList();

      return _tools;
    } catch (e) {
      _markFailed(e.toString());
      rethrow;
    }
  }

  /// 调用工具
  Future<ToolCallResult> callTool(String toolName, Map<String, dynamic> arguments) async {
    if (!health.isConnected) {
      await initialize();
    }

    try {
      final req = JsonRpcRequest(
        id: _nextId(),
        method: McpMethods.toolsCall,
        params: ToolCallParams(name: toolName, arguments: arguments).toJson(),
      );

      final res = await _send(req);
      if (res.isError) {
        throw McpException(
          'tools/call $toolName failed: ${res.error?.message} / tools/call $toolName 失败: ${res.error?.message}',
          code: res.error?.code,
        );
      }

      final callResult = ToolCallResult.fromJson(res.result!);
      if (callResult.isError == true) {
        throw McpException('Tool returned error: ${callResult.text} / 工具返回错误: ${callResult.text}');
      }

      return callResult;
    } catch (e) {
      if (e is McpException) rethrow;
      _markFailed(e.toString());
      rethrow;
    }
  }

  // ---- 健康管理 ----

  Future<bool> ping() async {
    try {
      final req = JsonRpcRequest(id: _nextId(), method: McpMethods.ping);
      await _send(req);
      _markHealthy();
      return true;
    } catch (_) {
      _markFailed('ping failed');
      return false;
    }
  }

  /// 完整的连接+发现流程
  Future<McpDiscoveredTools> connectAndDiscover() async {
    await initialize();
    final tools = await discoverTools();
    return McpDiscoveredTools(
      serverName: config.name,
      tools: tools,
    );
  }

  void disconnect() {
    health.connectionState = McpConnectionState.disconnected;
    _tools = [];
    _serverInfo = null;
    _capabilities = null;
  }

  // ---- 内部 ----

  int _nextId() => ++_requestId;

  void _markHealthy() {
    health.connectionState = McpConnectionState.connected;
    health.lastCheck = DateTime.now();
    health.consecutiveFailures = 0;
    health.nextRetryAfter = null;
    health.lastError = null;
  }

  void _markFailed(String error) {
    health.connectionState = McpConnectionState.failed;
    health.lastCheck = DateTime.now();
    health.consecutiveFailures++;
    health.lastError = error;
    health.nextRetryAfter = DateTime.now().add(health.backoffDuration);
  }

  Future<JsonRpcResponse> _send(JsonRpcRequest request) async {
    final body = encodeJsonRpc(request.toJson());

    final response = await _dio.post(
      '',
      data: body,
      options: Options(
        headers: {'Content-Type': 'application/json'},
        validateStatus: (s) => s != null && s < 500,
      ),
    );

    if (response.statusCode == null || response.statusCode! >= 500) {
      throw McpException('HTTP ${response.statusCode}: ${response.statusMessage}');
    }

    final raw = response.data is String
        ? response.data as String
        : jsonEncode(response.data);

    // Streamable HTTP 可能返回 SSE 格式
    if (raw.startsWith('event:') || raw.startsWith('data:')) {
      return _parseSse(raw);
    }

    final json = decodeJsonRpc(raw);
    return JsonRpcResponse.fromJson(json);
  }

  /// 解析 SSE 格式响应
  JsonRpcResponse _parseSse(String raw) {
    for (final line in raw.split('\n')) {
      if (line.startsWith('data:')) {
        final data = line.substring(5).trim();
        final json = decodeJsonRpc(data);
        return JsonRpcResponse.fromJson(json);
      }
    }
    throw McpException('Unable to parse SSE response / 无法解析 SSE 响应');
  }
}

// ============================================================
// 异常
// ============================================================

class McpException implements Exception {

  McpException(this.message, {this.code});
  final String message;
  final int? code;

  @override
  String toString() => 'McpException($code): $message';
}
