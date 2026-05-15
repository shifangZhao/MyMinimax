import 'dart:async';
import 'cdp_connection.dart';

/// Timeout-wrapped CDP command execution.
///
/// Wraps every CDP call in a per-command timeout to prevent silent hangs.
/// Handles reconnection gracefully — marks commands as failed during reconnect.
class CdpCommandExecutor {

  CdpCommandExecutor(
    this._connection, {
    Duration defaultTimeout = const Duration(seconds: 60),
  }) : _defaultTimeout = defaultTimeout;
  final CdpConnection _connection;
  final Duration _defaultTimeout;

  int _pendingCount = 0;
  bool _reconnecting = false;

  CdpConnection get connection => _connection;

  int get pendingCount => _pendingCount;

  void notifyReconnecting() {
    _reconnecting = true;
  }

  void notifyReconnected() {
    _reconnecting = false;
  }

  /// Execute a CDP command and return the parsed result.
  ///
  /// Commands are sent via the [CdpConnection] and results are awaited.
  /// If [sessionId] is provided, the command is scoped to a specific CDP session
  /// (e.g., an iframe target).
  Future<Map<String, dynamic>> execute(
    String method, {
    Map<String, dynamic>? params,
    String? sessionId,
    Duration? timeout,
  }) async {
    if (_reconnecting) {
      throw CdpNotConnectedException(method);
    }
    _pendingCount++;
    try {
      final response = await _connection.send(
        method,
        params: params,
        sessionId: sessionId,
        timeout: timeout ?? _defaultTimeout,
      );
      if (response.isError) {
        throw CdpCommandException(
          method,
          response.error!.code,
          response.error!.message,
        );
      }
      return response.result ?? {};
    } catch (e) {
      if (e is CdpCommandException) rethrow;
      if (e is TimeoutException) {
        throw CdpCommandException(method, -1, 'Timed out: $method');
      }
      rethrow;
    } finally {
      _pendingCount--;
    }
  }

  /// Execute a CDP command, returning null on any error (fire-and-forget style).
  /// Use for non-critical commands like enabling domains.
  Future<Map<String, dynamic>?> executeOrNull(
    String method, {
    Map<String, dynamic>? params,
    String? sessionId,
    Duration? timeout,
  }) async {
    try {
      return await execute(method, params: params, sessionId: sessionId, timeout: timeout);
    } catch (_) {
      return null;
    }
  }

  /// Execute multiple CDP commands in parallel and collect results.
  /// If any fail, the others continue (best-effort collection).
  Future<List<Map<String, dynamic>?>> executeParallel(
    List<_CdpCommand> commands,
  ) async {
    final futures = commands.map((cmd) => executeOrNull(
      cmd.method,
      params: cmd.params,
      sessionId: cmd.sessionId,
      timeout: cmd.timeout,
    ));
    return Future.wait(futures);
  }
}

class _CdpCommand {

  const _CdpCommand(this.method, {this.sessionId, this.params, this.timeout});
  final String method;
  final Map<String, dynamic>? params;
  final String? sessionId;
  final Duration? timeout;
}

// Shortcut for building parallel command lists
extension CdpParallelCommands on List<Map<String, dynamic>?> {
  void addCommand(String method, {Map<String, dynamic>? params, String? sessionId, Duration? timeout}) {
    // This is just a documentation extension; actual parallel execution
    // is done via CdpCommandExecutor.executeParallel()
  }
}

class CdpNotConnectedException implements Exception {
  const CdpNotConnectedException(this.method);
  final String method;
  @override
  String toString() => 'CDP not connected (reconnecting): $method';
}

class CdpCommandException implements Exception {
  const CdpCommandException(this.method, this.code, this.message);
  final String method;
  final int code;
  final String message;
  @override
  String toString() => 'CDP error $code on $method: $message';
}
