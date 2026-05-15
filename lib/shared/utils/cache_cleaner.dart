import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'temp_file_manager.dart';

class CacheCleanResult {
  const CacheCleanResult({required this.deletedCount, required this.freedBytes});
  final int deletedCount;
  final int freedBytes;

  String get sizeLabel {
    if (freedBytes < 1024) return '$freedBytes B';
    if (freedBytes < 1024 * 1024) return '${(freedBytes / 1024).toStringAsFixed(1)} KB';
    return '${(freedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class CacheCleaner {
  /// 扫描所有缓存目录，返回总文件数+总字节
  static Future<({int count, int bytes})> scanSize() async {
    int count = 0;
    int bytes = 0;

    final dirs = await _cacheDirs();
    for (final dir in dirs) {
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          count++;
          try {
            bytes += await entity.length();
          } catch (_) {}
        }
      }
    }
    return (count: count, bytes: bytes);
  }

  /// 清理旧文件（超过 [maxAgeDays] 天的），返回清理结果
  static Future<CacheCleanResult> cleanOld({int maxAgeDays = 7}) async {
    int count = 0;
    int bytes = 0;
    final cutoff = DateTime.now().subtract(Duration(days: maxAgeDays));

    final dirs = await _cacheDirs();
    for (final dir in dirs) {
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            if (stat.modified.isBefore(cutoff)) {
              bytes += await entity.length();
              await entity.delete();
              count++;
            }
          } catch (_) {}
        }
      }
    }

    // Also cleanup tracked temp files
    try {
      await TempFileManager().dispose();
    } catch (_) {}

    // Clean empty subdirectories
    for (final dir in dirs) {
      if (!await dir.exists()) continue;
      await _removeEmptyDirs(dir);
    }

    return CacheCleanResult(deletedCount: count, freedBytes: bytes);
  }

  /// 强制清理所有缓存文件（不限时间）
  static Future<CacheCleanResult> cleanAll() async {
    int count = 0;
    int bytes = 0;

    final dirs = await _cacheDirs();
    for (final dir in dirs) {
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            bytes += await entity.length();
            await entity.delete();
            count++;
          } catch (_) {}
        }
      }
    }

    try {
      await TempFileManager().dispose();
    } catch (_) {}

    for (final dir in dirs) {
      if (!await dir.exists()) continue;
      await _removeEmptyDirs(dir);
    }

    return CacheCleanResult(deletedCount: count, freedBytes: bytes);
  }

  static Future<List<Directory>> _cacheDirs() async {
    final tmp = await getTemporaryDirectory();
    final appDoc = await getApplicationDocumentsDirectory();
    // Screenshots stored in app documents
    final screenshotDir = Directory('${appDoc.path}/screenshots');
    return [
      tmp,
      screenshotDir,
    ];
  }

  static Future<void> _removeEmptyDirs(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is Directory) {
        await _removeEmptyDirs(entity);
        try {
          final contents = entity.list();
          if (await contents.isEmpty) await entity.delete();
        } catch (_) {}
      }
    }
  }
}
