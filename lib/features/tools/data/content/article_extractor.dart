/// Article content extraction — improved over summarize's version.
///
/// Key improvements:
/// - Scopes extraction to <article>/<main> containers (avoids nav/sidebar/footer)
/// - Properly removes ALL non-content tags (sanitize-html behavior)
/// - Better plain text extraction
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;

import '../../../../shared/utils/text_cleaner.dart';
import 'html_visibility.dart';

const _minSegmentLength = 30;
const _minHeadingLength = 10;
const _minListItemLength = 20;

final _segmentTags = {
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'li', 'p', 'blockquote', 'pre',
};

const nonTextTags = {
  'style', 'script', 'noscript', 'template', 'svg', 'canvas',
  'iframe', 'object', 'embed',
};

const contentContainerTags = {
  'article', 'main',
};

const allowedTagsForMarkdown = {
  'article', 'section', 'main', 'div', 'p',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'ol', 'ul', 'li', 'blockquote', 'pre', 'code',
  'span', 'strong', 'em', 'b', 'i', 'br', 'a', 'hr',
  'table', 'thead', 'tbody', 'tfoot', 'tr', 'th', 'td',
  'img', 'figure', 'figcaption',
  'sub', 'sup', 'small', 'mark', 'del', 'ins',
};

String sanitizeHtmlForMarkdownConversion(String html) {
  return _sanitizeHtmlKeepStructure(stripHiddenHtml(html));
}

// ── Public API for single-pass pipeline ──

/// Remove non-content tags (script, style, noscript, etc.) from document.
void removeNonTextTags(Document doc) {
  _sanitizeTextOnly(doc);
}

/// Collect article text segments from an already-cleaned Document.
List<String> collectSegmentsFromDocument(Document document) {
  final body = document.body;
  if (body == null) return [];
  return _collectSegments(document, body);
}

String extractArticleContent(String html) {
  final segments = collectSegmentsFromHtml(html);
  if (segments.isNotEmpty) {
    return segments.join('\n');
  }
  final fallback = normalizeWhitespace(extractPlainText(html));
  return fallback;
}

List<String> collectSegmentsFromHtml(String html) {
  final document = parse(stripHiddenHtml(html));
  _sanitizeTextOnly(document);

  // Scope to article/main content
  Element? scope = document.body;
  if (scope == null) return [];

  for (final containerTag in contentContainerTags) {
    final container = document.querySelector(containerTag);
    if (container != null) { scope = container; break; }
  }
  // Heuristic container detection
  if (scope != null) {
    final heuristic = _findContentContainer(scope);
    if (heuristic != null) scope = heuristic;
  }

  if (scope == null) return [];
  return _collectSegments(document, scope);
}

String extractPlainText(String html) {
  final document = parse(stripHiddenHtml(html));

  // Remove non-content tags
  for (final tag in nonTextTags) {
    for (final element in document.querySelectorAll(tag)) {
      element.remove();
    }
  }

  // Remove boilerplate containers
  final b = document.body;
  if (b != null) {
    removeBoilerplateContainers(b);
  }

  return decodeHtmlEntities(document.body?.text ?? document.outerHtml);
}

final _contentClassPatterns = [
  'article', 'post', 'content', 'body', 'main', 'entry',
  'text', 'story', 'detail', 'news', 'single',
  'article-body', 'article-content', 'post-body', 'post-content',
  'entry-content', 'story-body', 'article-detail', 'news-content',
  'blog-post', 'blog-content', 'markdown-body', 'prose',
];

Element? _findContentContainer(Element root) {
  // Score each <div> by content-signal class/id names
  Element? best;
  var bestScore = 0;

  for (final div in root.querySelectorAll('div')) {
    final id = (div.attributes['id'] ?? '').toLowerCase();
    final cls = (div.attributes['class'] ?? '').toLowerCase();
    final combined = '$id $cls';

    var score = 0;
    for (final pattern in _contentClassPatterns) {
      if (combined.contains(pattern)) score += 10;
    }

    // Penalize likely non-content
    if (combined.contains('sidebar') || combined.contains('comment') ||
        combined.contains('footer') || combined.contains('header') ||
        combined.contains('nav') || combined.contains('menu') ||
        combined.contains('ad') || combined.contains('related')) {
      score -= 30;
    }

    if (score > bestScore) {
      bestScore = score;
      best = div;
    }
  }

  // Only use if score is meaningful (> 10)
  return bestScore >= 10 ? best : null;
}

bool _isInsideBoilerplate(Element element) {
  var parent = element.parent;
  while (parent != null) {
    final tag = (parent.localName ?? '').toLowerCase();
    if (tag == 'nav' || tag == 'aside' || tag == 'footer' || tag == 'header') {
      return true;
    }
    parent = parent.parent;
  }
  return false;
}

void removeBoilerplateContainers(Node root) {
  if (root is! Element) return;
  final toRemove = <Element>[];
  _collectBoilerplate(root, toRemove);
  for (final el in toRemove) {
    el.remove();
  }
}

void _collectBoilerplate(Element parent, List<Element> out) {
  for (final child in parent.children) {
    final tag = (child.localName ?? '').toLowerCase();
    if (tag == 'nav' || tag == 'aside' || tag == 'footer' || tag == 'header') {
      out.add(child);
    } else {
      _collectBoilerplate(child, out);
    }
  }
}

void _sanitizeTextOnly(Document doc) {
  final toRemove = <Element>[];
  for (final element in doc.querySelectorAll('*')) {
    final tagName = element.localName ?? '';
    if (tagName.isEmpty) continue;
    if (nonTextTags.contains(tagName)) {
      toRemove.add(element);
      continue;
    }
    if (tagName == 'nav' || tagName == 'aside' || tagName == 'footer' || tagName == 'header') {
      toRemove.add(element);
    }
  }
  for (final element in toRemove) {
    element.remove();
  }
}

List<String> _collectSegments(Document document, Element scope) {
  final segments = <String>[];
  for (final tag in _segmentTags) {
    for (final element in scope.querySelectorAll(tag)) {
      if (_isInsideBoilerplate(element)) continue;
      final raw = element.text;
      final text = normalizeWhitespace(raw).replaceAll(RegExp(r'\n+'), ' ');
      if (text.isEmpty) continue;
      if (tag.startsWith('h')) {
        if (text.length >= _minHeadingLength) segments.add(text);
        continue;
      }
      if (tag == 'li') {
        if (text.length >= _minListItemLength) segments.add('• $text');
        continue;
      }
      if (text.length < _minSegmentLength) continue;
      segments.add(text);
    }
  }
  if (segments.isEmpty) {
    final body = document.querySelector('body');
    removeBoilerplateContainers(body ?? scope);
    final fallback = normalizeWhitespace(body?.text ?? document.outerHtml);
    return fallback.isNotEmpty ? [fallback] : [];
  }
  return segments.where((s) => s.isNotEmpty).toList();
}

String _sanitizeHtmlKeepStructure(String html) {
  final document = parse(html);

  // Remove non-content tags completely (script, style, etc.)
  final toRemove = <Element>[];
  for (final element in document.querySelectorAll('*')) {
    final tagName = element.localName ?? '';
    if (tagName.isEmpty) continue;
    if (nonTextTags.contains(tagName)) {
      toRemove.add(element);
    }
  }
  for (final element in toRemove) {
    element.remove();
  }

  // Remove boilerplate containers
  final b = document.body;
  if (b != null) {
    removeBoilerplateContainers(b);
  }

  // Unwrap tags not in allowed set (remove the tag, keep children)
  final bodyElement = document.body;
  if (bodyElement != null) {
    unwrapDisallowedTags(bodyElement);
  }

  // Strip disallowed attributes, keeping only href on <a> tags
  for (final element in document.querySelectorAll('*')) {
    final tagName = element.localName ?? '';
    if (tagName == 'a') {
      final href = element.attributes['href'];
      element.attributes.clear();
      if (href != null) element.attributes['href'] = href;
    } else if (tagName == 'img') {
      final alt = element.attributes['alt'];
      final src = _resolveLazySrc(element);
      element.attributes.clear();
      if (alt != null) element.attributes['alt'] = alt;
      if (src != null) element.attributes['src'] = src;
    } else if (tagName == 'pre' || tagName == 'code') {
      final cls = element.attributes['class'];
      element.attributes.clear();
      if (cls != null) element.attributes['class'] = cls;
    } else {
      element.attributes.clear();
    }
  }

  return document.outerHtml;
}

void unwrapDisallowedTags(Element scope) {
  // Collect elements to unwrap (iterate in reverse to handle nesting)
  final toUnwrap = <Element>[];
  for (final element in scope.querySelectorAll('*')) {
    final tagName = element.localName ?? '';
    if (tagName.isEmpty) continue;
    if (!allowedTagsForMarkdown.contains(tagName)) {
      toUnwrap.add(element);
    }
  }

  // Unwrap from deepest first (reverse order since querySelectorAll goes depth-first)
  for (final element in toUnwrap.reversed) {
    _unwrapElement(element);
  }
}

void _unwrapElement(Element element) {
  final parent = element.parent;
  if (parent == null) return;

  final children = element.nodes.toList();
  final index = parent.nodes.indexOf(element);

  if (index < 0) return;

  // Replace this element with its children
  element.remove();
  for (var i = children.length - 1; i >= 0; i--) {
    parent.insertBefore(children[i], index < parent.nodes.length ? parent.nodes[index] : null);
  }
}

/// Resolve the real image src from lazy-load attributes.
String? _resolveLazySrc(Element element) {
  final src = element.attributes['src'];
  for (final attr in ['data-src', 'data-original', 'data-lazy-src']) {
    final lazy = element.attributes[attr];
    if (lazy != null && lazy.isNotEmpty) return lazy;
  }
  return src;
}
