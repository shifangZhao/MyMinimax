import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../storage/database_helper.dart';
import '../saf/saf_client.dart';

class FileOperationTracker {
  final DatabaseHelper _db = DatabaseHelper();
  String? _currentMessageId;
  String? _currentConversationId;
  String? _currentSnapshotId;
  String? _currentBranchId;

  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/.snapshots');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  void setContext({required String messageId, required String conversationId, String? snapshotId, String? branchId}) {
    _currentMessageId = messageId;
    _currentConversationId = conversationId;
    _currentSnapshotId = snapshotId;
    _currentBranchId = branchId;
    debugPrint('[SNAPSHOT] setContext: msgId=$messageId, snapId=$snapshotId, branchId=$branchId');
  }

  Future<String> _getSnapshotsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/.snapshots';
  }

  /// 用户发送消息时初始化空快照占位
  Future<void> initializeSnapshotForMessage({
    required String messageId,
    required String conversationId,
    required String snapshotId,
    String? branchId,
  }) async {
    setContext(messageId: messageId, conversationId: conversationId, snapshotId: snapshotId, branchId: branchId);

    await _db.addFileSnapshot(
      messageId: messageId,
      conversationId: conversationId,
      filePath: '',
      operation: 'init',
      backupPath: null,
      snapshotId: snapshotId,
      branchId: branchId,
    );

    debugPrint('[SNAPSHOT] 初始化空快照: snapId=$snapshotId, msgId=$messageId');
  }

  Future<void> snapshotBefore(String filePath, String operation, {String? branchId}) async {
    if (_currentSnapshotId == null || _currentConversationId == null) return;
    final snapshotsDir = await _getSnapshotsDir();
    String? backupPath;

    final file = File(filePath);
    if (await file.exists()) {
      final backupName = '${_currentSnapshotId}_${DateTime.now().millisecondsSinceEpoch}_${filePath.split('/').last}';
      backupPath = '$snapshotsDir/$backupName';
      await file.copy(backupPath);
    }

    await _db.addFileSnapshot(
      messageId: _currentMessageId!,
      conversationId: _currentConversationId!,
      filePath: filePath,
      operation: operation,
      backupPath: backupPath,
      snapshotId: _currentSnapshotId,
      branchId: branchId ?? _currentBranchId,
    );

    debugPrint('[SNAPSHOT] snapshotBefore: snapId=$_currentSnapshotId, path=$filePath, op=$operation');
  }

  /// SAF 文件操作快照
  Future<void> snapshotBeforeSaf(String safRelPath, String operation, String? content, {String? branchId}) async {
    if (_currentSnapshotId == null || _currentMessageId == null) {
      debugPrint('[SNAPSHOT] 错误: 无上下文快照ID，跳过快照: path=$safRelPath');
      return;
    }
    final snapshotsDir = await _getSnapshotsDir();
    String? backupPath;

    if (content != null) {
      final safeName = safRelPath.replaceAll('/', '_').replaceAll('\\', '_');
      final backupName = '${_currentSnapshotId}_${DateTime.now().millisecondsSinceEpoch}_saf_$safeName';
      backupPath = '$snapshotsDir/$backupName';
      await File(backupPath).writeAsString(content);
    }

    await _db.addFileSnapshot(
      messageId: _currentMessageId!,
      conversationId: _currentConversationId!,
      filePath: 'saf://$safRelPath',
      operation: operation,
      backupPath: backupPath,
      snapshotId: _currentSnapshotId,
      branchId: branchId ?? _currentBranchId,
    );

    debugPrint('[SNAPSHOT] snapshotBeforeSaf: snapId=$_currentSnapshotId, path=saf://$safRelPath, op=$operation');
  }

  /// 按 snapshotId 回溯恢复文件状态
  Future<int> rollbackToSnapshot(String snapshotId, {SafClient? safClient, String? safUri}) async {
    debugPrint('[SNAPSHOT] 回溯到快照: $snapshotId');

    final snapshots = await _db.getFileSnapshotsBySnapshotId(snapshotId);
    if (snapshots.isEmpty) {
      debugPrint('[SNAPSHOT] 快照无文件操作: $snapshotId');
      return 0;
    }

    // 按时间倒序恢复（先恢复最后的修改）
    final sorted = snapshots.toList()
      ..sort((a, b) => (b['created_at'] as int? ?? 0).compareTo(a['created_at'] as int? ?? 0));

    int succeeded = 0;
    int failed = 0;

    for (final snap in sorted) {
      final op = snap['operation'] as String? ?? snap['operation_type'] as String? ?? '';
      final filePath = snap['file_path'] as String;
      final backupPath = snap['backup_path'] as String?;

      if (op == 'init') continue; // 空快照跳过

      try {
        if (filePath.startsWith('saf://') && safClient != null && safUri != null) {
          final safRelPath = filePath.substring(6);
          final backup = backupPath != null ? File(backupPath) : null;
          switch (op) {
            case 'write':
              if (backup != null && await backup.exists()) {
                await safClient.writeFile(safUri, safRelPath, await backup.readAsString());
              }
              break;
            case 'create':
              try { await safClient.deleteFile(safUri, safRelPath); } catch (e) { debugPrint('[SNAPSHOT] SAF delete rollback failed: $safRelPath - $e'); }
                print('[file] error: \$e');
              break;
            case 'delete':
              if (backup != null && await backup.exists()) {
                await safClient.writeFile(safUri, safRelPath, await backup.readAsString());
              }
              break;
          }
        } else {
          final file = File(filePath);
          switch (op) {
            case 'write':
              if (backupPath != null) {
                final backup = File(backupPath);
                if (await backup.exists()) {
                  await backup.copy(filePath);
                  debugPrint('[SNAPSHOT] 恢复文件: $filePath');
                }
              }
              break;
            case 'create':
              if (await file.exists()) {
                await file.delete();
                debugPrint('[SNAPSHOT] 删除创建的文件: $filePath');
              }
              break;
            case 'delete':
              if (backupPath != null) {
                final backup = File(backupPath);
                if (await backup.exists()) {
                  await backup.copy(filePath);
                  debugPrint('[SNAPSHOT] 恢复删除的文件: $filePath');
                }
              }
              break;
          }
        }
        succeeded++;
      } catch (e) {
        failed++;
        debugPrint('[SNAPSHOT] Rollback error for $filePath ($op): $e');
      }
    }

    debugPrint('[SNAPSHOT] 回溯完成: $succeeded succeeded, $failed failed');
    return succeeded + failed;
  }

  Future<int> rollbackAfter(String conversationId, int timestamp, {SafClient? safClient, String? safUri, String? branchId}) async {
    await init();
    final msgs = await _db.getMessages(conversationId, activeOnly: false, branchId: branchId);
    final deactivatedIds = msgs
        .where((m) => (m['created_at'] as int) > timestamp)
        .map((m) => m['id'] as String)
        .toList();

    if (deactivatedIds.isEmpty) return 0;

    final snapshots = await _db.getFileSnapshotsByMessages(deactivatedIds);
    int succeeded = 0;
    int failed = 0;

    for (final snap in snapshots) {
      final filePath = snap['file_path'] as String;
      final operation = snap['operation'] as String;
      final backupPath = snap['backup_path'] as String?;

      try {
        if (filePath.startsWith('saf://') && safClient != null && safUri != null) {
          final safRelPath = filePath.substring(6);
          final backup = backupPath != null ? File(backupPath) : null;
          switch (operation) {
            case 'write':
              if (backup != null && await backup.exists()) {
                await safClient.writeFile(safUri, safRelPath, await backup.readAsString());
              }
              break;
            case 'create':
              try { await safClient.deleteFile(safUri, safRelPath); } catch (e) { debugPrint('[FileTracker] SAF delete rollback failed: $safRelPath - $e'); }
                print('[file] error: \$e');
              break;
            case 'delete':
              if (backup != null && await backup.exists()) {
                await safClient.writeFile(safUri, safRelPath, await backup.readAsString());
              }
              break;
          }
        } else {
          final file = File(filePath);
          switch (operation) {
            case 'write':
              if (backupPath != null) {
                final backup = File(backupPath);
                if (await backup.exists()) {
                  await backup.copy(filePath);
                }
              }
              break;
            case 'create':
              if (await file.exists()) {
                await file.delete();
              }
              break;
            case 'delete':
              if (backupPath != null) {
                final backup = File(backupPath);
                if (await backup.exists()) {
                  await backup.copy(filePath);
                }
              }
              break;
          }
        }
        succeeded++;
      } catch (e) {
        failed++;
        debugPrint('[FileTracker] Rollback error for $filePath ($operation): $e');
      }
    }

    if (failed > 0) {
      debugPrint('[FileTracker] Rollback summary: $succeeded succeeded, $failed failed');
    }
    return succeeded + failed;
  }

  Future<Map<String, String>> saveUndoBackups(List<String> messageIds) async {
    final undoBackups = <String, String>{};
    final snapshots = await _db.getFileSnapshotsByMessages(messageIds);
    final undoDir = await _getSnapshotsDir();
    final undoSubDir = '$undoDir/undo';

    for (final snap in snapshots) {
      final filePath = snap['file_path'] as String;
      if (filePath.startsWith('saf://')) {
        continue;
      }
      try {
        final file = File(filePath);
        if (await file.exists()) {
          final backupName = 'undo_${DateTime.now().millisecondsSinceEpoch}_${filePath.hashCode}_${filePath.split('/').last}';
          final undoBackup = '$undoSubDir/$backupName';
          await Directory(undoSubDir).create(recursive: true);
          await file.copy(undoBackup);
          undoBackups[filePath] = undoBackup;
        }
      } catch (_) {}
    }
    return undoBackups;
  }

  Future<int> restoreUndoBackups(Map<String, String> undoBackups) async {
    int restored = 0;
    for (final entry in undoBackups.entries) {
      try {
        final backup = File(entry.value);
        if (await backup.exists()) {
          await backup.copy(entry.key);
          await backup.delete();
          restored++;
        }
      } catch (e) {
        debugPrint('[FileTracker] Undo restore failed for ${entry.key}: $e');
      }
    }
    return restored;
  }

  Future<void> cleanupUndoBackups(Map<String, String> undoBackups) async {
    for (final path in undoBackups.values) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> cleanupOldSnapshots({int daysToKeep = 7}) async {
    final snapshotsDir = await _getSnapshotsDir();
    final dir = Directory(snapshotsDir);
    if (!await dir.exists()) return;

    final cutoff = DateTime.now().subtract(Duration(days: daysToKeep));
    await for (final entity in dir.list()) {
      if (entity is File) {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
        }
      }
    }
  }

  /// 清理回溯后被软删消息的快照记录（数据库层面）
  Future<void> cleanupSnapshotsAfter(String conversationId, int beforeTimestamp, {String? branchId}) async {
    await _db.deleteFileSnapshotsAfter(conversationId, beforeTimestamp, branchId: branchId);
    debugPrint('[SNAPSHOT] 清理快照记录: conv=$conversationId before=$beforeTimestamp');
  }
}
