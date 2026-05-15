import 'dart:convert';

/// Repairs common LLM-generated JSON errors in tool-call arguments.
///
/// Applies three fixes in order: remove trailing commas,
/// balance unmatched delimiters, close unclosed strings.
/// Returns the repaired JSON string, or null if irreparable.
class JsonRepair {
  JsonRepair._();

  static String? repair(String damaged) {
    if (damaged.isEmpty) return null;

    var s = damaged.trim();
    if (_isValid(s)) return s;

    // Phase 1: Remove trailing commas — safe, semantics-preserving
    // Use lookahead so the delimiter is not consumed/replaced
    s = s.replaceAll(RegExp(r',(?=\s*[}\]])'), '');

    // Phase 2: Close unclosed string at end (do BEFORE balancing braces,
    // so that a closing brace is appended after the string's closing quote)
    s = _closeFinalString(s);

    // Phase 3: Balance unmatched {} and []
    s = _balanceDelimiters(s);

    if (_isValid(s)) return s;
    return null;
  }

  static bool _isValid(String s) {
    try { jsonDecode(s); return true; } catch (_) { return false; }
  }

  /// Track unmatched `{`/`[` in order, append missing closers in LIFO.
  static String _balanceDelimiters(String s) {
    final stack = <String>[]; // stores expected closer: '}' or ']'
    bool inString = false;

    for (int i = 0; i < s.length; i++) {
      final c = s[i];

      if (c == '\\' && inString && i + 1 < s.length) { i++; continue; }
      if (c == '"') { inString = !inString; continue; }
      if (inString) continue;

      if (c == '{') {
        stack.add('}');
      } else if (c == '[') {
        stack.add(']');
      } else if (c == '}' || c == ']') {
        if (stack.isNotEmpty && stack.last == c) {
          stack.removeLast();
        }
      }
    }

    // Append missing closers in reverse (LIFO) order
    for (int i = stack.length - 1; i >= 0; i--) {
      s += stack[i];
    }
    return s;
  }

  /// If final string is unclosed (odd number of quotes), close it.
  static String _closeFinalString(String s) {
    int count = 0;
    for (int i = 0; i < s.length; i++) {
      if (s[i] == '\\' && i + 1 < s.length) { i++; continue; }
      if (s[i] == '"') count++;
    }
    return count.isOdd ? '$s"' : s;
  }
}
