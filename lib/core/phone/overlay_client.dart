import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../permission/permission_manager.dart';

/// 悬浮窗客户端
class OverlayClient {
  static const _channel = MethodChannel('com.myminimax/overlay');
  static bool get isSupported => Platform.isAndroid;

  Future<bool> show({String? title, String? text}) async {
    // 悬浮窗权限统一入口
    await PermissionManager().requireForTool(AppPermission.overlay);
    try {
      final result = await _channel.invokeMethod<bool>('show', {
        if (title != null) 'title': title,
        if (text != null) 'text': text,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception('Floating window show failed: ${e.message} / 悬浮窗显示失败: ${e.message}');
    }
  }

  Future<bool> hide() async {
    try {
      final result = await _channel.invokeMethod<bool>('hide');
      return result ?? false;
    } on PlatformException catch (e) {
      throw Exception('Floating window hide failed: ${e.message} / 悬浮窗隐藏失败: ${e.message}');
    }
  }

  Future<bool> isVisible() async {
    try {
      final result = await _channel.invokeMethod<bool>('isVisible');
      return result ?? false;
    } catch (e) {
      debugPrint('[OverlayClient] isVisible failed: $e');
      return false;
    }
  }
}

/// 通知监听客户端
class NotificationListenerClient {
  static const _channel = MethodChannel('com.myminimax/notification_listener');
  static bool get isSupported => Platform.isAndroid;

  Future<bool> isPermissionGranted() async {
    return PermissionManager().has(AppPermission.notificationListener);
  }

  Future<List<Map<String, dynamic>>> getRecentNotifications({int limit = 50}) async {
    try {
      final result = await _channel.invokeMethod<List>('getRecentNotifications', {'limit': limit});
      return result?.cast<Map<String, dynamic>>() ?? [];
    } on PlatformException catch (e) {
      throw Exception('Notification read failed: ${e.message} / 通知读取失败: ${e.message}');
    }
  }

  Future<void> clearNotifications() async {
    try {
      await _channel.invokeMethod('clearNotifications');
    } on PlatformException catch (e) {
      debugPrint('[NotificationListener] clearNotifications failed: $e');
    }
  }

  Future<void> postNotification({required String title, required String body}) async {
    try {
      await _channel.invokeMethod('postNotification', {'title': title, 'body': body});
    } on PlatformException catch (e) {
      throw Exception('Notification post failed: ${e.message} / 通知发布失败: ${e.message}');
    }
  }
}
