/// Token budget controller for memory injection into system prompts.
///
/// Ensures memory text stays within a configurable token budget by
/// selecting the highest-priority memories when the budget is tight.
library;

import 'memory_entry.dart';

class MemoryBudgetController {
  MemoryBudgetController({this.maxMemoryTokens = 3000});

  final int maxMemoryTokens;

  /// Rough token estimate: ~1 token per CJK char, ~1 token per 2 ASCII chars.
  static int estimateTokens(String text) {
    int count = 0;
    for (final char in text.runes) {
      if (char >= 0x4E00 && char <= 0x9FFF) {
        count += 1;
      } else if (char <= 0x7F) {
        count += 1;
      } else {
        count += 2;
      }
    }
    return (count / 1.5).ceil();
  }

  /// Select memories within [maxMemoryTokens] budget, prioritizing by
  /// confidence, recency, and link count.
  List<MemoryEntry> select(List<MemoryEntry> candidates) {
    if (candidates.isEmpty || _totalEstimate(candidates) <= maxMemoryTokens) {
      return candidates;
    }

    final scored = candidates.map((m) {
      double priority = 0;

      switch (m.confidence) {
        case 'manual':
          priority += 100;
        case 'high':
          priority += 80;
        case 'medium':
          priority += 50;
        case 'low':
          priority += 30;
      }

      final days = DateTime.now().difference(m.createdAt).inDays;
      priority += 50 / (1 + days / 30.0);
      priority += m.linkedMemoryIds.length * 10.0;

      return (entry: m, priority: priority);
    }).toList();

    scored.sort((a, b) => b.priority.compareTo(a.priority));

    final result = <MemoryEntry>[];
    int used = 10; // header overhead

    for (final s in scored) {
      final line = s.entry.toSystemPromptLine();
      final cost = estimateTokens(line) + 5; // + formatting overhead
      if (used + cost > maxMemoryTokens) break;
      result.add(s.entry);
      used += cost;
    }

    return result;
  }

  int _totalEstimate(List<MemoryEntry> entries) {
    int total = 10; // header
    for (final m in entries) {
      total += estimateTokens(m.toSystemPromptLine()) + 5;
    }
    return total;
  }
}
