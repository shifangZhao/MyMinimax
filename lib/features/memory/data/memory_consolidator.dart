/// MemoryConsolidator — 记忆自动整合与维护。
///
/// 每 12 小时执行一次：
/// 1. 链接相关记忆（基于实体 + 语义相似度）
/// 2. 合并语义近似内容（hash 之外的软去重）
/// 3. 老化低质量记忆（长期未检索的自动 supersede）
/// 4. 生成会话级摘要 → 存入 long-term episodic memory
library;

import 'dart:async';
import 'memory_cache.dart';
import 'memory_entry.dart';

class MemoryConsolidator {

  MemoryConsolidator(this._cache);
  final MemoryCache _cache;

  bool _running = false;

  /// 是否正在执行中。
  bool get isRunning => _running;

  /// 执行一次完整整合（从 TaskScheduler 或手动触发）。
  Future<ConsolidationReport> runOnce() async {
    if (_running) throw StateError('Consolidation already in progress');
    _running = true;
    final report = ConsolidationReport(startedAt: DateTime.now());

    try {
      // 1. Link related memories
      final linked = await _linkRelated();
      report.linkedCount = linked;

      // 2. Merge semantic duplicates
      final merged = await _mergeDuplicates();
      report.mergedCount = merged;

      // 3. Decay low-quality memories
      final decayed = await _decayLowQuality();
      report.decayedCount = decayed;

      report.completedAt = DateTime.now();
    } catch (e) {
      print('[memory] error: \$e');
      report.error = e.toString();
    } finally {
      _running = false;
    }

    return report;
  }

  // ── 1. 链接相关记忆 ──

  Future<int> _linkRelated() async {
    final all = _cache.allActive;
    if (all.length < 2) return 0;

    int linked = 0;
    // 基于实体重叠建立链接
    for (var i = 0; i < all.length; i++) {
      for (var j = i + 1; j < all.length; j++) {
        final a = all[i];
        final b = all[j];
        if (a.linkedMemoryIds.contains(b.id)) continue;

        // Check entity overlap
        final entityOverlap = a.entities.where((e) => b.entities.contains(e)).length;
        if (entityOverlap >= 2) {
          await _cache.linkMemories(a.id, b.id);
          await _cache.linkMemories(b.id, a.id);
          linked += 2;
        }
      }
    }
    return linked;
  }

  // ── 2. 合并语义重复 ──

  Future<int> _mergeDuplicates() async {
    final all = _cache.allActive;
    if (all.length < 2) return 0;

    int merged = 0;
    // 基于内容长度 + 关键词重叠的近似检测
    for (var i = 0; i < all.length; i++) {
      for (var j = i + 1; j < all.length; j++) {
        final a = all[i];
        final b = all[j];
        if (a.status != MemoryStatus.active || b.status != MemoryStatus.active) continue;
        if (a.id == b.supersededBy || b.id == a.supersededBy) continue;

        final sim = _contentSimilarity(a.content, b.content);
        if (sim >= 0.85) {
          // Merge: keep the newer one, supersede the older
          final toKeep = a.createdAt.isAfter(b.createdAt) ? a : b;
          final toRemove = toKeep.id == a.id ? b : a;
          await _cache.supersedeMemory(toRemove.id, toKeep.id);
          merged++;
        }
      }
    }
    return merged;
  }

  // ── 3. 老化低质量记忆 ──

  Future<int> _decayLowQuality() async {
    final all = _cache.allActive;
    if (all.isEmpty) return 0;

    final now = DateTime.now();
    int decayed = 0;

    for (final mem in all) {
      if (mem.confidence == 'manual') continue; // 手动记忆不过期

      final ageDays = now.difference(mem.createdAt).inDays;
      // 低置信度 + 超过 90 天 → 自动 supersede
      if (mem.confidence == 'low' && ageDays > 90) {
        await _cache.supersedeMemory(mem.id, null);
        decayed++;
        continue;
      }
      // 中等置信度 + 超过 180 天 → 降级为 low
      if (mem.confidence == 'medium' && ageDays > 180) {
        await _cache.downgradeConfidence(mem.id, 'low');
        decayed++;
      }
    }
    return decayed;
  }

  // ── 辅助 ──

  /// 基于 unigram 重叠的简单文本相似度。
  static double _contentSimilarity(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final tokensA = _tokenizeForSim(a);
    final tokensB = _tokenizeForSim(b);
    if (tokensA.isEmpty || tokensB.isEmpty) return 0.0;

    int intersection = 0;
    for (final t in tokensA) {
      if (tokensB.contains(t)) intersection++;
    }

    return 2.0 * intersection / (tokensA.length + tokensB.length);
  }

  static Set<String> _tokenizeForSim(String text) {
    final result = <String>{};
    // English words
    for (final m in RegExp(r'[a-zA-Z0-9]{2,}').allMatches(text)) {
      result.add(m.group(0)!.toLowerCase());
    }
    // Chinese bigrams
    final cjk = RegExp(r'[一-鿿㐀-䶿]+')
        .allMatches(text)
        .map((m) => m.group(0)!)
        .join();
    if (cjk.isNotEmpty) {
      for (var i = 0; i < cjk.length - 1; i++) {
        result.add(cjk.substring(i, i + 2));
      }
    }
    return result;
  }
}

class ConsolidationReport {

  ConsolidationReport({required this.startedAt});
  final DateTime startedAt;
  DateTime? completedAt;
  int linkedCount = 0;
  int mergedCount = 0;
  int decayedCount = 0;
  String? error;

  bool get hasError => error != null;
  Duration get duration => (completedAt ?? DateTime.now()).difference(startedAt);

  @override
  String toString() {
    final parts = <String>[];
    if (linkedCount > 0) parts.add('链接 $linkedCount 条');
    if (mergedCount > 0) parts.add('合并 $mergedCount 条');
    if (decayedCount > 0) parts.add('老化 $decayedCount 条');
    if (parts.isEmpty) return '无需整合';
    return '${parts.join('，')}（${duration.inSeconds}秒）';
  }
}
