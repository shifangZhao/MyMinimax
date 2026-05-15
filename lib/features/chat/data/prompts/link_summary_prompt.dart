/// Link summary prompt builder ported from @steipete/summarize-core.
///
/// Source: packages/core/src/prompts/link-summary.ts
library;

import 'summary_lengths.dart';


class ShareContextEntry {

  const ShareContextEntry({
    required this.author,
    required this.text, this.handle,
    this.likeCount,
    this.reshareCount,
    this.replyCount,
    this.timestamp,
  });
  final String author;
  final String? handle;
  final String text;
  final int? likeCount;
  final int? reshareCount;
  final int? replyCount;
  final String? timestamp;
}

String _formatCount(int value) => value.toString();

String buildLinkSummaryPrompt({
  required String url,
  required String content, required SummaryLength summaryLength, String? title,
  String? siteName,
  String? description,
  bool truncated = false,
  bool hasTranscript = false,
  String? outputLanguage,
  List<ShareContextEntry> shares = const [],
  String? promptOverride,
}) {
  final contextLines = <String>['Source URL: $url'];

  if (title != null) contextLines.add('Page name: $title');
  if (siteName != null) contextLines.add('Site: $siteName');
  if (description != null) contextLines.add('Page description: $description');
  if (truncated) contextLines.add('Note: Content truncated to the first portion available.');

  final contextHeader = contextLines.join('\n');

  final audienceLine = hasTranscript
      ? 'You summarize online videos for curious Twitter users who want to know whether the clip is worth watching.'
      : 'You summarize online articles for curious Twitter users who want the gist before deciding to dive in.';

  final directive = resolveSummaryLengthSpec(summaryLength);
  final contentLengthLine = content.isNotEmpty
      ? 'Extracted content length: ${_formatCount(content.length)} characters. '
          'Hard limit: never exceed this length. If the requested length is larger, '
          'do not pad — finish early rather than adding filler.'
      : '';

  final needsHeadings = summaryLength == SummaryLength.xl ||
      summaryLength == SummaryLength.xxl;
  final headingInstruction = needsHeadings
      ? 'Use Markdown headings with the "### " prefix to break sections. '
          'Include at least 3 headings and start with a heading. Do not use bold for headings.'
      : '';

  final presetLengthLine = formatPresetLengthGuidance(summaryLength);

  // Build share lines
  final shareLines = shares.map((share) {
    final handle = share.handle != null && share.handle!.isNotEmpty
        ? '@${share.handle}'
        : share.author;
    final metrics = <String>[];
    if (share.likeCount != null && share.likeCount! > 0) {
      metrics.add('${_formatCount(share.likeCount!)} likes');
    }
    if (share.reshareCount != null && share.reshareCount! > 0) {
      metrics.add('${_formatCount(share.reshareCount!)} reshares');
    }
    if (share.replyCount != null && share.replyCount! > 0) {
      metrics.add('${_formatCount(share.replyCount!)} replies');
    }
    final metricsSuffix = metrics.isNotEmpty ? ' [${metrics.join(', ')}]' : '';
    final timestampStr = share.timestamp != null ? ' (${share.timestamp})' : '';
    return '- $handle$timestampStr$metricsSuffix: ${share.text}';
  }).toList();

  final shareBlock = shares.isNotEmpty
      ? 'Tweets from sharers:\n${shareLines.join('\n')}'
      : '';

  final shareGuidance = shares.isNotEmpty
      ? 'You are also given quotes from people who recently shared this link. '
          'When these quotes contain substantive commentary, append a brief subsection titled '
          '"What sharers are saying" with one or two bullet points summarizing the key reactions. '
          'If they are generic reshares with no commentary, omit that subsection.'
      : 'You are not given any quotes from people who shared this link. '
          'Do not fabricate reactions or add a "What sharers are saying" subsection.';

  final languageInstruction = outputLanguage != null
      ? 'Write your response in $outputLanguage.'
      : '';

  final baseInstructions = [
    'Hard rules: never mention sponsor/ads; use straight quotation marks only (no curly quotes).',
    'Apostrophes in contractions are OK.',
    audienceLine,
    directive.guidance,
    directive.formatting,
    headingInstruction,
    presetLengthLine,
    contentLengthLine,
    if (languageInstruction.isNotEmpty) languageInstruction,
    'Keep the response compact by avoiding blank lines between sentences or list items; '
        'use only the single newlines required by the formatting instructions.',
    'Do not use emojis, disclaimers, or speculation.',
    'Write in direct, factual language.',
    'Format the answer in Markdown and obey the length-specific formatting above.',
    'Use short paragraphs; use bullet lists only when they improve scanability; '
        'avoid rigid templates.',
    'Include 1-2 short exact excerpts (max 25 words each) formatted as Markdown italics '
        'using single asterisks when there is a strong, non-sponsor line. '
        'Use straight quotation marks (no curly) as needed. '
        'If no suitable line exists, omit excerpts. '
        'Never include ad/sponsor/boilerplate excerpts and do not mention them.',
    'Base everything strictly on the provided content and never invent details.',
    'Final check: remove any sponsor/ad references or mentions of skipping/ignoring content. '
        'Ensure excerpts (if any) are italicized and use only straight quotes.',
    shareGuidance,
  ].where((line) => line.trim().isNotEmpty).join('\n');

  final instructions = promptOverride ?? baseInstructions;

  final context = [contextHeader, shareBlock]
      .where((line) => line.trim().isNotEmpty)
      .join('\n');

  return _buildTaggedPrompt(
    instructions: instructions,
    context: context,
    content: content,
  );
}

String _buildTaggedPrompt({
  required String instructions,
  required String context,
  required String content,
}) {
  return '<instructions>\n$instructions\n</instructions>\n\n'
      '<context>\n$context\n</context>\n\n'
      '<content>\n$content\n</content>';
}
