/// An entry in the working memory store.
class WorkingMemoryEntry {
  WorkingMemoryEntry({
    required this.key,
    required this.value,
    required this.sourceTaskId,
    this.ttl,
  }) : createdAt = DateTime.now();

  final String key;
  final dynamic value;
  final String sourceTaskId;
  final DateTime createdAt;
  final Set<String> readBy = <String>{};
  final Duration? ttl;

  bool get isExpired {
    if (ttl == null) return false;
    return createdAt.add(ttl!).isBefore(DateTime.now());
  }

  WorkingMemoryEntry markReadBy(String taskId) {
    readBy.add(taskId);
    return this;
  }
}

/// Structured key-value store for inter-sub-task data passing.
class WorkingMemory {
  final Map<String, WorkingMemoryEntry> _store = {};

  void set(String key, dynamic value,
      {required String sourceTaskId, Duration? ttl}) {
    _store[key] = WorkingMemoryEntry(
      key: key,
      value: value,
      sourceTaskId: sourceTaskId,
      ttl: ttl,
    );
  }

  T? get<T>(String key, {String? readerTaskId}) {
    final entry = _store[key];
    if (entry == null || entry.isExpired) return null;
    if (readerTaskId != null) entry.markReadBy(readerTaskId);
    return entry.value as T?;
  }

  List<WorkingMemoryEntry> getBySource(String taskId) {
    return _store.values.where((e) => e.sourceTaskId == taskId).toList();
  }

  /// Returns entries accessible by [taskId]:
  /// entries whose source task is a completed dependency.
  List<WorkingMemoryEntry> getForTask(String taskId,
      {required List<String> dependencyIds}) {
    return _store.values
        .where((e) => dependencyIds.contains(e.sourceTaskId) && !e.isExpired)
        .toList();
  }

  /// Builds a context string for injection into a sub-task's system prompt.
  String buildContextString(String forTaskId,
      {required List<String> dependencyIds}) {
    final entries = getForTask(forTaskId, dependencyIds: dependencyIds);
    if (entries.isEmpty) return '';

    final buf = StringBuffer('## Working Memory Context\n');
    // Deduplicate by latest entry per source task
    final latest = <String, WorkingMemoryEntry>{};
    for (final e in entries) {
      latest[e.key] = e;
    }
    for (final entry in latest.values) {
      final val = entry.value is String
          ? entry.value as String
          : entry.value.toString();
      final truncated = val.length > 200 ? '${val.substring(0, 200)}...' : val;
      buf.writeln('- ${entry.key}: $truncated');
    }
    return buf.toString();
  }

  /// Serialize to a JSON-compatible map.
  Map<String, dynamic> snapshot() {
    return {
      for (final entry in _store.values)
        entry.key: {
          'value': entry.value,
          'sourceTaskId': entry.sourceTaskId,
          'createdAt': entry.createdAt.toIso8601String(),
          'readBy': entry.readBy.toList(),
          if (entry.ttl != null) 'ttl': entry.ttl!.inSeconds,
        },
    };
  }
}
