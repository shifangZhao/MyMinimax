import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PendingToolState {

  const PendingToolState({
    required this.toolName,
    required this.arguments,
    required this.startTime,
    required this.toolCallId,
    required this.conversationId,
  });

  factory PendingToolState.fromJson(Map<String, dynamic> json) {
    return PendingToolState(
      toolName: json['toolName'] as String,
      arguments: Map<String, dynamic>.from(json['arguments'] as Map),
      startTime: DateTime.parse(json['startTime'] as String),
      toolCallId: json['toolCallId'] as String,
      conversationId: json['conversationId'] as String,
    );
  }
  final String toolName;
  final Map<String, dynamic> arguments;
  final DateTime startTime;
  final String toolCallId;
  final String conversationId;

  Map<String, dynamic> toJson() => {
    'toolName': toolName,
    'arguments': arguments,
    'startTime': startTime.toIso8601String(),
    'toolCallId': toolCallId,
    'conversationId': conversationId,
  };
}

class AgentStatePersistence {
  static const _pendingToolKey = 'agent_pending_tool_state';
  static const _toolTimeoutMinutes = 2;

  static Future<void> save(PendingToolState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingToolKey, jsonEncode(state.toJson()));
  }

  static Future<PendingToolState?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_pendingToolKey);
    if (jsonStr == null) return null;

    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final state = PendingToolState.fromJson(json);

      if (DateTime.now().difference(state.startTime) >
          const Duration(minutes: _toolTimeoutMinutes)) {
        await clear();
        return null;
      }

      return state;
    } catch (e) {
      print('[agent] error: \$e');
      await clear();
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingToolKey);
  }

  static Future<bool> hasPendingTool() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_pendingToolKey);
  }
}