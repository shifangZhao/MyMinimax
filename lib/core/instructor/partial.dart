/// Streaming partial object accumulator.
///
/// Fields start as null and fill in progressively as the LLM streams
/// JSON for a forced tool_use. Callers yield a new [Partial] each time
/// a field is updated so the UI can render the object being built.
library;

import 'dart:convert';

/// A partial structured object during streaming extraction.
class Partial<T> {

  Partial._(this._fields);

  /// Start with an empty partial.
  factory Partial.empty() => Partial._({});
  final Map<String, dynamic> _fields;

  /// Access a field value by name. Returns null if not yet extracted.
  R? get<R>(String fieldName) => _fields[fieldName] as R?;

  /// The raw accumulated fields so far.
  Map<String, dynamic> get rawFields => Map.unmodifiable(_fields);

  /// Number of non-null fields extracted so far.
  int get filledCount => _fields.values.where((v) => v != null).length;

  /// Whether any fields have been filled.
  bool get hasAnyField => filledCount > 0;

  /// Whether all required fields are present and non-null.
  bool isComplete(List<String> requiredFields) {
    for (final field in requiredFields) {
      if (!_fields.containsKey(field) || _fields[field] == null) return false;
    }
    return true;
  }

  /// Try to build the final T using [fromJson].
  /// Returns null if required fields are missing.
  T? tryBuild(
    dynamic Function(Map<String, dynamic>) fromJson,
    List<String> requiredFields,
  ) {
    if (!isComplete(requiredFields)) return null;
    try {
      return fromJson(Map<String, dynamic>.from(_fields)) as T;
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'Partial($_fields)';
}

/// Accumulates streaming JSON fragments into Partial objects.
class PartialAccumulator<T> {

  PartialAccumulator();
  Partial<T> _current = Partial.empty();
  String _buffer = '';

  Partial<T> get current => _current;

  /// Feed a JSON fragment and return an updated Partial if anything changed.
  Partial<T>? feed(String jsonFragment) {
    _buffer += jsonFragment;

    // Attempt incremental parse: try to decode what we have so far.
    // If the JSON is incomplete, try patching it.
    Map<String, dynamic>? parsed = _tryDecodePartial(_buffer);

    if (parsed != null) {
      final newFields = <String, dynamic>{};
      for (final entry in parsed.entries) {
        if (_current._fields[entry.key] != entry.value) {
          newFields[entry.key] = entry.value;
        }
      }
      if (newFields.isNotEmpty) {
        _current = Partial._({..._current._fields, ...newFields});
        return _current;
      }
    }

    return null;
  }

  /// Try to decode a potentially-incomplete JSON object.
  ///
  /// Uses stack-based repair: tracks open strings, objects, and arrays
  /// to compute the minimal closing suffix instead of guessing a fixed
  /// set of suffixes. Handles nested objects, arrays, and trailing
  /// commas correctly.
  Map<String, dynamic>? _tryDecodePartial(String raw) {
    // 1. Direct parse — most common case, no repair needed.
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {}

    // 2. Stack-based repair.
    final repairs = _computeRepairs(raw);
    for (final candidate in repairs) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return null;
  }

  /// Walk [raw] to determine what's open (strings, braces, brackets)
  /// and return candidate repaired strings to try.
  List<String> _computeRepairs(String raw) {
    final stack = <String>[];
    bool inString = false;

    for (int i = 0; i < raw.length; i++) {
      final ch = raw[i];

      // Handle escape sequences inside strings
      if (ch == '\\' && inString) {
        i++; // skip the escaped character
        continue;
      }

      if (ch == '"') {
        inString = !inString;
        continue;
      }

      if (inString) continue;

      if (ch == '{') {
        stack.add('}');
      } else if (ch == '[') {
        stack.add(']');
      } else if (ch == '}' || ch == ']') {
        if (stack.isNotEmpty && stack.last == ch) {
          stack.removeLast();
        }
      }
    }

    // Build closing suffix
    final suffix = StringBuffer();
    if (inString) suffix.write('"');
    for (int i = stack.length - 1; i >= 0; i--) {
      suffix.write(stack[i]);
    }
    final closing = suffix.toString();

    final candidates = <String>[];

    // Candidate 1: raw + closing brackets
    candidates.add(raw + closing);

    // Candidate 2: strip trailing comma (e.g. {"a": 1,)
    final trimmed = raw.trimRight();
    if (trimmed.endsWith(',')) {
      candidates.add(trimmed.substring(0, trimmed.length - 1) + closing);
    }

    // Candidate 3: trailing colon → append null (e.g. {"a": )
    if (trimmed.endsWith(':')) {
      candidates.add('${raw}null$closing');
    }

    return candidates;
  }

  /// Reset for a new stream.
  void reset() {
    _current = Partial.empty();
    _buffer = '';
  }
}
