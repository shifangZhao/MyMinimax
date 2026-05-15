import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../permission/permission_manager.dart';

/// 悬浮对话事件
class FloatingChatEvent {

  const FloatingChatEvent({required this.type, this.data});
  final String type;
  final String? data;
}

/// 悬浮对话客户端 —— 与 Android 原生 FloatingChatHandler 双向通信
class FloatingChatClient {

  FloatingChatClient() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }
  static const _channel = MethodChannel('com.myminimax/floating_chat');

  static bool get isSupported => Platform.isAndroid;

  final _eventController = StreamController<FloatingChatEvent>.broadcast();

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onSendMessage':
        final text = call.arguments is Map
            ? (call.arguments as Map)['text'] as String? ?? ''
            : '';
        _eventController.add(FloatingChatEvent(type: 'sendMessage', data: text));
        break;
      case 'onBallTapped':
        _eventController.add(const FloatingChatEvent(type: 'ballTapped'));
        break;
      case 'onOpenApp':
        _eventController.add(const FloatingChatEvent(type: 'openApp'));
        break;
      case 'onPanelStateChanged':
        final open = call.arguments is Map
            ? (call.arguments as Map)['open']?.toString() ?? 'false'
            : 'false';
        _eventController.add(FloatingChatEvent(type: 'panelStateChanged', data: open));
        break;
      case 'onPanelError':
        final error = call.arguments is Map
            ? (call.arguments as Map)['error']?.toString() ?? 'unknown'
            : 'unknown';
        debugPrint('[FloatingChat] Panel error: $error');
        _eventController.add(FloatingChatEvent(type: 'panelError', data: error));
        break;
    }
  }

  /// 监听原生侧发来的事件
  Stream<FloatingChatEvent> get events => _eventController.stream;

  // ── 显示 / 隐藏 ──

  Future<void> showBall() async {
    try {
      await PermissionManager().requireForTool(AppPermission.overlay);
      await _channel.invokeMethod('showBall');
    } on PlatformException catch (e) {
      debugPrint('[FloatingChat] showBall failed: ${e.message}');
    } catch (e) {
      debugPrint('[FloatingChat] showBall failed: $e');
    }
  }

  Future<void> hideBall() async {
    try {
      await _channel.invokeMethod('hideBall');
    } on PlatformException catch (e) {
      debugPrint('[FloatingChat] hideBall failed: ${e.message}');
    }
  }

  Future<void> hideAll() async {
    try {
      await _channel.invokeMethod('hideAll');
    } on PlatformException catch (e) {
      debugPrint('[FloatingChat] hideAll failed: ${e.message}');
    }
  }

  // ── 消息 ──

  Future<void> appendMessage(String role, String content) async {
    try {
      await _channel.invokeMethod('appendMessage', {
        'role': role,
        'content': content,
      });
    } on PlatformException catch (e) {
      debugPrint('[FloatingChat] appendMessage failed: ${e.message}');
    }
  }

  Future<void> updateStreaming(String content) async {
    try {
      await _channel.invokeMethod('updateStreaming', {
        'content': content,
      });
    } on PlatformException catch (e) {
      debugPrint('[FloatingChat] updateStreaming failed: ${e.message}');
    }
  }

  Future<void> streamDone() async {
    try {
      await _channel.invokeMethod('streamDone');
    } on PlatformException catch (e) {
      debugPrint('[FloatingChat] streamDone failed: ${e.message}');
    }
  }

  Future<void> setGenerating(bool value) async {
    try {
      await _channel.invokeMethod('setGenerating', {'value': value});
    } on PlatformException catch (e) {
      debugPrint('[FloatingChat] setGenerating failed: ${e.message}');
    }
  }

  Future<void> syncMessages(List<Map<String, String>> messages) async {
    try {
      await _channel.invokeMethod('syncMessages', {'messages': messages});
    } on PlatformException catch (e) {
      debugPrint('[FloatingChat] syncMessages failed: ${e.message}');
    }
  }

  /// 更新状态栏 (思考中/执行工具)
  Future<void> updateStatus({String? status, String? tool}) async {
    try {
      await _channel.invokeMethod('updateStatus', {
        'status': status ?? '',
        'tool': tool ?? '',
      });
    } on PlatformException catch (e) {
      debugPrint('[FloatingChat] updateStatus failed: ${e.message}');
    }
  }

  void dispose() {
    _eventController.close();
  }
}
