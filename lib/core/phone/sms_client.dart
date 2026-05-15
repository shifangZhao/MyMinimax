import 'dart:io';
import 'package:flutter/services.dart';
import '../permission/permission_manager.dart';

class SmsClient {
  static const _channel = MethodChannel('com.myminimax/sms');
  static bool get isSupported => Platform.isAndroid;

  Future<List<Map<String, dynamic>>> readInbox({
    int limit = 50,
    String? senderFilter,
  }) async {
    await PermissionManager().requireForTool(AppPermission.sms);
    try {
      final result = await _channel.invokeMethod<List>('readInbox', {
        'limit': limit,
        if (senderFilter != null) 'senderFilter': senderFilter,
      });
      if (result == null) return [];
      return result.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } on PlatformException catch (e) {
      throw Exception('SMS read failed: ${e.message} / 短信读取失败: ${e.message}');
    }
  }

  Future<List<Map<String, dynamic>>> getConversations({int limit = 20}) async {
    await PermissionManager().requireForTool(AppPermission.sms);
    try {
      final result = await _channel.invokeMethod<List>('getConversations', {'limit': limit});
      if (result == null) return [];
      return result.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } on PlatformException catch (e) {
      throw Exception('SMS conversation query failed: ${e.message} / 短信会话查询失败: ${e.message}');
    }
  }

  Future<String> sendSms({
    required String phoneNumber,
    required String message,
  }) async {
    await PermissionManager().requireForTool(AppPermission.sms);
    try {
      final result = await _channel.invokeMethod<String>('send', {
        'phoneNumber': phoneNumber,
        'message': message,
      });
      return result ?? '';
    } on PlatformException catch (e) {
      throw Exception('SMS send failed: ${e.message} / 短信发送失败: ${e.message}');
    }
  }

  Future<String> deleteSms(String smsId) async {
    await PermissionManager().requireForTool(AppPermission.sms);
    try {
      final result = await _channel.invokeMethod<String>('deleteSms', {'smsId': smsId});
      return result ?? '';
    } on PlatformException catch (e) {
      throw Exception('SMS delete failed: ${e.message} / 短信删除失败: ${e.message}');
    }
  }
}
