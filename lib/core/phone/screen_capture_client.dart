import 'dart:io';
import 'package:flutter/services.dart';

class ScreenCaptureClient {
  static const _channel = MethodChannel('com.myminimax/screen_capture');
  static bool get isSupported => Platform.isAndroid;

  /// 截取屏幕并保存为 PNG 文件，返回文件路径。
  /// [outputPath] 可选，不传则保存到缓存目录。
  Future<String> capture({String? outputPath}) async {
    if (!isSupported) {
      throw PlatformException(
        code: 'NOT_SUPPORTED',
        message: 'Screen capture only available on Android / 截屏功能仅在 Android 上可用',
      );
    }
    try {
      final path = await _channel.invokeMethod<String>('capture', {
        if (outputPath != null) 'outputPath': outputPath,
      });
      if (path == null || path.isEmpty) {
        throw PlatformException(code: 'CAPTURE_ERROR', message: '截屏返回空路径');
      }
      return path;
    } on PlatformException {
      rethrow;
    } catch (e) {
      print('[screen] error: \$e');
      throw PlatformException(code: 'CAPTURE_ERROR', message: e.toString());
    }
  }

  /// 是否已获得截屏权限
  Future<bool> hasPermission() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 释放截屏资源
  Future<void> release() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('release');
    } catch (_) {}
  }
}
