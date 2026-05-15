/// JSON-LD extraction ported from @steipete/summarize-core.
///
/// Source: packages/core/src/content/link-preview/content/jsonld.ts
library;

import 'dart:convert';

import 'package:html/parser.dart' show parse;

import '../../../../shared/utils/text_cleaner.dart' show normalizeCandidate;

class JsonLdContent {

  const JsonLdContent({this.title, this.description, this.type});
  final String? title;
  final String? description;
  final String? type;
}

JsonLdContent? extractJsonLdContent(String html) {
  try {
    final document = parse(html);
    final scripts =
        document.querySelectorAll('script[type="application/ld+json"]');
    final candidates = <JsonLdContent>[];

    for (final script in scripts) {
      final raw = script.text;
      if (raw.isEmpty) continue;
      try {
        final data = jsonDecode(raw);
        _collectCandidates(data, candidates);
      } catch (_) {
        // ignore malformed JSON-LD
      }
    }

    if (candidates.isEmpty) return null;

    final filtered = candidates
        .map((c) => JsonLdContent(
              title: normalizeCandidate(c.title),
              description: normalizeCandidate(c.description),
              type: normalizeCandidate(c.type),
            ))
        .where((c) => c.title != null || c.description != null)
        .toList()
      ..sort((a, b) =>
          (b.description?.length ?? 0).compareTo(a.description?.length ?? 0));

    return filtered.isNotEmpty ? filtered.first : null;
  } catch (_) {
    return null;
  }
}

void _collectCandidates(dynamic input, List<JsonLdContent> out) {
  if (input == null) return;

  if (input is List) {
    for (final item in input) {
      _collectCandidates(item, out);
    }
    return;
  }

  if (input is! Map<String, dynamic>) return;

  if (input.containsKey('@graph') && input['@graph'] is List) {
    _collectCandidates(input['@graph'], out);
  }

  final type = _extractType(input);
  if (type != null) {
    final title = _firstString(input, ['name', 'headline', 'title']);
    final description = _firstString(input, ['description', 'summary']);
    if (title != null || description != null) {
      out.add(JsonLdContent(title: title, description: description, type: type));
    }
  }
}

String? _extractType(Map<String, dynamic> record) {
  final raw = record['@type'];
  if (raw is String) return raw.toLowerCase();
  if (raw is List) {
    final found = raw.firstWhere(
      (e) => e is String,
      orElse: () => null,
    );
    if (found is String) return found.toLowerCase();
  }
  return null;
}

String? _firstString(Map<String, dynamic> record, List<String> keys) {
  for (final key in keys) {
    final value = record[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}
