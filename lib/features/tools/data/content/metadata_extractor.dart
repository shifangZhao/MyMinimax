// ignore_for_file: avoid_dynamic_calls

/// Metadata extraction ported from @steipete/summarize-core.
///
/// Source: packages/core/src/content/link-preview/content/parsers.ts
library;

import 'package:html/parser.dart' show parse;

import '../../../../shared/utils/text_cleaner.dart' show decodeHtmlEntities, normalizeCandidate;

class ParsedMetadata {

  const ParsedMetadata({
    this.title,
    this.description,
    this.siteName,
    this.publishedDate,
    this.author,
  });
  final String? title;
  final String? description;
  final String? siteName;
  final String? publishedDate;
  final String? author;
}

ParsedMetadata extractMetadataFromHtml(String html, String url) {
  final document = parse(html);

  final title = _pickFirstText([
    _pickMetaContent(document, [
      ('property', 'og:title'),
      ('name', 'og:title'),
      ('name', 'twitter:title'),
    ]),
    _extractTagText(document, 'title'),
  ]);

  final description = _pickFirstText([
    _pickMetaContent(document, [
      ('property', 'og:description'),
      ('name', 'description'),
      ('name', 'twitter:description'),
    ]),
  ]);

  final siteName = _pickFirstText([
    _pickMetaContent(document, [
      ('property', 'og:site_name'),
      ('name', 'application-name'),
    ]),
    _safeHostname(url),
  ]);

  // Extract published date from meta tags
  final publishedDate = _pickFirstText([
    _pickMetaContent(document, [
      ('property', 'article:published_time'),
      ('name', 'article:published_time'),
      ('property', 'og:updated_time'),
      ('name', 'date'),
      ('name', 'pubdate'),
      ('name', 'publish_date'),
    ]),
    _extractTimeTag(document),
  ]);

  // Extract author from meta tags
  final author = _pickFirstText([
    _pickMetaContent(document, [
      ('property', 'article:author'),
      ('name', 'author'),
      ('name', 'article:author'),
    ]),
  ]);

  return ParsedMetadata(
    title: title,
    description: description,
    siteName: siteName,
    publishedDate: publishedDate,
    author: author,
  );
}

String? _extractTimeTag(dynamic document) {
  final timeElement = document.querySelector('time[datetime]');
  if (timeElement != null) {
    return normalizeCandidate(timeElement.attributes['datetime']);
  }
  return null;
}

String? _pickFirstText(List<String?> candidates) {
  for (final candidate in candidates) {
    if (candidate != null && candidate.isNotEmpty) return candidate;
  }
  return null;
}

String? _pickMetaContent(
  dynamic document,
  List<(String, String)> selectors,
) {
  for (final (attr, value) in selectors) {
    final element = document.querySelector('meta[$attr="$value"]');
    if (element == null) continue;
    final content = element.attributes['content'] ?? element.attributes['value'] ?? '';
    final normalized = normalizeCandidate(decodeHtmlEntities(content));
    if (normalized != null) return normalized;
  }
  return null;
}

String? _extractTagText(dynamic document, String tagName) {
  final normalizedTag = tagName.trim().toLowerCase();
  if (normalizedTag != 'title') return null;

  final element = document.querySelector(normalizedTag);
  if (element == null) return null;

  final text = decodeHtmlEntities(element.text);
  return normalizeCandidate(text);
}

String? _safeHostname(String url) {
  try {
    final host = Uri.parse(url).host;
    final stripped = host.replaceFirst(RegExp(r'^www\.'), '');
    return stripped.isNotEmpty ? stripped : null;
  } catch (_) {
    return null;
  }
}
