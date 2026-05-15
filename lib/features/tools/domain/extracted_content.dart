class ExtractedLinkContent {

  const ExtractedLinkContent({
    required this.url,
    required this.content, required this.truncated, required this.totalCharacters, required this.wordCount, this.title,
    this.description,
    this.siteName,
    this.publishedDate,
    this.author,
  });
  final String url;
  final String? title;
  final String? description;
  final String? siteName;
  final String? publishedDate;
  final String? author;
  final String content;
  final bool truncated;
  final int totalCharacters;
  final int wordCount;

  /// Estimated reading time in minutes.
  /// English: ~200 wpm, Chinese: ~400 chars/min.
  int get readingTimeMinutes {
    if (totalCharacters == 0) return 0;
    // Detect CJK-dominant: if > 30% CJK chars, use 400 chars/min
    var cjk = 0;
    for (final ch in content.runes) {
      if (ch >= 0x4E00 && ch <= 0x9FFF) cjk++;
    }
    final cjkRatio = cjk / totalCharacters;
    if (cjkRatio > 0.3) {
      return (totalCharacters / 400).ceil();
    }
    return (wordCount / 200).ceil().clamp(1, 999);
  }
}
