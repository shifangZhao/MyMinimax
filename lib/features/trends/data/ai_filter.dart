import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../../../core/storage/database_helper.dart';
import '../domain/models.dart';

typedef AiCallFn = Future<String> Function(String systemPrompt, String userMessage);

class AiInterestTag {

  const AiInterestTag({required this.tag, this.id, this.description = '', this.priority = 9999});

  factory AiInterestTag.fromMap(Map<String, dynamic> m) => AiInterestTag(
    id: m['id'] as int?,
    tag: m['tag'] as String,
    description: m['description'] as String? ?? '',
    priority: m['priority'] as int? ?? 9999,
  );
  final int? id;
  final String tag;
  final String description;
  final int priority;
}

class AiClassifyResult {

  const AiClassifyResult({
    required this.news,
    required this.matchedTag,
    required this.score,
    required this.tagId,
  });
  final TrendingNews news;
  final String matchedTag;
  final double score;
  final int tagId;
}

class AiFilter {

  AiFilter({
    DatabaseHelper? db,
    this.minScore = 0.7,
    this.batchSize = 200,
    this.reclassifyThreshold = 0.6,
  }) : _db = db ?? DatabaseHelper();
  final DatabaseHelper _db;

  /// Minimum relevance score for inclusion (matching original default 0.7)
  final double minScore;

  /// Titles per LLM API call (matching original default 200)
  final int batchSize;

  /// Threshold for full re-extraction vs incremental tag update (matching original default 0.6)
  final double reclassifyThreshold;

  /// Compute MD5 hash of normalized interests content (matching Python format: filename:md5)
  String computeInterestsHash(String interests) {
    final lines = interests
        .trim()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();
    final normalized = lines.join('\n');
    final hash = md5.convert(utf8.encode(normalized)).toString();
    return 'ai_interests:$hash';
  }

  /// Phase A: Extract structured tags from natural language interests
  Future<List<AiInterestTag>> extractTags({
    required String interests,
    required AiCallFn aiCall,
  }) async {
    if (interests.trim().isEmpty) return [];

    const systemPrompt = '你是一个精准的关键词提取专家。用户会描述他感兴趣的话题领域，'
        '你需要从中提取出 5-20 个关键词标签（每个 2-6 个字），并附上简短说明。'
        '标签应该具体、可操作，能用于新闻标题匹配。'
        '返回纯 JSON 数组，格式：[{"tag": "标签名", "description": "涵盖内容说明"}]';

    final response = await aiCall(systemPrompt, '我的兴趣领域：\n$interests');
    final tags = _parseTagResponse(response);

    // Store to DB with version
    final version = DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i < tags.length; i++) {
      await _db.rawInsertAiFilterTag(
        tag: tags[i].tag,
        description: tags[i].description,
        priority: i,
        version: version,
      );
    }

    return tags;
  }

  /// Phase A': AI-driven incremental tag update (matching original update_tags)
  /// Returns null on failure (caller should fall back to full extractTags)
  Future<Map<String, dynamic>?> updateTags({
    required List<AiInterestTag> oldTags,
    required String interests,
    required AiCallFn aiCall,
  }) async {
    if (oldTags.isEmpty || interests.trim().isEmpty) return null;

    final oldTagsJson = const JsonEncoder.withIndent('  ').convert(
      oldTags.map((t) => {'tag': t.tag, 'description': t.description}).toList(),
    );

    const systemPrompt = '你是一个精准的标签管理专家。你需要对比旧的标签列表和新的用户兴趣描述，'
        '判断哪些标签需要保留、新增或删除。\n'
        '规则：\n'
        '1. 仍然相关的标签放入 keep 数组\n'
        '2. 新出现的兴趣点放入 add 数组\n'
        '3. 不再相关的标签名称放入 remove 数组\n'
        '4. change_ratio 表示变化程度（0=完全未变, 1=完全重来），约等于 (add+remove)/(keep+add+remove)\n'
        '返回纯 JSON：{"keep": [{"tag":"", "description":""}], "add": [{"tag":"", "description":""}], "remove": ["旧标签名"], "change_ratio": 0.0}';

    final userMessage = '## 旧标签列表\n$oldTagsJson\n\n## 新的兴趣描述\n$interests';

    try {
      final response = await aiCall(systemPrompt, userMessage);
      final json = _extractJson(response);
      if (json == null) return null;

      final data = jsonDecode(json) as Map<String, dynamic>;
      final keep = (data['keep'] as List?)?.whereType<Map>().map((t) => {
        'tag': (t['tag'] as String?)?.trim() ?? '',
        'description': (t['description'] as String?)?.trim() ?? '',
      }).where((t) => t['tag']!.isNotEmpty).toList() ?? [];

      final add = (data['add'] as List?)?.whereType<Map>().map((t) => {
        'tag': (t['tag'] as String?)?.trim() ?? '',
        'description': (t['description'] as String?)?.trim() ?? '',
      }).where((t) => t['tag']!.isNotEmpty).toList() ?? [];

      final remove = (data['remove'] as List?)
          ?.map((r) => (r as String).trim())
          .where((r) => r.isNotEmpty)
          .toList() ?? [];

      final ratio = (data['change_ratio'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.0;

      return {'keep': keep, 'add': add, 'remove': remove, 'change_ratio': ratio};
    } catch (e) {
      debugPrint('[AiFilter] Tag update failed: $e');
      return null;
    }
  }

  /// Smart tag extraction with hash-based change detection (matching original logic)
  Future<List<AiInterestTag>> extractOrUpdateTags({
    required String interests,
    required AiCallFn aiCall,
    String? storedHash,
  }) async {
    if (interests.trim().isEmpty) return [];

    final newHash = computeInterestsHash(interests);
    final existingTags = await _db.getActiveAiFilterTags();

    // No existing tags → full extraction
    if (existingTags.isEmpty) {
      debugPrint('[AiFilter] No existing tags, full extraction');
      return extractTags(interests: interests, aiCall: aiCall);
    }

    // Hash unchanged → reuse existing tags
    if (storedHash != null && storedHash == newHash) {
      debugPrint('[AiFilter] Interests unchanged, reusing ${existingTags.length} tags');
      return existingTags.map((m) => AiInterestTag.fromMap(m)).toList();
    }

    // Hash changed → try incremental update
    final oldTagObjects = existingTags.map((m) => AiInterestTag.fromMap(m)).toList();
    final update = await updateTags(
      oldTags: oldTagObjects,
      interests: interests,
      aiCall: aiCall,
    );

    if (update == null) {
      // Update failed → full re-extraction
      debugPrint('[AiFilter] Tag update failed, falling back to full extraction');
      return extractTags(interests: interests, aiCall: aiCall);
    }

    final changeRatio = update['change_ratio'] as double;
    final keep = update['keep'] as List<Map<String, dynamic>>;
    final add = update['add'] as List<Map<String, dynamic>>;
    final remove = update['remove'] as List<String>;

    if (changeRatio >= reclassifyThreshold) {
      debugPrint('[AiFilter] change_ratio=$changeRatio >= $reclassifyThreshold, full re-extraction');
      return extractTags(interests: interests, aiCall: aiCall);
    }

    // Incremental update
    debugPrint('[AiFilter] Incremental update: keep=${keep.length}, add=${add.length}, remove=${remove.length}');
    final version = DateTime.now().millisecondsSinceEpoch;
    final newTags = <AiInterestTag>[];
    final oldTagMap = <String, AiInterestTag>{};
    for (final t in oldTagObjects) {
      oldTagMap[t.tag] = t;
    }

    final processedTags = <String>{};
    int priority = 0;

    // Keep existing tags
    for (final k in keep) {
      final tagName = k['tag'] as String;
      final existing = oldTagMap[tagName];
      final id = await _db.upsertAiFilterTag(
        tag: tagName,
        description: k['description'] as String? ?? existing?.description ?? '',
        priority: priority,
        version: version,
        existingId: existing?.id,
      );
      newTags.add(AiInterestTag(id: id, tag: tagName, description: k['description'] as String? ?? '', priority: priority));
      processedTags.add(tagName);
      priority++;
    }

    // Add new tags
    for (final a in add) {
      final tagName = a['tag'] as String;
      if (processedTags.contains(tagName)) continue;
      final id = await _db.upsertAiFilterTag(
        tag: tagName,
        description: a['description'] as String? ?? '',
        priority: priority,
        version: version,
      );
      newTags.add(AiInterestTag(id: id, tag: tagName, description: a['description'] as String? ?? '', priority: priority));
      priority++;
    }

    // Removed tags are NOT added to new version (DB retains old version, new version excludes them)

    return newTags;
  }

  /// Phase B: Classify news titles against tags with relevance scores
  Future<List<AiClassifyResult>> classifyBatch({
    required List<TrendingNews> newsItems,
    required List<AiInterestTag> tags,
    required String interests,
    required AiCallFn aiCall,
  }) async {
    if (newsItems.isEmpty || tags.isEmpty) return [];

    // Split into batches matching original batch_size logic
    final allResults = <AiClassifyResult>[];
    for (int offset = 0; offset < newsItems.length; offset += batchSize) {
      final batch = newsItems.skip(offset).take(batchSize).toList();
      final batchResults = await _classifyOneBatch(
        newsItems: batch,
        tags: tags,
        interests: interests,
        aiCall: aiCall,
        idOffset: offset,
      );
      allResults.addAll(batchResults);
    }

    // Apply min_score filter
    final filtered = allResults.where((r) => r.score >= minScore).toList();
    filtered.sort((a, b) => b.score.compareTo(a.score));

    // Persist to DB
    final tagVersion = await _db.getLatestAiFilterTagVersion();
    if (tagVersion != null) {
      for (final r in filtered) {
        if (r.news.id != null) {
          await _db.insertAiFilterResult(
            newsItemId: r.news.id!,
            tagId: r.tagId,
            relevanceScore: r.score,
          );
        }
      }
    }

    return filtered;
  }

  Future<List<AiClassifyResult>> _classifyOneBatch({
    required List<TrendingNews> newsItems,
    required List<AiInterestTag> tags,
    required String interests,
    required AiCallFn aiCall,
    required int idOffset,
  }) async {
    final tagList = tags.asMap().entries
        .map((e) => '${e.key}: ${e.value.tag}(${e.value.description})')
        .join('\n');

    final newsList = newsItems.asMap().entries
        .map((e) => '${idOffset + e.key}: ${e.value.title}')
        .join('\n');

    const systemPrompt = '你是一个高效的新闻分类专家。根据给定的标签列表，快速判断每条新闻标题最适合哪个标签。\n'
        '分类规则：\n'
        '1. 每条新闻只归入一个最相关的标签\n'
        '2. 不匹配任何标签的新闻不要输出\n'
        '3. 给出 0.0-1.0 的相关度分数\n'
        '4. 只根据标题判断，不要过度推测\n'
        '5. 返回纯 JSON 数组：[{"id": 新闻编号, "tag_id": 标签编号, "score": 0.0-1.0}]';

    final userMessage = '## 用户偏好\n$interests\n\n'
        '## 分类标签\n$tagList\n\n'
        '## 新闻列表（共${newsItems.length}条）\n$newsList';

    final response = await aiCall(systemPrompt, userMessage);
    return _parseClassifyResponse(response, newsItems, tags, idOffset);
  }

  List<AiInterestTag> _parseTagResponse(String response) {
    try {
      final json = _extractJson(response);
      if (json == null) return [];
      final list = jsonDecode(json) as List<dynamic>;
      return list.map((item) {
        final map = item as Map<String, dynamic>;
        return AiInterestTag(
          tag: map['tag'] as String? ?? '',
          description: map['description'] as String? ?? '',
        );
      }).where((t) => t.tag.isNotEmpty).toList();
    } catch (e) {
      debugPrint('[AiFilter] Tag parse error: $e');
      return [];
    }
  }

  List<AiClassifyResult> _parseClassifyResponse(
    String response,
    List<TrendingNews> news,
    List<AiInterestTag> tags,
    int idOffset,
  ) {
    try {
      final json = _extractJson(response);
      if (json == null) return [];
      final data = jsonDecode(json);

      if (data is! List) return [];

      // Best score per news (matching original: one tag per news, highest score wins)
      final bestPerNews = <int, AiClassifyResult>{};

      for (final item in data) {
        if (item is! Map) continue;

        // Support both flat and nested JSON formats (matching original)
        final candidates = <Map<String, dynamic>>[];

        if (item.containsKey('tag_id')) {
          // Flat format: {"id": 1, "tag_id": 1, "score": 0.9}
          candidates.add({'tag_id': item['tag_id'], 'score': item['score']});
        }

        if (item.containsKey('tags')) {
          // Nested format: {"id": 1, "tags": [{"tag_id": 1, "score": 0.9}]}
          final nestedTags = item['tags'];
          if (nestedTags is List && nestedTags.isNotEmpty) {
            for (final t in nestedTags) {
              if (t is Map) {
                candidates.add({'tag_id': t['tag_id'], 'score': t['score']});
              }
            }
          }
        }

        if (candidates.isEmpty) continue;

        final rawId = item['id'];
        if (rawId is! int) continue;

        // Adjust ID by offset for batched processing
        final localId = rawId - idOffset;
        if (localId < 0 || localId >= news.length) continue;

        // Pick highest-score valid tag
        int? bestTagId;
        double bestScore = -1.0;

        for (final c in candidates) {
          final tagId = c['tag_id'] as int?;
          final score = (c['score'] as num?)?.toDouble() ?? 0.5;
          final clampedScore = score.clamp(0.0, 1.0);

          if (tagId != null && tagId >= 0 && tagId < tags.length && clampedScore > bestScore) {
            bestScore = clampedScore;
            bestTagId = tagId;
          }
        }

        if (bestTagId != null) {
          final existing = bestPerNews[localId];
          if (existing == null || bestScore > existing.score) {
            bestPerNews[localId] = AiClassifyResult(
              news: news[localId],
              matchedTag: tags[bestTagId].tag,
              score: bestScore,
              tagId: bestTagId,
            );
          }
        }
      }

      final results = bestPerNews.values.toList();
      results.sort((a, b) => b.score.compareTo(a.score));
      return results;
    } catch (e) {
      debugPrint('[AiFilter] Classify parse error: $e');
      return [];
    }
  }

  /// Get cached AI filter results for previously classified news
  Future<List<Map<String, dynamic>>> getCachedResults() async {
    final version = await _db.getLatestAiFilterTagVersion();
    if (version == null) return [];
    return _db.getAiFilterResults(tagVersion: version);
  }

  /// Compute interests hash (public alias for external use)
  String hashInterests(String interests) => computeInterestsHash(interests);

  String? _extractJson(String text) {
    final trimmed = text.trim();
    // Try to extract from markdown code block
    final codeBlock = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
    final match = codeBlock.firstMatch(trimmed);
    if (match != null) return match.group(1)!.trim();

    // Try to find first JSON array or object
    final arrayStart = trimmed.indexOf('[');
    final objStart = trimmed.indexOf('{');
    if (arrayStart >= 0 && (arrayStart < objStart || objStart < 0)) {
      final arrayEnd = trimmed.lastIndexOf(']');
      if (arrayEnd > arrayStart) return trimmed.substring(arrayStart, arrayEnd + 1);
    }
    if (objStart >= 0) {
      final objEnd = trimmed.lastIndexOf('}');
      if (objEnd > objStart) return trimmed.substring(objStart, objEnd + 1);
    }
    return null;
  }
}
