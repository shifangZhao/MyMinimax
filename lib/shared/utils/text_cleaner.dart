/// String normalization utilities ported from @steipete/summarize-core.
///
/// Source: packages/core/src/content/link-preview/content/cleaner.ts
library;

final _invisibleUnicode = RegExp(
  '[\\u200B-\\u200F\\u202A-\\u202E\\u2060-\\u2069\\uFEFF]',
  unicode: true,
);

String decodeHtmlEntities(String input) {
  return input
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&#x2F;', '/')
      .replaceAll('&nbsp;', ' ');
}

String stripInvisibleUnicode(String input) {
  return input.replaceAll(_invisibleUnicode, '');
}

String normalizeWhitespace(String input) {
  return stripInvisibleUnicode(input)
      .replaceAll(' ', ' ')
      .replaceAll(RegExp(r'[\t ]+'), ' ')
      .replaceAll(RegExp(r'\s*\n\s*'), '\n')
      .trim();
}

String normalizeForPrompt(String input) {
  return stripInvisibleUnicode(input)
      .replaceAll(' ', ' ')
      .replaceAll(RegExp(r'[\t ]+'), ' ')
      .replaceAll(RegExp(r'\s*\n\s*'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String? normalizeCandidate(String? value) {
  if (value == null || value.isEmpty) return null;
  final trimmed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return trimmed.isNotEmpty ? trimmed : null;
}

String clipAtSentenceBoundary(String input, int maxLength) {
  if (input.length <= maxLength) return input;

  final slice = input.substring(0, maxLength);
  final lastBreak = [
    slice.lastIndexOf('. '),
    slice.lastIndexOf('! '),
    slice.lastIndexOf('? '),
    slice.lastIndexOf('\n\n'),
  ].reduce((a, b) => a > b ? a : b);

  if (lastBreak > maxLength * 0.5) {
    return slice.substring(0, lastBreak + 1);
  }
  return slice;
}
