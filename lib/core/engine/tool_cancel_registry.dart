import 'dart:async';

import '../../features/tools/domain/tool.dart';

class CancelToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;

  final _cancelCompleter = Completer<void>();

  void cancel() {
    _isCancelled = true;
    if (!_cancelCompleter.isCompleted) {
      _cancelCompleter.complete();
    }
  }

  /// A future that completes when this token is cancelled.
  Future<void> get onCancel => _cancelCompleter.future;

  /// Returns a ToolResult when this token is cancelled.
  Future<ToolResult> cancelledResult(String toolName, ToolResult Function() resultFactory) async {
    await onCancel;
    return resultFactory();
  }
}

class ToolCancelRegistry {
  ToolCancelRegistry._();
  static final ToolCancelRegistry instance = ToolCancelRegistry._();

  final _map = <String, CancelToken>{};

  void register(String messageId, CancelToken cancelToken) {
    _map[messageId] = cancelToken;
  }

  void unregister(String messageId) {
    _map.remove(messageId);
  }

  void cancelAllForSession(String sessionId) {
    for (final ct in _map.values) {
      ct.cancel();
    }
    _map.clear();
  }

  void cancelAll() {
    for (final ct in _map.values) {
      ct.cancel();
    }
    _map.clear();
  }

  void cancelOne(String messageId) {
    _map[messageId]?.cancel();
    _map.remove(messageId);
  }
}
