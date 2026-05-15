/// MemoryCache — mem0-style memory layer with ADD-only strategy, hash dedup,
/// relevance-based retrieval, and backward-compatible API.
library;

import 'dart:convert';
import '../../../core/api/minimax_client.dart';
import '../../../core/storage/database_helper.dart';
import 'memory_entry.dart';
import 'memory_retriever.dart';
import 'memory_embedder.dart';
import 'content_hasher.dart';
import 'entity_extractor.dart';

/// AI 发现的待确认记忆条目（兼容旧 API）
class PendingEntry {

  PendingEntry({
    required this.type,
    required this.key,
    required this.value,
    this.confidence = 'medium',
    this.source = 'ai',
    this.sourceDetail = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  final String type;
  final String key;
  final String value;
  final String confidence;
  final String source;
  final String sourceDetail;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'type': type,
        'key': key,
        'value': value,
        'confidence': confidence,
        'source': source,
        'sourceDetail': sourceDetail,
        'createdAt': createdAt.toIso8601String(),
      };
}

class MemoryCache {
  MemoryCache({DatabaseHelper? db, MinimaxClient? client})
      : _db = db ?? DatabaseHelper(),
        _embedder = client != null ? MemoryEmbedder(client: client, db: db) : null,
        _retriever = MemoryRetriever(db ?? DatabaseHelper());
  final DatabaseHelper _db;
  MemoryEmbedder? _embedder;
  late MemoryRetriever _retriever;

  // --- in-memory indexes ---
  final List<MemoryEntry> _allActive = [];
  final Map<String, MemoryEntry> _byId = {};
  final Map<String, MemoryEntry> _byCategoryKey = {}; // "category:key" → entry

  // Pending (AI-discovered, not yet confirmed by user)
  final List<MemoryEntry> _pendingList = [];

  // Tasks (from new tasks table)
  final Map<String, Map<String, dynamic>> _tasks = {};

  bool _loaded = false;
  Future<void>? _loadFuture;

  final List<void Function()> _listeners = [];
  void Function()? onChange;

  static final MemoryCache instance = MemoryCache();

  /// 注入依赖（Embedder 需要 MinimaxClient，通过 Riverpod 延迟注入）。
  /// Token Plan 密钥不支持 embo-01 embedding API，跳过嵌入层。
  void configure({MinimaxClient? client}) {
    if (client != null) {
      if (!MinimaxClient.isTokenPlanKey(client.apiKey)) {
        _embedder = MemoryEmbedder(client: client, db: _db);
      }
      _retriever = MemoryRetriever(_db, embedder: _embedder);
    }
  }

  bool get isLoaded => _loaded;

  /// All active memories (for dedup reference during extraction).
  List<MemoryEntry> get allActive => List.unmodifiable(_allActive);

  void addListener(void Function() cb) => _listeners.add(cb);
  void removeListener(void Function() cb) => _listeners.remove(cb);

  void _notifyChange() {
    onChange?.call();
    for (final cb in _listeners) {
      cb();
    }
  }

  // ===== Load =====

  Future<void> load() async {
    if (_loaded) return;
    if (_loadFuture != null) {
      await _loadFuture;
      return;
    }
    _loadFuture = _doLoad();
    await _loadFuture;
    _loadFuture = null;
  }

  Future<void> _doLoad() async {
    _allActive.clear();
    _byId.clear();
    _byCategoryKey.clear();
    _pendingList.clear();
    _tasks.clear();
    _retriever = MemoryRetriever(_db, embedder: _embedder);

    // Load active memories
    final rows = await _db.getAllMemories(status: 'active');
    for (final r in rows) {
      var entry = MemoryEntry.fromDb(r);

      // Fix placeholder hashes from migration
      if (entry.contentHash.isEmpty ||
          !entry.contentHash.contains(RegExp(r'^[0-9a-f]{32,}$'))) {
        final realHash = ContentHasher.hash(entry.content);
        await _db.updateMemory(entry.id, {'content_hash': realHash});
        entry = MemoryEntry(
          id: entry.id,
          memoryType: entry.memoryType,
          content: entry.content,
          contentHash: realHash,
          category: entry.category,
          key: entry.key,
          entities: entry.entities,
          linkedMemoryIds: entry.linkedMemoryIds,
          confidence: entry.confidence,
          source: entry.source,
          sourceDetail: entry.sourceDetail,
          status: entry.status,
          supersededBy: entry.supersededBy,
          createdAt: entry.createdAt,
          updatedAt: entry.updatedAt,
        );
        // fall through to add to indexes below
      }

      _allActive.add(entry);
      _byId[entry.id] = entry;
      if (entry.key != null && entry.key!.isNotEmpty) {
        _byCategoryKey['${entry.category}:${entry.key}'] = entry;
      }

      // Run entity extraction if missing (from migration)
      if (entry.entities.isEmpty && entry.content.isNotEmpty) {
        final entities = EntityExtractor.extract(entry.content);
        if (entities.isNotEmpty) {
          await _db.updateMemory(entry.id, {
            'entities': jsonEncode(entities),
          });
        }
      }
    }

    // Load tasks
    final taskRows = await _db.getAllTasks();
    for (final t in taskRows) {
      _tasks[t['id'] as String] = t;
    }

    _loaded = true;
  }

  void loadFromRows(List<Map<String, dynamic>> rows) {
    // Legacy method — minimal support
    _allActive.clear();
    _byId.clear();
    _byCategoryKey.clear();
    _pendingList.clear();
    for (final r in rows) {
      final type = r['type'] as String?;
      if (type == 'task') {
        _tasks[r['id'] as String] = r;
      } else {
        final entry = MemoryEntry.fromDb({
          'id': r['id'],
          'memory_type': 'semantic',
          'content': r['value'] ?? '',
          'content_hash': '',
          'category': type ?? 'static',
          'key': r['key'],
          'confidence': 'manual',
          'source': 'manual',
          'status': 'active',
          'created_at': r['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
        });
        _allActive.add(entry);
        _byId[entry.id] = entry;
        if (entry.key != null && entry.key!.isNotEmpty) {
          _byCategoryKey['${entry.category}:${entry.key}'] = entry;
        }
      }
    }
    _loaded = true;
  }

  // ===== ADD-only insert =====

  /// Add a memory. Returns existing if hash-match, or new entry.
  Future<MemoryEntry> addMemory({
    required String content,
    MemoryType memoryType = MemoryType.semantic,
    String category = 'dynamic',
    String? key,
    List<String> entities = const [],
    List<String> linkedMemoryIds = const [],
    String confidence = 'medium',
    String source = 'ai',
    String sourceDetail = '',
  }) async {
    final hash = ContentHasher.hash(content);

    // Hash dedup: skip if identical content already active
    for (final m in _allActive) {
      if (m.contentHash == hash) return m;
    }

    // Supersede: same category+key, higher confidence replaces old
    String? supersedes;
    if (key != null && key.isNotEmpty) {
      final existing = _byCategoryKey['$category:$key'];
      if (existing != null && _confRank(confidence) >= _confRank(existing.confidence)) {
        await _db.updateMemory(existing.id, {
          'status': 'superseded',
          'superseded_by': null, // will set after insert
        });
        supersedes = existing.id;
      }
    }

    // Auto-extract entities if not provided
    List<String> ents = entities;
    if (ents.isEmpty) {
      ents = EntityExtractor.extract(content);
    }

    final id = _genId();
    final entry = MemoryEntry(
      id: id,
      memoryType: memoryType,
      content: content,
      contentHash: hash,
      category: category,
      key: key,
      entities: ents,
      linkedMemoryIds: linkedMemoryIds,
      confidence: confidence,
      source: source,
      sourceDetail: sourceDetail,
      status: MemoryStatus.active,
      supersededBy: null,
      createdAt: DateTime.now(),
    );

    await _db.insertMemory(entry.toDb());

    // Update superseded_by on old entry
    if (supersedes != null) {
      await _db.updateMemory(supersedes, {'superseded_by': id});
    }

    _allActive.add(entry);
    _byId[id] = entry;
    if (key != null && key.isNotEmpty) {
      _byCategoryKey['$category:$key'] = entry;
    }

    _notifyChange();
    return entry;
  }

  int _confRank(String c) {
    switch (c) {
      case 'manual': return 4;
      case 'high': return 3;
      case 'medium': return 2;
      case 'low': return 1;
      default: return 0;
    }
  }

  String _genId() => 'mem_${DateTime.now().microsecondsSinceEpoch}';

  /// Link two memories.
  Future<void> linkMemories(String childId, String parentId) async {
    final child = _byId[childId];
    if (child == null || child.linkedMemoryIds.contains(parentId)) return;

    final newLinks = [...child.linkedMemoryIds, parentId];
    await _db.updateMemory(childId, {
      'linked_memory_ids': jsonEncode(newLinks),
    });
    // Update in-memory
    final updated = MemoryEntry(
      id: child.id,
      memoryType: child.memoryType,
      content: child.content,
      contentHash: child.contentHash,
      category: child.category,
      key: child.key,
      entities: child.entities,
      linkedMemoryIds: newLinks,
      confidence: child.confidence,
      source: child.source,
      sourceDetail: child.sourceDetail,
      status: child.status,
      supersededBy: child.supersededBy,
      createdAt: child.createdAt,
      updatedAt: DateTime.now(),
    );
    final idx = _allActive.indexWhere((m) => m.id == childId);
    if (idx >= 0) _allActive[idx] = updated;
    _byId[childId] = updated;
  }

  // ===== Relevance retrieval =====

  /// Retrieve top-K memories relevant to [query].
  Future<List<MemoryEntry>> retrieveRelevant(String query, {int topK = 10}) async {
    if (!_loaded) await load();
    return _retriever.retrieve(
      query: query,
      activeMemories: _allActive,
      topK: topK,
    );
  }

  // ===== System prompt =====

  /// Build memory section for system prompt, filtered by relevance to [query].
  /// Memories are grouped by category for readability.
  String toSystemPrompt([String query = '']) {
    if (_allActive.isEmpty) return '';

    List<MemoryEntry> relevant;
    if (query.isNotEmpty) {
      // Synchronous scoring — keyword match + recency only (no FTS await)
      final tokens = MemoryRetriever.tokenize(query);
      final scored = <({MemoryEntry entry, double score})>[];
      for (final mem in _allActive) {
        double kw = 0;
        for (final t in tokens) {
          if (mem.content.toLowerCase().contains(t)) kw++;
        }
        double ent = 0;
        for (final t in tokens) {
          for (final e in mem.entities) {
            if (e.toLowerCase().contains(t) || t.contains(e.toLowerCase())) {
              ent++;
              break;
            }
          }
        }
        final days = DateTime.now().difference(mem.createdAt).inDays;
        final recency = 1.0 / (1.0 + days / 30.0);
        final confW = mem.confidence == 'manual'
            ? 1.0
            : mem.confidence == 'high'
                ? 0.8
                : mem.confidence == 'medium'
                    ? 0.5
                    : 0.3;
        final score = kw * 2.0 + ent * 3.0 + recency + confW;
        if (score > 0) scored.add((entry: mem, score: score));
      }
      scored.sort((a, b) => b.score.compareTo(a.score));
      relevant = scored.take(10).map((s) => s.entry).toList();
    } else {
      // No query: most recent 30, grouped by category
      final sorted = List<MemoryEntry>.from(_allActive)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      relevant = sorted.take(30).toList();
    }

    if (relevant.isEmpty) return '';

    // Group by category
    final grouped = _groupByCategory(relevant);

    final buf = StringBuffer();
    buf.writeln('【用户记忆】');

    // Preset category sections (ordered)
    _writeSection(buf, '静态画像', grouped['static'], prefix: '  - ');
    _writeSection(buf, '动态画像', grouped['dynamic'], prefix: '  - ');
    _writeSection(buf, '交互偏好', grouped['preference'], prefix: '  - ');
    _writeSection(buf, '注意事项', grouped['notice'], prefix: '  - ');

    // Open-category sections
    _writeSection(buf, '兴趣爱好', grouped['interest'], prefix: '  - ');
    _writeSection(buf, '个人事实', grouped['fact'], prefix: '  - ');
    _writeSection(buf, '经历事件', grouped['experience'], prefix: '  - ');
    _writeSection(buf, '人际关系', grouped['relationship'], prefix: '  - ');
    _writeSection(buf, '健康养生', grouped['health'], prefix: '  - ');
    _writeSection(buf, '职业工作', grouped['professional'], prefix: '  - ');
    _writeSection(buf, '计划目标', grouped['plan'], prefix: '  - ');

    // Catch-all: episodes and uncategorized
    _writeFlatSection(buf, grouped['episodic']);
    _writeFlatSection(buf, grouped['procedural']);

    return buf.toString();
  }

  /// Group memories by category.
  Map<String, List<MemoryEntry>> _groupByCategory(List<MemoryEntry> entries) {
    final map = <String, List<MemoryEntry>>{};
    for (final m in entries) {
      map.putIfAbsent(m.category, () => []).add(m);
    }
    return map;
  }

  void _writeSection(StringBuffer buf, String title, List<MemoryEntry>? entries, {String prefix = '  - '}) {
    if (entries == null || entries.isEmpty) return;
    buf.writeln('$title:');
    for (final m in entries) {
      buf.writeln('$prefix${m.content}');
    }
  }

  void _writeFlatSection(StringBuffer buf, List<MemoryEntry>? entries) {
    if (entries == null || entries.isEmpty) return;
    for (final m in entries) {
      buf.writeln('- ${m.toSystemPromptLine()}');
    }
  }

  // ===== O(1) lookup (backward compat) =====

  String? get(String type, String key) {
    return _byCategoryKey['$type:$key']?.content;
  }

  Map<String, String> getByType(String type) {
    final result = <String, String>{};
    for (final m in _allActive) {
      if (m.category == type && m.key != null) {
        result[m.key!] = m.content;
      }
    }
    return result;
  }

  // ===== Pending entries =====

  List<PendingEntry> getPending() {
    return _pendingList
        .map((e) => PendingEntry(
              type: e.category,
              key: e.key ?? '',
              value: e.content,
              confidence: e.confidence,
              source: e.source,
              sourceDetail: e.sourceDetail,
              createdAt: e.createdAt,
            ))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> confirm(String type, String key) async {
    final entry = _byCategoryKey['$type:$key'];
    if (entry == null) return;
    _pendingList.removeWhere((e) => e.id == entry.id);
    // Already active — just notify
    _notifyChange();
  }

  Future<void> reject(String type, String key) async {
    final entry = _byCategoryKey['$type:$key'];
    if (entry == null) return;
    await _db.deleteMemory(entry.id);
    _allActive.remove(entry);
    _byId.remove(entry.id);
    _byCategoryKey.remove('$type:$key');
    _pendingList.removeWhere((e) => e.id == entry.id);
    _notifyChange();
  }

  // ===== Write (backward compat) =====

  Future<void> set(String type, String key, String value, {
    String confidence = 'manual',
    String source = 'manual',
    bool confirmed = true,
  }) async {
    await addMemory(
      content: value,
      memoryType: MemoryType.semantic,
      category: type,
      key: key,
      confidence: confidence,
      source: source,
    );
  }

  Future<void> setPending(String type, String key, String value, {
    String confidence = 'medium',
    String source = 'ai',
    String sourceDetail = '',
  }) async {
    // Don't overwrite confirmed
    if (_byCategoryKey.containsKey('$type:$key')) return;

    // Check if already in pending
    for (final e in _pendingList) {
      if (e.category == type && e.key == key) return;
    }

    final id = _genId();
    final entry = MemoryEntry(
      id: id,
      memoryType: MemoryType.semantic,
      content: value,
      contentHash: ContentHasher.hash(value),
      category: type,
      key: key,
      entities: EntityExtractor.extract(value),
      confidence: confidence,
      source: source,
      sourceDetail: sourceDetail,
      status: MemoryStatus.active,
      createdAt: DateTime.now(),
    );
    await _db.insertMemory(entry.toDb());
    _allActive.add(entry);
    _byId[id] = entry;
    if (key.isNotEmpty) {
      _byCategoryKey['$type:$key'] = entry;
    }
    _pendingList.add(entry);
  }

  Future<void> remove(String type, String key) async {
    final entry = _byCategoryKey.remove('$type:$key');
    if (entry != null) {
      await _db.deleteMemory(entry.id);
      _allActive.remove(entry);
      _byId.remove(entry.id);
      _pendingList.removeWhere((e) => e.id == entry.id);
    }
    _notifyChange();
  }

  /// 把 [targetId] 标记 superseded_by [newId]（用于 consolidation 合并）。
  Future<void> supersedeMemory(String targetId, String? newId) async {
    final entry = _byId[targetId];
    if (entry == null) return;

    await _db.updateMemory(targetId, {
      'status': 'superseded',
      'superseded_by': newId,
    });

    // Update in-memory
    final updated = MemoryEntry(
      id: entry.id,
      memoryType: entry.memoryType,
      content: entry.content,
      contentHash: entry.contentHash,
      category: entry.category,
      key: entry.key,
      entities: entry.entities,
      linkedMemoryIds: entry.linkedMemoryIds,
      confidence: entry.confidence,
      source: entry.source,
      sourceDetail: entry.sourceDetail,
      status: MemoryStatus.superseded,
      supersededBy: newId,
      embedding: entry.embedding,
      embeddingSource: entry.embeddingSource,
      createdAt: entry.createdAt,
      updatedAt: DateTime.now(),
    );
    final idx = _allActive.indexWhere((m) => m.id == targetId);
    if (idx >= 0) _allActive[idx] = updated;
    _byId[targetId] = updated;
    _notifyChange();
  }

  /// 降级记忆置信度。
  Future<void> downgradeConfidence(String id, String newConfidence) async {
    final entry = _byId[id];
    if (entry == null) return;

    await _db.updateMemory(id, {'confidence': newConfidence});

    final updated = MemoryEntry(
      id: entry.id,
      memoryType: entry.memoryType,
      content: entry.content,
      contentHash: entry.contentHash,
      category: entry.category,
      key: entry.key,
      entities: entry.entities,
      linkedMemoryIds: entry.linkedMemoryIds,
      confidence: newConfidence,
      source: entry.source,
      sourceDetail: entry.sourceDetail,
      status: entry.status,
      supersededBy: entry.supersededBy,
      embedding: entry.embedding,
      embeddingSource: entry.embeddingSource,
      createdAt: entry.createdAt,
      updatedAt: DateTime.now(),
    );
    final idx = _allActive.indexWhere((m) => m.id == id);
    if (idx >= 0) _allActive[idx] = updated;
    _byId[id] = updated;
    _notifyChange();
  }

  // ===== Import =====

  Future<void> importFromJson(Map<String, dynamic> json) async {
    void add(String type, String key, String value) {
      if (value.isEmpty) return;
      set(type, key, value);
    }

    add('static', 'birthday', json['birthday'] as String? ?? '');
    add('static', 'gender', json['gender'] as String? ?? '');
    add('static', 'nativeLanguage', json['nativeLanguage'] as String? ?? '');
    add('dynamic', 'knowledgeBackground', json['knowledgeBackground'] as String? ?? '');
    add('dynamic', 'currentIdentity', json['currentIdentity'] as String? ?? '');
    add('dynamic', 'location', json['location'] as String? ?? '');
    add('dynamic', 'usingLanguage', json['usingLanguage'] as String? ?? '');
    add('dynamic', 'shortTermGoals', json['shortTermGoals'] as String? ?? '');
    add('dynamic', 'shortTermInterests', json['shortTermInterests'] as String? ?? '');
    add('dynamic', 'behaviorHabits', json['behaviorHabits'] as String? ?? '');
    add('dynamic', 'agentName', json['agentName'] as String? ?? '');
    add('dynamic', 'namePreference', json['namePreference'] as String? ?? '');
    add('dynamic', 'userTitle', json['userTitle'] as String? ?? '');
    add('preference', 'answerStyle', json['answerStyle'] as String? ?? '');
    add('preference', 'detailLevel', json['detailLevel'] as String? ?? '');
    add('preference', 'formatPreference', json['formatPreference'] as String? ?? '');
    add('preference', 'visualPreference', json['visualPreference'] as String? ?? '');
    add('notice', 'communicationRules', json['communicationRules'] as String? ?? '');
    add('notice', 'prohibitedItems', json['prohibitedItems'] as String? ?? '');
    add('notice', 'otherRequirements', json['otherRequirements'] as String? ?? '');

    final tasks = json['tasks'] as List<dynamic>? ?? [];
    for (final t in tasks) {
      final tm = t as Map<String, dynamic>;
      final taskId = tm['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString();
      final taskRow = <String, dynamic>{
        'id': taskId,
        'title': tm['title'] ?? '',
        'description': tm['description'] ?? '',
        'task_type': tm['taskType'] ?? 'scheduled',
        'interval_seconds': tm['intervalSeconds'] ?? 0,
        'due_time': tm['dueDate'] != null
            ? DateTime.tryParse(tm['dueDate'] as String)?.millisecondsSinceEpoch
            : null,
        'status': tm['status'] ?? 'pending',
        'created_at': tm['createdAt'] != null
            ? DateTime.tryParse(tm['createdAt'] as String)?.millisecondsSinceEpoch ??
                DateTime.now().millisecondsSinceEpoch
            : DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'is_active': 1,
      };
      _tasks[taskId] = taskRow;
      await _db.insertTask(taskRow);
    }
  }

  // ===== Tasks =====

  List<Map<String, dynamic>> getTasks({String? status, DateTime? before}) {
    return _tasks.values.where((t) {
      if (status != null && t['status'] != status) return false;
      if (before != null) {
        final due = t['due_time'] as int?;
        if (due != null &&
            DateTime.fromMillisecondsSinceEpoch(due).isAfter(before)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Map<String, dynamic>? getTask(String id) => _tasks[id];

  Future<void> addTask(Map<String, dynamic> taskRow) async {
    _tasks[taskRow['id'] as String] = taskRow;
    await _db.insertTask(taskRow);
    _notifyChange();
  }

  Future<void> updateTask(Map<String, dynamic> taskRow) async {
    final id = taskRow['id'] as String;
    _tasks[id] = taskRow;
    await _db.updateTask(id, taskRow);
    _notifyChange();
  }

  Future<void> deleteTask(String taskId) async {
    _tasks.remove(taskId);
    await _db.deleteTask(taskId);
    _notifyChange();
  }

  Future<void> expireOverdueTasks() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in _tasks.entries) {
      final t = entry.value;
      if (t['status'] == 'pending' &&
          t['due_time'] != null &&
          (t['due_time'] as int) < now) {
        final updated = Map<String, dynamic>.from(t);
        updated['status'] = 'expired';
        _tasks[entry.key] = updated;
        await _db.updateTask(entry.key, {'status': 'expired'});
      }
    }
  }

  // ===== Migration =====

  Future<void> migrateFromJson(String jsonStr) async {
    if (jsonStr.isEmpty) return;
    try {
      await importFromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {}
  }
}
