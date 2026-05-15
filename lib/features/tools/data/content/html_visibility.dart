/// Hidden HTML element stripping ported from @steipete/summarize-core.
///
/// Source: packages/core/src/content/link-preview/content/visibility.ts
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;

final _htmlCommentPattern = RegExp(r'<!--[\s\S]*?-->');
final _styleSplitPattern = RegExp(r';');

Map<String, String> _parseStyle(String style) {
  final map = <String, String>{};
  for (final part in style.split(_styleSplitPattern)) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final colon = trimmed.indexOf(':');
    if (colon == -1) continue;
    final key = trimmed.substring(0, colon).trim().toLowerCase();
    final value = trimmed.substring(colon + 1).trim().toLowerCase();
    if (key.isEmpty) continue;
    map[key] = value;
  }
  return map;
}

double? _parseCssNumber(String? value) {
  if (value == null) return null;
  final match = RegExp(r'^(-?\d*\.?\d+)').firstMatch(value.trim());
  if (match == null) return null;
  final parsed = double.tryParse(match.group(1) ?? '');
  return parsed != null && parsed.isFinite ? parsed : null;
}

bool _isHiddenByStyle(String style) {
  final normalized = style.toLowerCase();

  if (normalized.contains(RegExp(r'display\s*:\s*none'))) return true;
  if (normalized.contains(RegExp(r'visibility\s*:\s*hidden'))) return true;
  if (normalized.contains(RegExp(r'opacity\s*:\s*0(?:\.0+)?(?:\s|;|$)'))) return true;
  if (normalized.contains(RegExp(r'font-size\s*:\s*0(?:\.0+)?(?:[a-z%]+)?'))) return true;
  if (normalized.toLowerCase().contains(RegExp(r'clip-path\s*:\s*inset\(\s*100%', caseSensitive: false))) return true;

  final clipRectPattern = RegExp(
    r'clip\s*:\s*rect\(\s*0(?:px)?\s*,\s*0(?:px)?\s*,\s*0(?:px)?\s*,\s*0(?:px)?\s*\)',
    caseSensitive: false,
  );
  if (clipRectPattern.hasMatch(normalized)) return true;

  if (RegExp(r'transform\s*:\s*scale\(\s*0(?:\s*,\s*0)?\s*\)', caseSensitive: false)
      .hasMatch(normalized)) {
    return true;
  }

  final styles = _parseStyle(normalized);
  final width = _parseCssNumber(styles['width']);
  final height = _parseCssNumber(styles['height']);
  final overflow = styles['overflow'] ?? '';
  if (width == 0 && height == 0 && overflow.startsWith('hidden')) return true;

  final textIndent = _parseCssNumber(styles['text-indent']);
  if (textIndent != null && textIndent <= -999) return true;

  final position = styles['position'];
  if (position == 'absolute' || position == 'fixed') {
    final left = _parseCssNumber(styles['left']);
    final top = _parseCssNumber(styles['top']);
    if (left != null && left <= -999) return true;
    if (top != null && top <= -999) return true;
  }

  return false;
}

/// Extract class names from <style> blocks whose sole rule is display:none.
/// Handles the common case: `.hidden { display: none }`, `.d-none { display:none !important }`
Set<String> extractHiddenClassesFromStyles(String html) {
  final hidden = <String>{};
  final stylePattern =
      RegExp(r'<style[^>]*>([\s\S]*?)</style>', caseSensitive: false);
  for (final match in stylePattern.allMatches(html)) {
    final css = match.group(1) ?? '';
    extractHiddenClassesFromCss(css, hidden);
  }
  return hidden;
}

/// Extract hidden class names from raw CSS text (without <style> tags).
void extractHiddenClassesFromCss(String css, Set<String> out) {
  final rulePattern = RegExp(
    r'\.([a-zA-Z_-][\w-]*)\s*\{[^}]*display\s*:\s*none[^}]*\}',
    caseSensitive: false,
  );
  for (final match in rulePattern.allMatches(css)) {
    final cls = match.group(1);
    if (cls != null) out.add(cls.toLowerCase());
  }
}

bool shouldStripElement(Element element, {Set<String>? hiddenClasses}) {
  final tagName = element.localName ?? '';
  if (tagName.isEmpty) return false;

  const nonContentTags = {
    'template', 'script', 'style', 'noscript', 'svg', 'canvas',
    'iframe', 'object', 'embed',
  };
  if (nonContentTags.contains(tagName)) return true;

  final attrs = element.attributes;

  if (attrs.containsKey('hidden')) return true;

  final ariaHidden = attrs['aria-hidden'];
  if (ariaHidden == 'true' || ariaHidden == '1') return true;

  if (tagName == 'input' && attrs['type'] == 'hidden') return true;

  final style = attrs['style'];
  if (style != null && _isHiddenByStyle(style)) return true;

  // Cookie/consent banners — fixed/sticky position with identifiable id/class
  final id = attrs['id'] ?? '';
  final className = attrs['class'] ?? '';
  final combined = '$id $className'.toLowerCase();
  if (_cookiePatterns.any((p) => combined.contains(p)) &&
      style != null &&
      (style.contains('fixed') || style.contains('sticky') || style.contains('absolute'))) {
    return true;
  }

  // Check against <style>-defined hidden classes
  if (hiddenClasses != null && hiddenClasses.isNotEmpty) {
    final classAttr = attrs['class'];
    if (classAttr != null) {
      for (final cls in classAttr.split(RegExp(r'\s+'))) {
        if (hiddenClasses.contains(cls.toLowerCase())) return true;
      }
    }
  }

  return false;
}

const _cookiePatterns = [
  'cookie', 'consent', 'gdpr', 'privacy-banner',
  'cookie-notice', 'cookie-banner', 'cookie-bar',
  'cc-banner', 'data-consent',
];

String stripHiddenHtml(String html) {
  if (html.isEmpty) return html;

  final withoutComments = html.replaceAll(_htmlCommentPattern, '');
  final hiddenClasses = extractHiddenClassesFromStyles(withoutComments);
  final document = parse(withoutComments);

  // Collect nodes to remove first (modifying during iteration is unsafe)
  final toRemove = <Element>[];
  for (final element in document.querySelectorAll('*')) {
    if (shouldStripElement(element, hiddenClasses: hiddenClasses)) {
      toRemove.add(element);
    }
  }

  for (final element in toRemove) {
    element.remove();
  }

  return document.outerHtml;
}
