import 'dart:io';
import 'package:flutter/services.dart';
import '../permission/permission_manager.dart';

/// 通讯录客户端
class ContactsClient {
  static const _channel = MethodChannel('com.myminimax/contacts');
  static bool get isSupported => Platform.isAndroid;

  Future<List<Map<String, dynamic>>> search(String query) async {
    await PermissionManager().requireForTool(AppPermission.contacts);
    try {
      final result = await _channel.invokeMethod<List>('search', {'query': query});
      if (result == null) return [];
      return result.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } on PlatformException catch (e) {
      throw Exception('Contacts query failed: ${e.message} / 通讯录查询失败: ${e.message}');
    }
  }

  Future<Map<String, dynamic>?> getById(String contactId) async {
    await PermissionManager().requireForTool(AppPermission.contacts);
    try {
      final result = await _channel.invokeMethod<Map>('getById', {'contactId': contactId});
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw Exception('Contacts read failed: ${e.message} / 通讯录读取失败: ${e.message}');
    }
  }

  Future<String> createContact({
    required String givenName,
    String? familyName,
    String? phone,
    String? email,
  }) async {
    await PermissionManager().requireForTool(AppPermission.contacts);
    try {
      final result = await _channel.invokeMethod<String>('createContact', {
        'givenName': givenName,
        if (familyName != null) 'familyName': familyName,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
      });
      return result ?? '';
    } on PlatformException catch (e) {
      throw Exception('Create contact failed: ${e.message} / 创建联系人失败: ${e.message}');
    }
  }

  Future<String> deleteContact(String contactId) async {
    await PermissionManager().requireForTool(AppPermission.contacts);
    try {
      final result = await _channel.invokeMethod<String>('deleteContact', {'contactId': contactId});
      return result ?? '';
    } on PlatformException catch (e) {
      throw Exception('Delete contact failed: ${e.message} / 删除联系人失败: ${e.message}');
    }
  }
}

/// Calendar client / 日历客户端
class CalendarClient {
  static const _channel = MethodChannel('com.myminimax/calendar');
  static bool get isSupported => Platform.isAndroid;

  Future<List<Map<String, dynamic>>> queryEvents({
    required int startMs,
    required int endMs,
  }) async {
    await PermissionManager().requireForTool(AppPermission.calendar);
    try {
      final result = await _channel.invokeMethod<List>('query', {
        'startMs': startMs,
        'endMs': endMs,
      });
      if (result == null) return [];
      return result.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } on PlatformException catch (e) {
      throw Exception('Calendar query failed: ${e.message} / 日历查询失败: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> createEvent({
    required String title,
    required int startMs, required int endMs, String? description,
  }) async {
    await PermissionManager().requireForTool(AppPermission.calendar);
    try {
      final result = await _channel.invokeMethod<Map>('create', {
        'title': title,
        if (description != null) 'description': description,
        'startMs': startMs,
        'endMs': endMs,
      });
      if (result == null) return {};
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw Exception('Create calendar event failed: ${e.message} / 创建日历事件失败: ${e.message}');
    }
  }

  Future<bool> deleteEvent(String eventId) async {
    await PermissionManager().requireForTool(AppPermission.calendar);
    try {
      final result = await _channel.invokeMethod<String>('delete', {'eventId': eventId});
      return result != null && result.isNotEmpty;
    } on PlatformException catch (e) {
      throw Exception('Delete calendar event failed: ${e.message} / 删除日历事件失败: ${e.message}');
    }
  }
}

/// Phone client / 电话客户端
class PhoneClient {
  static const _channel = MethodChannel('com.myminimax/phone');
  static bool get isSupported => Platform.isAndroid;

  Future<void> call(String phoneNumber) async {
    await PermissionManager().requireForTool(AppPermission.phoneCall);
    try {
      await _channel.invokeMethod('call', {'phoneNumber': phoneNumber});
    } on PlatformException catch (e) {
      throw Exception('Phone call failed: ${e.message} / 拨号失败: ${e.message}');
    }
  }

  Future<List<Map<String, dynamic>>> getCallLog({int limit = 50}) async {
    await PermissionManager().requireForTool(AppPermission.phoneCall);
    try {
      final result = await _channel.invokeMethod<List>('getCallLog', {'limit': limit});
      if (result == null) return [];
      return result.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } on PlatformException catch (e) {
      throw Exception('Call log read failed: ${e.message} / 通话记录读取失败: ${e.message}');
    }
  }
}
