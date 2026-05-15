/// Memory data models and enums for the revamped memory system.
library;

import 'dart:convert';

/// mem0-style memory type classification.
enum MemoryType { semantic, episodic, procedural }

/// Memory lifecycle status (ADD-only: never overwrite, only supersede).
enum MemoryStatus { active, superseded, rejected }

class MemoryEntry {

  MemoryEntry({
    required this.id,
    required this.memoryType,
    required this.content,
    required this.contentHash,
    required this.category,
    required this.createdAt, this.key,
    List<String>? entities,
    List<String>? linkedMemoryIds,
    this.confidence = 'medium',
    this.source = 'ai',
    this.sourceDetail = '',
    this.status = MemoryStatus.active,
    this.supersededBy,
    this.embedding,
    this.embeddingSource = '',
    this.updatedAt,
  })  : entities = entities ?? const [],
        linkedMemoryIds = linkedMemoryIds ?? const [];

  factory MemoryEntry.fromDb(Map<String, dynamic> row) {
    List<double>? embedding;
    final embedRaw = row['embedding'] as String?;
    if (embedRaw != null && embedRaw.isNotEmpty) {
      try {
        embedding = (jsonDecode(embedRaw) as List).cast<double>();
      } catch (_) {}
    }

    return MemoryEntry(
      id: row['id'] as String,
      memoryType: MemoryType.values.firstWhere(
        (t) => t.name == row['memory_type'],
        orElse: () => MemoryType.semantic,
      ),
      content: row['content'] as String,
      contentHash: row['content_hash'] as String? ?? '',
      category: row['category'] as String? ?? 'static',
      key: row['key'] as String?,
      entities: _parseJsonList(row['entities'] as String?),
      linkedMemoryIds: _parseJsonList(row['linked_memory_ids'] as String?),
      confidence: row['confidence'] as String? ?? 'medium',
      source: row['source'] as String? ?? 'ai',
      sourceDetail: row['source_detail'] as String? ?? '',
      status: MemoryStatus.values.firstWhere(
        (s) => s.name == (row['status'] as String? ?? 'active'),
        orElse: () => MemoryStatus.active,
      ),
      supersededBy: row['superseded_by'] as String?,
      embedding: embedding,
      embeddingSource: row['embedding_source'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: row['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int)
          : null,
    );
  }
  final String id;
  final MemoryType memoryType;
  final String content;
  final String contentHash;
  final String category;
  final String? key;
  final List<String> entities;
  final List<String> linkedMemoryIds;
  final String confidence;
  final String source;
  final String sourceDetail;
  final MemoryStatus status;
  final String? supersededBy;
  final List<double>? embedding;
  final String embeddingSource;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toDb() => {
        'id': id,
        'memory_type': memoryType.name,
        'content': content,
        'content_hash': contentHash,
        'category': category,
        'key': key,
        'entities': _encodeJsonList(entities),
        'linked_memory_ids': _encodeJsonList(linkedMemoryIds),
        'confidence': confidence,
        'source': source,
        'source_detail': sourceDetail,
        'status': status.name,
        'superseded_by': supersededBy,
        'embedding': embedding != null ? jsonEncode(embedding) : '',
        'embedding_source': embeddingSource,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt?.millisecondsSinceEpoch,
      };

  /// Format one line for system prompt injection.
  String toSystemPromptLine() {
    final age = DateTime.now().difference(createdAt);
    final ageStr = age.inDays > 30
        ? '${age.inDays ~/ 30}月前'
        : age.inDays > 0
            ? '${age.inDays}天前'
            : '今天';
    return '[$ageStr][$confidence] $content';
  }

  static List<String> _parseJsonList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = _jsonDecode(raw);
      if (decoded is List) return decoded.cast<String>();
      return const [];
    } catch (_) {
      return const [];
    }
  }

  static String _encodeJsonList(List<String> list) {
    if (list.isEmpty) return '[]';
    return _jsonEncode(list);
  }

  static dynamic _jsonDecode(String s) {
    // Use dart:convert — imported at top
    return const _JsonCodec().decode(s);
  }

  static String _jsonEncode(List<String> list) {
    return const _JsonCodec().encode(list);
  }
}

class _JsonCodec {

  const _JsonCodec();
  final JsonDecoder _decoder = const JsonDecoder();
  final JsonEncoder _encoder = const JsonEncoder();

  dynamic decode(String s) => _decoder.convert(s);
  String encode(Object o) => _encoder.convert(o);
}
