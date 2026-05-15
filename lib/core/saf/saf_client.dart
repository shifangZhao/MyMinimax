import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

class SafFileEntry {

  const SafFileEntry({
    required this.name,
    required this.uri,
    required this.isDirectory,
    required this.lastModified, this.size = 0,
  });

  factory SafFileEntry.fromMap(Map<dynamic, dynamic> map) {
    final lastModifiedMs = (map['lastModified'] as int?) ?? 0;
    return SafFileEntry(
      name: map['name'] as String? ?? '',
      uri: map['uri'] as String? ?? '',
      isDirectory: map['isDirectory'] as bool? ?? false,
      size: (map['size'] as int?) ?? 0,
      lastModified: lastModifiedMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastModifiedMs)
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
  final String name;
  final String uri;
  final bool isDirectory;
  final int size;
  final DateTime lastModified;
}

class SafClient {
  static const _channel = MethodChannel('com.myminimax/saf');

  static bool get isSupported => Platform.isAndroid;

  /// 弹出 SAF 目录选择器，返回 content:// URI
  Future<String?> pickDirectory() async {
    try {
      final result = await _channel.invokeMethod<String>('pickDirectory');
      return result;
    } on PlatformException catch (_) {
      return null;
    }
  }

  /// 持久化 URI 权限（跨重启保留）
  Future<bool> persistUriPermission(String uri) async {
    try {
      final result = await _channel.invokeMethod<bool>('persistUriPermission', {'uri': uri});
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// 读取文件内容
  Future<String> readFile(String treeUri, String relativePath) async {
    try {
      final result = await _channel.invokeMethod<String>('readFile', {
        'treeUri': treeUri,
        'path': relativePath,
      });
      return result ?? '';
    } on PlatformException catch (e) {
      throw Exception('SAF read file failed: ${e.message} / SAF 读取文件失败: ${e.message}');
    }
  }

  /// 写入文件（自动创建）
  Future<void> writeFile(String treeUri, String relativePath, String content) async {
    try {
      await _channel.invokeMethod('writeFile', {
        'treeUri': treeUri,
        'path': relativePath,
        'content': content,
      });
    } on PlatformException catch (e) {
      throw Exception('SAF write file failed: ${e.message} / SAF 写入文件失败: ${e.message}');
    }
  }

  /// 新建目录
  Future<void> createDirectory(String treeUri, String relativePath) async {
    try {
      await _channel.invokeMethod('createDirectory', {
        'treeUri': treeUri,
        'path': relativePath,
      });
    } on PlatformException catch (e) {
      throw Exception('SAF create directory failed: ${e.message} / SAF 新建目录失败: ${e.message}');
    }
  }

  /// 删除文件或目录
  Future<void> deleteFile(String treeUri, String relativePath) async {
    try {
      await _channel.invokeMethod('deleteFile', {
        'treeUri': treeUri,
        'path': relativePath,
      });
    } on PlatformException catch (e) {
      throw Exception('SAF delete file failed: ${e.message} / SAF 删除文件失败: ${e.message}');
    }
  }

  /// 读取文件原始字节（Base64编码传输）
  Future<Uint8List?> readFileBytes(String treeUri, String relativePath) async {
    try {
      final result = await _channel.invokeMethod<String>('readFileBytes', {
        'treeUri': treeUri,
        'path': relativePath,
      });
      if (result == null || result.isEmpty) return null;
      return Uint8List.fromList(base64.decode(result));
    } on PlatformException catch (e) {
      throw Exception('SAF read file bytes failed: ${e.message} / SAF 读取文件字节失败: ${e.message}');
    }
  }

  /// 写入文件原始字节（Base64编码传输）
  Future<void> writeFileBytes(String treeUri, String relativePath, Uint8List bytes) async {
    try {
      final base64Content = base64.encode(bytes);
      await _channel.invokeMethod('writeFileBytes', {
        'treeUri': treeUri,
        'path': relativePath,
        'content': base64Content,
      });
    } on PlatformException catch (e) {
      throw Exception('SAF write file bytes failed: ${e.message} / SAF 写入文件字节失败: ${e.message}');
    }
  }

  /// 列出目录内容
  Future<List<SafFileEntry>> listFiles(String treeUri, String? relativePath) async {
    try {
      final result = await _channel.invokeMethod<List>('listFiles', {
        'treeUri': treeUri,
        'path': relativePath ?? '',
      });
      if (result == null) return [];
      return result.map((e) => SafFileEntry.fromMap(e as Map<dynamic, dynamic>)).toList();
    } on PlatformException catch (e) {
      throw Exception('SAF list files failed: ${e.message} / SAF 列出文件失败: ${e.message}');
    }
  }
}
