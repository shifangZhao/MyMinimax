/// Relevance-based memory retrieval with multi-signal scoring.
///
/// Five signals:
/// - Keyword token match (primary for Chinese)
/// - Entity exact match
/// - FTS5 full-text match (supplementary, English-effective)
/// - Embedding cosine similarity (semantic, requires [embedder])
/// - Recency decay
///
/// Designed for mobile scale (tens to low-hundreds of memories).
library;

import '../../../core/storage/database_helper.dart';
import 'memory_embedder.dart';
import 'memory_entry.dart';

class MemoryRetriever {

  MemoryRetriever(this._db, {this.embedder});
  final DatabaseHelper _db;
  MemoryEmbedder? embedder;

  /// Retrieve top-K memories relevant to [query].
  Future<List<MemoryEntry>> retrieve({
    required String query,
    required List<MemoryEntry> activeMemories,
    int topK = 10,
    MemoryType? filterType,
    String? filterCategory,
  }) async {
    if (query.isEmpty || activeMemories.isEmpty) {
      // No query: return most recent
      final sorted = List<MemoryEntry>.from(
        filterType != null
            ? activeMemories.where((m) => m.memoryType == filterType).toList()
            : activeMemories,
      )..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return sorted.take(topK).toList();
    }

    // 1. Tokenize query
    final tokens = tokenize(query);
    if (tokens.isEmpty) return activeMemories.take(topK).toList();

    // 2. FTS5 search (supplementary signal)
    final Set<String> ftsHitIds = await _ftsSearch(query);

    // 3. Embedding vector for query (if embedder available)
    List<double>? queryEmbedding;
    if (embedder != null) {
      try {
        queryEmbedding = await embedder!.embed(query, type: 'query');
      } catch (_) {
        // Embedding unavailable — skip vector signal
      }
    }

    // 4. Score every active memory
    final scored = <_ScoredEntry>[];
    for (final mem in activeMemories) {
      if (filterType != null && mem.memoryType != filterType) continue;
      if (filterCategory != null && mem.category != filterCategory) continue;

      final keywordHits = _countKeywordHits(tokens, mem);
      final entityHits = _countEntityHits(tokens, mem);
      final ftsHit = ftsHitIds.contains(mem.id) ? 1.0 : 0.0;
      final recency = _recencyBoost(mem.createdAt);
      final confidenceW = _confidenceWeight(mem.confidence);
      final linkBoost = mem.linkedMemoryIds.isNotEmpty ? 1.0 : 0.0;

      // Embedding score: use cached embedding or skip
      double embedScore = 0.0;
      if (queryEmbedding != null && mem.embedding != null && mem.embedding!.length == queryEmbedding.length) {
        embedScore = MemoryEmbedder.cosineSimilarity(queryEmbedding!, mem.embedding!);
      }

      final score = keywordHits * 2.0 +
          entityHits * 3.0 +
          ftsHit * 1.5 +
          embedScore * 4.0 +
          recency +
          confidenceW +
          linkBoost;

      if (score > 0) {
        scored.add(_ScoredEntry(mem, score));
      }
    }

    // 4. Sort by score DESC, take topK
    scored.sort((a, b) => b.score.compareTo(a.score));

    // 5. Expand: include linked memories of top results
    final resultIds = <String>{};
    final result = <MemoryEntry>[];
    for (final se in scored.take(topK)) {
      if (resultIds.add(se.entry.id)) {
        result.add(se.entry);
      }
      // Pull in linked memories
      for (final linkedId in se.entry.linkedMemoryIds) {
        if (resultIds.contains(linkedId)) continue;
        final linked = _byId(linkedId, activeMemories);
        if (linked != null && resultIds.add(linked.id)) {
          result.add(linked);
        }
      }
    }

    return result.take(topK).toList();
  }

  // ---- private ----

  MemoryEntry? _byId(String id, List<MemoryEntry> pool) {
    try {
      return pool.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  int _countKeywordHits(List<String> tokens, MemoryEntry mem) {
    final content = mem.content.toLowerCase();
    int hits = 0;
    for (final t in tokens) {
      if (content.contains(t)) hits++;
    }
    return hits;
  }

  int _countEntityHits(List<String> tokens, MemoryEntry mem) {
    int hits = 0;
    for (final t in tokens) {
      for (final e in mem.entities) {
        if (e.toLowerCase().contains(t) || t.contains(e.toLowerCase())) {
          hits++;
          break;
        }
      }
    }
    return hits;
  }

  double _recencyBoost(DateTime createdAt) {
    final days = DateTime.now().difference(createdAt).inDays;
    return 1.0 / (1.0 + days / 30.0);
  }

  double _confidenceWeight(String confidence) {
    switch (confidence) {
      case 'manual':
        return 1.0;
      case 'high':
        return 0.8;
      case 'medium':
        return 0.5;
      case 'low':
        return 0.3;
      default:
        return 0.5;
    }
  }

  Future<Set<String>> _ftsSearch(String query) async {
    try {
      final rows = await _db.searchMemoriesFts(query);
      return rows.map((r) => r['id'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Tokenize for Chinese + English mixed text.
  static List<String> tokenize(String text) {
    final tokens = <String>[];

    // English words
    final wordRe = RegExp(r'[a-zA-Z0-9]{2,}');
    for (final m in wordRe.allMatches(text)) {
      tokens.add(m.group(0)!.toLowerCase());
    }

    // Chinese CJK characters — unigrams + bigrams
    final cjk = RegExp(r'[一-鿿㐀-䶿]+')
        .allMatches(text)
        .map((m) => m.group(0)!)
        .join();
    if (cjk.isNotEmpty) {
      for (var i = 0; i < cjk.length; i++) {
        tokens.add(cjk[i]);
      }
      for (var i = 0; i < cjk.length - 1; i++) {
        tokens.add(cjk.substring(i, i + 2));
      }
    }

    return tokens;
  }
}

class _ScoredEntry {
  _ScoredEntry(this.entry, this.score);
  final MemoryEntry entry;
  final double score;
}
