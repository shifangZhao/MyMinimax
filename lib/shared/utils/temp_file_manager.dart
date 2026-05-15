import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Centralized temp file manager for document processing.
///
/// Provides unique prefixes per session to avoid collisions and
/// guarantees cleanup via [dispose] called on app shutdown.
class TempFileManager {
  factory TempFileManager() => _instance;
  TempFileManager._();
  static final TempFileManager _instance = TempFileManager._();

  final _files = <File>{};
  final _prefix = 'mm_${DateTime.now().millisecondsSinceEpoch}_';

  /// Create a temp file with a unique name and track it for cleanup.
  Future<File> createTemp(String suffix) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$_prefix${_files.length}_$suffix');
    _files.add(file);
    return file;
  }

  /// Register an externally-created temp file for tracked cleanup.
  void track(File file) => _files.add(file);

  /// Untrack and delete a single file.
  Future<void> delete(File file) async {
    _files.remove(file);
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Delete all tracked temp files. Call on app shutdown or session reset.
  Future<void> dispose() async {
    for (final file in _files.toList()) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    _files.clear();
  }

  /// Number of currently tracked files.
  int get count => _files.length;
}
