import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Tool-call signature for loop detection.
/// Tracks what was called, with what args, and what the result looked like.
class _ToolCallSignature {

  const _ToolCallSignature({
    required this.name,
    required this.argsHash,
    this.resultHash,
  });
  final String name;
  final String argsHash;
  final String? resultHash;

  @override
  bool operator ==(Object other) =>
      other is _ToolCallSignature &&
      other.name == name &&
      other.argsHash == argsHash &&
      other.resultHash == resultHash;

  @override
  int get hashCode => Object.hash(name, argsHash, resultHash);
}

/// Detects when the agent is stuck in a tool-calling loop.
///
/// Two detection modes:
/// 1. Identical consecutive calls — same tool + same args + same result N+ times
/// 2. Repeating sequences — e.g. [A, B, A, B, A, B]
///
/// Args are JSON-normalised (sorted keys, compact) before hashing so that
/// semantically-identical calls produce the same signature regardless of key
/// order or whitespace.
///
/// When a loop is detected, a soft corrective nudge message is returned.
/// The caller should inject it into the LLM context rather than hard-aborting.
class ToolLoopDetector {

  ToolLoopDetector({int windowSize = 30}) : _windowSize = windowSize;
  final int _windowSize;
  final List<_ToolCallSignature> _signatures = [];

  /// Record a completed tool call (name + args + result).
  /// Call this AFTER the tool result is available.
  void record(String name, Map<String, dynamic> args, String? result) {
    _signatures.add(_ToolCallSignature(
      name: name,
      argsHash: _hashArgs(args),
      resultHash: result != null ? _hashString(result) : null,
    ));
    if (_signatures.length > _windowSize) {
      _signatures.removeAt(0);
    }
  }

  /// Returns a corrective nudge message if a loop is detected, or null.
  String? check() {
    // ── Identical consecutive calls ──
    final toolName = _detectIdenticalConsecutive(threshold: 5);
    if (toolName != null) {
      return "[SYSTEM: REPETITION GUARD] You have called '$toolName' with the same "
          'arguments multiple times in a row, getting the same result each time. '
          'STOP repeating this approach — it is not working. '
          'Step back and try a fundamentally different strategy. '
          'Consider: using a different tool, changing your arguments significantly, '
          "or explaining to the user what you're stuck on and asking for guidance.";
    }

    // ── Repeating sequence ──
    final pattern = _detectRepeatingSequence();
    if (pattern != null) {
      final desc = pattern.map((s) => s.name).join(' → ');
      return '[SYSTEM: REPETITION GUARD] You are stuck in a repeating cycle: '
          '[$desc]. This pattern has repeated without progress. '
          'STOP this cycle and try a fundamentally different approach. '
          'Consider: breaking down the problem differently, using alternative tools, '
          "or explaining to the user what you're stuck on.";
    }

    return null;
  }

  /// Returns true if the tail streak is so severe that the session should be
  /// hard-stopped (last resort). Only cares about the most recent calls.
  bool get isSeverelyLooping {
    return _tailConsecutiveSame() >= 8;
  }

  void reset() => _signatures.clear();

  // ─── private ───

  String? _detectIdenticalConsecutive({int threshold = 3}) {
    if (_signatures.length < threshold) return null;
    int count = 1;
    for (int i = _signatures.length - 1; i > 0; i--) {
      if (_signatures[i] == _signatures[i - 1]) {
        count++;
        if (count >= threshold) return _signatures[i].name;
      } else {
        count = 1;
      }
    }
    return null;
  }

  List<_ToolCallSignature>? _detectRepeatingSequence() {
    final n = _signatures.length;
    for (int seqLen = 2; seqLen <= 5; seqLen++) {
      final minRequired = seqLen * 2;
      if (n < minRequired) continue;
      final tail = _signatures.sublist(n - minRequired);
      final pattern = tail.sublist(0, seqLen);
      int reps = 0;
      for (int start = n - seqLen; start >= 0; start -= seqLen) {
        final end = start + seqLen > n ? n : start + seqLen;
        if (end - start != seqLen) break;
        if (_listEqual(_signatures.sublist(start, end), pattern)) {
          reps++;
        } else {
          break;
        }
      }
      if (reps >= 2) return pattern;
    }
    return null;
  }

  int _tailConsecutiveSame() {
    if (_signatures.isEmpty) return 0;
    int count = 1;
    for (int i = _signatures.length - 1; i > 0; i--) {
      if (_signatures[i] == _signatures[i - 1]) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  bool _listEqual(List<_ToolCallSignature> a, List<_ToolCallSignature> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _hashArgs(Map<String, dynamic> args) {
    return _hashString(jsonEncode(_normalizeJson(args)));
  }

  static String _hashString(String s) {
    if (s.isEmpty) return '';
    return sha256.convert(utf8.encode(s)).toString().substring(0, 12);
  }

  /// Recursively sort JSON keys so semantically-identical objects hash the same.
  static dynamic _normalizeJson(dynamic value) {
    if (value is Map<String, dynamic>) {
      final sorted = <String, dynamic>{};
      for (final k in (value.keys.toList()..sort())) {
        sorted[k] = _normalizeJson(value[k]);
      }
      return sorted;
    }
    if (value is List) {
      return value.map(_normalizeJson).toList();
    }
    return value;
  }
}
