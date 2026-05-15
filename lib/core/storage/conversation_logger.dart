import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class ConversationLogger {
  factory ConversationLogger() => _instance;
  ConversationLogger._internal();
  String? _currentConversationId;
  File? _logFile;

  static final ConversationLogger _instance = ConversationLogger._internal();

  Future<void> switchConversation(String? conversationId) async {
    if (_currentConversationId == conversationId) return;

    // 关闭旧文件
    await _closeLogFile();

    if (conversationId == null) {
      _currentConversationId = null;
      _logFile = null;
      return;
    }

    // 创建新日志文件
    _currentConversationId = conversationId;
    final appDir = await getApplicationDocumentsDirectory();
    final logsDir = Directory('${appDir.path}/logs');
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _logFile = File('${logsDir.path}/conversation_${conversationId}_$timestamp.log');
    await _logFile!.writeAsString('=== 会话日志开始 ===\n');
  }

  Future<void> _closeLogFile() async {
    if (_logFile != null) {
      try {
        await _logFile!.writeAsString('=== 会话日志结束 ===\n\n', mode: FileMode.append);
      } catch (_) {}
      _logFile = null;
    }
  }

  Future<void> log(String level, String message, {Object? error, StackTrace? stackTrace}) async {
    final timestamp = DateTime.now().toIso8601String();
    final buffer = StringBuffer();
    buffer.writeln('[$timestamp] [$level] $message');
    if (error != null) {
      buffer.writeln('  ERROR: $error');
    }
    if (stackTrace != null) {
      buffer.writeln('  STACK: $stackTrace');
    }

    // 写入文件
    if (_logFile != null) {
      try {
        await _logFile!.writeAsString(buffer.toString(), mode: FileMode.append);
      } catch (_) {}
    }

    // 同时打印到控制台
    if (level == 'ERROR') {
      debugPrint(buffer.toString());
    }
  }

  void debug(String message) => log('DEBUG', message);
  void info(String message) => log('INFO', message);
  void warn(String message) => log('WARN', message);
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      log('ERROR', message, error: error, stackTrace: stackTrace);

  Future<void> close() async {
    await _closeLogFile();
    _currentConversationId = null;
  }
}
