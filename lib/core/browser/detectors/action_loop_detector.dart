import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Tracks action repetition via normalized SHA-256 hashing to detect
/// behavioral loops in an agent's action sequence.
///
/// Actions are normalized before hashing so that minor parameter
/// variations don't mask genuine repetition patterns:
/// - search: sorts query tokens alphabetically
/// - click: uses element index only
/// - type/input: uses index + normalized text
/// - navigate: hashes by full URL
/// - scroll: direction + index
///
/// This is a soft detector — it generates nudge messages but never blocks.
class ActionLoopDetector {

  ActionLoopDetector({this.windowSize = 20});
  final int windowSize;
  final List<String> _recentHashes = [];

  int get maxRepetitionCount => _computeMaxRepeat();
  bool get isLooping => maxRepetitionCount >= 5;
  bool get isSeverelyLooping => maxRepetitionCount >= 8;

  /// Record an executed action.
  /// Returns true if this action contributes to a detected loop.
  bool record(String actionName, Map<String, dynamic> params) {
    // Exempt actions that can't cause loops
    if (_isExempt(actionName)) return false;

    final h = computeActionHash(actionName, params);
    _recentHashes.add(h);
    if (_recentHashes.length > windowSize) {
      _recentHashes.removeAt(0);
    }
    return isLooping;
  }

  /// Get the appropriate nudge message for the current repetition level.
  String? get nudgeMessage {
    final count = maxRepetitionCount;
    if (count >= 12) {
      return 'Same action pattern repeated $count times. You appear deeply stuck. STOP what you\'re doing and try a COMPLETELY different strategy, or call done with partial results.';
    }
    if (count >= 8) {
      return 'Same action pattern repeated $count times. Are you still making progress? Consider a radically different approach.';
    }
    if (count >= 5) {
      return 'Same action pattern repeated $count times. Consider whether a different approach would be more productive.';
    }
    return null;
  }

  void reset() {
    _recentHashes.clear();
  }

  int _computeMaxRepeat() {
    if (_recentHashes.isEmpty) return 0;
    final counts = <String, int>{};
    for (final h in _recentHashes) {
      counts[h] = (counts[h] ?? 0) + 1;
    }
    return counts.values.fold(0, (a, b) => a > b ? a : b);
  }

  bool _isExempt(String actionName) {
    const exempt = ['browser_wait', 'browser_go_back', 'browser_screenshot'];
    return exempt.contains(actionName);
  }

  /// Compute a stable hash for an action based on type + normalized params.
  static String computeActionHash(
      String actionName, Map<String, dynamic> params) {
    final normalized = _normalize(actionName, params);
    return sha256.convert(utf8.encode(normalized)).toString().substring(0, 12);
  }

  static String _normalize(String actionName, Map<String, dynamic> params) {
    switch (actionName) {
      case 'browser_search':
        final q = (params['query'] as String? ?? '').toLowerCase();
        final tokens = q
            .split(RegExp(r'[^\w]'))
            .where((t) => t.isNotEmpty)
            .toList()
          ..sort();
        return 's|${params['engine'] ?? 'ddg'}|${tokens.join('|')}';

      case 'browser_click':
        return 'c|${params['index'] ?? params['selector'] ?? ''}';

      case 'browser_type':
        final t = (params['text'] as String? ?? '').trim().toLowerCase();
        return 't|${params['index'] ?? ''}|$t';

      case 'browser_navigate':
        return 'n|${params['url'] ?? ''}';

      case 'browser_scroll':
        return 'sc|${params['direction'] ?? 'down'}|${params['index'] ?? ''}';

      case 'browser_select_dropdown':
        return 'sd|${params['index']}|${params['text'] ?? ''}';

      case 'browser_hover':
        return 'h|${params['index'] ?? ''}';

      case 'browser_press_key':
        return 'pk|${params['key'] ?? ''}';

      case 'browser_drag':
        return 'dr|${params['fromIndex']}|${params['toIndex'] ?? ''}';

      default:
        // For other actions, hash by name + sorted params
        final sorted = <String>[];
        for (final e in params.entries) {
          sorted.add('${e.key}=${e.value}');
        }
        sorted.sort();
        return '$actionName|${sorted.join('|')}';
    }
  }
}
