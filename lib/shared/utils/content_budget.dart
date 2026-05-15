/// Content budget utilities ported from @steipete/summarize-core.
///
/// Source: packages/core/src/content/link-preview/content/cleaner.ts (ContentBudget section)
library;

import 'text_cleaner.dart';

final _wordSplitPattern = RegExp(r'\s+');

class ContentBudgetResult {

  const ContentBudgetResult({
    required this.content,
    required this.truncated,
    required this.totalCharacters,
    required this.wordCount,
  });
  final String content;
  final bool truncated;
  final int totalCharacters;
  final int wordCount;
}

ContentBudgetResult applyContentBudget(
  String baseContent,
  int maxCharacters,
) {
  final totalCharacters = baseContent.length;
  final truncated = totalCharacters > maxCharacters;
  final clipped = truncated
      ? clipAtSentenceBoundary(baseContent, maxCharacters)
      : baseContent;
  final content = clipped.trim();
  final wordCount = content.isNotEmpty
      ? content.split(_wordSplitPattern).where((s) => s.isNotEmpty).length
      : 0;

  return ContentBudgetResult(
    content: content,
    truncated: truncated,
    totalCharacters: totalCharacters,
    wordCount: wordCount,
  );
}
