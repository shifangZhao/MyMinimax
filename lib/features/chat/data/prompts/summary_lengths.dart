/// Summary length presets ported from @steipete/summarize-core.
///
/// Source: packages/core/src/prompts/summary-lengths.ts
library;

enum SummaryLength { short, medium, long, xl, xxl }

class SummaryLengthSpec {

  const SummaryLengthSpec({
    required this.guidance,
    required this.formatting,
    required this.targetCharacters,
    required this.minCharacters,
    required this.maxCharacters,
    required this.maxTokens,
  });
  final String guidance;
  final String formatting;
  final int targetCharacters;
  final int minCharacters;
  final int maxCharacters;
  final int maxTokens;
}

const _specs = <SummaryLength, SummaryLengthSpec>{
  SummaryLength.short: SummaryLengthSpec(
    guidance:
        'Write a tight summary that delivers the primary claim plus one high-signal supporting detail.',
    formatting:
        'Use 1-2 short paragraphs (a single paragraph is fine). Aim for 2-5 sentences total.',
    targetCharacters: 900,
    minCharacters: 600,
    maxCharacters: 1200,
    maxTokens: 768,
  ),
  SummaryLength.medium: SummaryLengthSpec(
    guidance:
        'Write a clear summary that covers the core claim plus the most important supporting evidence or data points.',
    formatting:
        'Use 1-3 short paragraphs (2 is typical, but a single paragraph is okay if the content is simple). Aim for 2-3 sentences per paragraph.',
    targetCharacters: 1800,
    minCharacters: 1200,
    maxCharacters: 2500,
    maxTokens: 1536,
  ),
  SummaryLength.long: SummaryLengthSpec(
    guidance:
        'Write a detailed summary that prioritizes the most important points first, followed by key supporting facts or events, then secondary details or conclusions stated in the source.',
    formatting:
        'Paragraphs are optional; use up to 3 short paragraphs. Aim for 2-4 sentences per paragraph when you split into paragraphs.',
    targetCharacters: 4200,
    minCharacters: 2500,
    maxCharacters: 6000,
    maxTokens: 3072,
  ),
  SummaryLength.xl: SummaryLengthSpec(
    guidance:
        'Write a detailed summary that captures the main points, supporting facts, and concrete numbers or quotes when present.',
    formatting: 'Use 2-5 short paragraphs. Aim for 2-4 sentences per paragraph.',
    targetCharacters: 9000,
    minCharacters: 6000,
    maxCharacters: 14000,
    maxTokens: 6144,
  ),
  SummaryLength.xxl: SummaryLengthSpec(
    guidance:
        'Write a comprehensive summary that covers background, main points, evidence, and stated outcomes in the source text; avoid adding implications or recommendations unless explicitly stated.',
    formatting: 'Use 3-7 short paragraphs. Aim for 2-4 sentences per paragraph.',
    targetCharacters: 17000,
    minCharacters: 14000,
    maxCharacters: 22000,
    maxTokens: 12288,
  ),
};

const summaryLengthToTokens = <SummaryLength, int>{
  SummaryLength.short: 768,
  SummaryLength.medium: 1536,
  SummaryLength.long: 3072,
  SummaryLength.xl: 6144,
  SummaryLength.xxl: 12288,
};

const summaryLengthMaxCharacters = <SummaryLength, int>{
  SummaryLength.short: 1200,
  SummaryLength.medium: 2500,
  SummaryLength.long: 6000,
  SummaryLength.xl: 14000,
  SummaryLength.xxl: 22000,
};

SummaryLengthSpec resolveSummaryLengthSpec(SummaryLength length) {
  return _specs[length]!;
}

String formatPresetLengthGuidance(SummaryLength length) {
  final spec = resolveSummaryLengthSpec(length);
  return 'Target length: around ${_formatCount(spec.targetCharacters)} characters '
      '(acceptable range ${_formatCount(spec.minCharacters)}-${_formatCount(spec.maxCharacters)}). '
      'This is a soft guideline; prioritize clarity.';
}

SummaryLength pickSummaryLengthForCharacters(int maxCharacters) {
  if (maxCharacters <= summaryLengthMaxCharacters[SummaryLength.short]!) return SummaryLength.short;
  if (maxCharacters <= summaryLengthMaxCharacters[SummaryLength.medium]!) return SummaryLength.medium;
  if (maxCharacters <= summaryLengthMaxCharacters[SummaryLength.long]!) return SummaryLength.long;
  if (maxCharacters <= summaryLengthMaxCharacters[SummaryLength.xl]!) return SummaryLength.xl;
  return SummaryLength.xxl;
}

int estimateMaxCompletionTokensForCharacters(int maxCharacters) {
  final estimate = (maxCharacters / 4).ceil();
  return estimate < 256 ? 256 : estimate;
}

String _formatCount(int value) {
  return value.toString();
}
