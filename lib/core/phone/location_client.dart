import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import '../permission/permission_manager.dart';

class LocationClient {
  static const _locationChannel = MethodChannel('com.myminimax/location');
  static bool get isSupported => Platform.isAndroid;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  Future<Map<String, dynamic>> getCurrentPosition() async {
    if (!isSupported) {
      try {
        return await _ipLocationFallback();
      } catch (_) {
        return {};
      }
    }

    // 统一权限入口
    try {
      await PermissionManager().requireForTool(AppPermission.location);
    } catch (_) {
      // 权限被拒时降级到 IP 定位
      try {
        return await _ipLocationFallback();
      } catch (_) {
        return {};
      }
    }

    try {
      final result = await _locationChannel.invokeMethod<Map>('getCurrentPosition');
      final map = result?.cast<String, dynamic>();
      if (map != null && map.isNotEmpty) {
        map['source'] = 'gps';
        return map;
      }
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION' || e.code == 'UNAVAILABLE' || e.code == 'TIMEOUT') {
        // Fall through to IP fallback
      } else {
        rethrow;
      }
    }

    try {
      return await _ipLocationFallback();
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>> _ipLocationFallback() async {
    try {
      final resp = await _dio.get('https://ipapi.co/json/');
      if (resp.statusCode == 200 && resp.data is Map) {
        final d = resp.data as Map<String, dynamic>;
        if (d['latitude'] != null && d['longitude'] != null) {
          return {
            'latitude': (d['latitude'] as num).toDouble(),
            'longitude': (d['longitude'] as num).toDouble(),
            'city': d['city'] as String? ?? '',
            'region': d['region'] as String? ?? '',
            'country': d['country_name'] as String? ?? '',
            'source': 'ip',
          };
        }
      }
    } catch (_) {}

    try {
      final resp = await _dio.get('https://ip-api.com/json/');
      if (resp.statusCode == 200 && resp.data is Map) {
        final d = resp.data as Map<String, dynamic>;
        if (d['lat'] != null && d['lon'] != null) {
          return {
            'latitude': (d['lat'] as num).toDouble(),
            'longitude': (d['lon'] as num).toDouble(),
            'city': d['city'] as String? ?? '',
            'region': d['regionName'] as String? ?? '',
            'country': d['country'] as String? ?? '',
            'source': 'ip',
          };
        }
      }
    } catch (_) {}

    throw Exception('IP location failed');
  }
}
