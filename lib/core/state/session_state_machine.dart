/// 会话状态机 — 形式化对话生命周期
///
/// 替代 chat_page 中散布的 streamState 字符串判断。
library;

import 'dart:async';

enum SessionState {
  idle,
  preparing,
  streaming,
  waitingTool,
  executingTool,
  completed,
  failed,
}

/// 合法的状态转换表
const _transitions = <SessionState, Set<SessionState>>{
  SessionState.idle: {SessionState.preparing, SessionState.failed},
  SessionState.preparing: {SessionState.streaming, SessionState.failed},
  SessionState.streaming: {SessionState.waitingTool, SessionState.completed, SessionState.failed},
  SessionState.waitingTool: {SessionState.executingTool, SessionState.failed},
  SessionState.executingTool: {SessionState.streaming, SessionState.waitingTool, SessionState.completed, SessionState.failed},
  SessionState.completed: {SessionState.idle, SessionState.failed},
  SessionState.failed: {SessionState.idle, SessionState.preparing},
};

class SessionContext {
  final List<ToolCallRecord> toolCallHistory = [];
  int messageCount = 0;
  int estimatedTokenCount = 0;
  final DateTime sessionStartedAt = DateTime.now();
  final Map<String, int> toolUsageCounts = {};

  void recordToolCall(String toolName, bool success) {
    toolCallHistory.add(ToolCallRecord(toolName, success, DateTime.now()));
    toolUsageCounts[toolName] = (toolUsageCounts[toolName] ?? 0) + 1;
  }

  Duration get elapsed => DateTime.now().difference(sessionStartedAt);
}

class ToolCallRecord {

  ToolCallRecord(this.toolName, this.success, this.timestamp);
  final String toolName;
  final bool success;
  final DateTime timestamp;
}

class SessionStateMachine {
  SessionState _current = SessionState.idle;
  final SessionContext context = SessionContext();

  final _stateController = StreamController<SessionState>.broadcast();

  SessionState get current => _current;
  Stream<SessionState> get stateStream => _stateController.stream;

  bool canTransition(SessionState to) {
    final allowed = _transitions[_current];
    return allowed != null && allowed.contains(to);
  }

  void transition(SessionState to) {
    if (!canTransition(to)) {
      throw StateError('Illegal state transition: $_current → $to / 非法状态转换: $_current → $to');
    }
    _current = to;
    _stateController.add(_current);
  }

  bool tryTransition(SessionState to) {
    if (!canTransition(to)) return false;
    transition(to);
    return true;
  }

  // ---- 便捷方法 ----

  void onSendStart() {
    if (_current == SessionState.failed || _current == SessionState.idle) {
      transition(SessionState.preparing);
    } else if (_current == SessionState.completed) {
      transition(SessionState.idle);
      transition(SessionState.preparing);
    }
  }

  void onFirstToken() {
    if (_current == SessionState.preparing) {
      transition(SessionState.streaming);
    }
  }

  void onToolCallReceived(String toolName) {
    if (_current == SessionState.streaming) {
      transition(SessionState.waitingTool);
    }
  }

  void onToolExecutionStart() {
    if (_current == SessionState.waitingTool) {
      transition(SessionState.executingTool);
    }
  }

  void onToolExecutionComplete(bool success) {
    if (_current == SessionState.executingTool) {
      transition(SessionState.streaming);
    }
  }

  void onStreamDone() {
    if (_current == SessionState.streaming) {
      transition(SessionState.completed);
    }
  }

  void onError(Object error) {
    if (_current != SessionState.idle && _current != SessionState.completed) {
      transition(SessionState.failed);
    }
  }

  void reset() {
    _current = SessionState.idle;
    context.toolCallHistory.clear();
    context.messageCount = 0;
    context.estimatedTokenCount = 0;
    context.toolUsageCounts.clear();
    _stateController.add(_current);
  }

  bool get isActive =>
      _current != SessionState.idle && _current != SessionState.completed && _current != SessionState.failed;

  bool get isTerminal =>
      _current == SessionState.completed || _current == SessionState.failed;

  void dispose() {
    _stateController.close();
  }
}
