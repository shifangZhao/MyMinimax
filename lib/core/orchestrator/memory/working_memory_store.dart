import '../models/working_memory.dart';

/// Persistent working memory store.
/// Currently in-memory only; can be extended with SQLite persistence.
class WorkingMemoryStore {
  WorkingMemoryStore() : memory = WorkingMemory();

  final WorkingMemory memory;
  String? _orchestrationId;

  String? get orchestrationId => _orchestrationId;

  /// Initialize the store for a new orchestration run.
  void initialize(String orchestrationId, [Map<String, dynamic> initialData = const {}]) {
    _orchestrationId = orchestrationId;
    for (final entry in initialData.entries) {
      memory.set(entry.key, entry.value, sourceTaskId: '__init__');
    }
  }

  /// Store a working memory entry.
  void set(String key, dynamic value, {required String sourceTaskId, Duration? ttl}) {
    memory.set(key, value, sourceTaskId: sourceTaskId, ttl: ttl);
  }

  /// Retrieve a working memory entry.
  T? get<T>(String key, {String? readerTaskId}) {
    return memory.get<T>(key, readerTaskId: readerTaskId);
  }

  /// Export all state for serialization.
  Map<String, dynamic> snapshot() {
    return {
      'orchestrationId': _orchestrationId,
      'memory': memory.snapshot(),
    };
  }

  /// Reset the store.
  void reset() {
    _orchestrationId = null;
  }
}
