/// YouTube description extraction ported from @steipete/summarize-core.
///
/// Source: packages/core/src/content/link-preview/content/youtube.ts
library;

import 'dart:convert';

import '../../../../shared/utils/text_cleaner.dart' show normalizeWhitespace;

String? extractYouTubeShortDescription(String html) {
  final tokenIndex = html.indexOf('ytInitialPlayerResponse');
  if (tokenIndex < 0) return null;

  final assignmentIndex = html.indexOf('=', tokenIndex);
  if (assignmentIndex < 0) return null;

  final objectText = _extractBalancedJsonObject(html, assignmentIndex);
  if (objectText == null) return null;

  try {
    final parsed = jsonDecode(objectText);
    if (parsed is! Map<String, dynamic>) return null;

    final videoDetails = parsed['videoDetails'];
    if (videoDetails is! Map<String, dynamic>) return null;

    final description = videoDetails['shortDescription'];
    if (description is! String) return null;

    final normalized = normalizeWhitespace(description);
    return normalized.isNotEmpty ? normalized : null;
  } catch (_) {
    return null;
  }
}

String? _extractBalancedJsonObject(String source, int startAt) {
  final start = source.indexOf('{', startAt);
  if (start < 0) return null;

  var depth = 0;
  var inString = false;
  String? quote;
  var escaping = false;

  for (var i = start; i < source.length; i++) {
    final ch = source[i];

    if (inString) {
      if (escaping) {
        escaping = false;
        continue;
      }
      if (ch == '\\') {
        escaping = true;
        continue;
      }
      if (ch == quote) {
        inString = false;
        quote = null;
      }
      continue;
    }

    if (ch == '"' || ch == "'") {
      inString = true;
      quote = ch;
      continue;
    }

    if (ch == '{') {
      depth += 1;
      continue;
    }
    if (ch == '}') {
      depth -= 1;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }

  return null;
}
