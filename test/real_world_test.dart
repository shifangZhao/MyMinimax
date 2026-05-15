// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/shared/utils/text_cleaner.dart';
import 'package:myminimax/shared/utils/content_budget.dart';
import 'package:myminimax/features/tools/data/content/html_pipeline.dart';
import 'package:myminimax/features/tools/data/content/content_scorer.dart';
import 'package:myminimax/features/tools/data/content/metadata_extractor.dart';

void main() {
  test('Real HTML: httpbin Moby Dick', () {
    final html = File('test/httpbin.html').readAsStringSync();
    print('\n========================================');
    print('REAL URL: http://httpbin.org/html');
    print('========================================');
    print('Input: ${html.length} chars raw HTML\n');

    // Extract metadata
    final meta = extractMetadataFromHtml(html, 'http://httpbin.org/html');
    print('--- METADATA ---');
    print('Title: ${meta.title ?? "N/A"}');
    print('Description: ${meta.description ?? "N/A"}');
    print('Site: ${meta.siteName ?? "N/A"}');

    // Pipeline
    final pipeline = HtmlPipeline(html);
    final markdown = pipeline.toMarkdown();
    final normalized = normalizeForPrompt(markdown);
    final budget = applyContentBudget(normalized, 3000);

    print('\n--- OLD APPROACH (tag strip) ---');
    final oldText = html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    print('Size: ${oldText.length} chars');

    print('\n--- NEW APPROACH (HtmlPipeline) ---');
    print('Size: ${budget.content.length} chars');
    print('Reduction: ${((1-budget.content.length/html.length)*100).round()}%');

    // Scoring
    final newScore = scoreContent(budget.content, html);
    final oldScore = scoreContent(oldText, html);
    print('Old score: ${oldScore.score.toStringAsFixed(1)} (${oldScore.paragraphCount} paras, ${oldScore.headingCount} heads)');
    print('New score: ${newScore.score.toStringAsFixed(1)} (${newScore.paragraphCount} paras, ${newScore.headingCount} heads)');

    print('\n=== CLEAN MARKDOWN OUTPUT ===');
    print(budget.content);

    // Assertions
    expect(budget.content.contains('<'), isFalse, reason: 'No HTML tags');
    expect(budget.content.contains('Moby-Dick'), isTrue, reason: 'Title preserved');
    expect(budget.content.contains('Herman Melville'), isTrue, reason: 'Author preserved');
    expect(budget.content.length, greaterThan(100), reason: 'Has content');
    expect(newScore.headingCount, greaterThanOrEqualTo(1), reason: 'Has heading');
  });

  test('SPA/JS page: InfoQ (empty static content)', () {
    final html = File('test/article.html').readAsStringSync();
    print('\n========================================');
    print('REAL URL: https://www.infoq.cn/article/...');
    print('========================================');
    print('Input: ${html.length} chars raw HTML\n');

    // Detect SPA/JS-only pages
    final textRatio = html.replaceAll(RegExp(r'<[^>]*>'), '').trim().length / html.length;
    print('Text ratio: ${(textRatio*100).round()}%');
    if (textRatio < 0.05) {
      print('DETECTED: SPA/JS-rendered page (${(textRatio*100).round()}% text)');
      print('→ Cannot extract from static HTML. Page requires JavaScript.');
    }

    final pipeline = HtmlPipeline(html);
    final markdown = pipeline.toMarkdown();
    print('\nMarkdown output: ${markdown.length} chars');

    // Should gracefully handle empty content
    expect(markdown.length, lessThan(100),
        reason: 'SPA pages should return minimal/empty output, not crash');
  });
}
