import '../../engine/file_operation_tracker.dart';

/// Rollback manager for orchestration file changes.
///
/// Leverages the existing [FileOperationTracker] to roll back file changes
/// made during sub-task execution. Uses timestamp-based rollback:
/// captures the checkpoint before orchestration starts, then rolls back
/// all changes after that point on failure.
class OrchestrationRollback {
  FileOperationTracker? _fileTracker;
  String? _conversationId;
  int? _checkpointTimestamp;

  /// Attach the conversation's file tracker and set the rollback checkpoint.
  void attach(FileOperationTracker tracker, String conversationId) {
    _fileTracker = tracker;
    _conversationId = conversationId;
    _checkpointTimestamp = DateTime.now().millisecondsSinceEpoch;
  }

  /// Roll back all file changes made since the checkpoint.
  Future<int> rollbackAll({String? branchId}) async {
    if (_fileTracker == null || _conversationId == null || _checkpointTimestamp == null) {
      return 0;
    }
    return _fileTracker!.rollbackAfter(
      _conversationId!,
      _checkpointTimestamp!,
      branchId: branchId,
    );
  }

  /// Whether a rollback checkpoint has been established.
  bool get hasCheckpoint => _checkpointTimestamp != null;

  /// Reset the checkpoint (call when orchestration completes successfully).
  void clear() {
    _fileTracker = null;
    _conversationId = null;
    _checkpointTimestamp = null;
  }
}
