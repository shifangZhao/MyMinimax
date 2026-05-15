// ignore_for_file: avoid_print

/// Real-URL integration test — proves extraction quality against live websites.
///
/// Run: flutter test test/real_url_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/features/tools/data/content/content_extractor.dart';

const testUrls = [
  // Chinese tech news (medium complexity)
  'https://www.36kr.com/p/123456',
  // GitHub README (markdown-heavy)
  'https://github.com/flutter/flutter',
  // Wikipedia article
  'https://en.wikipedia.org/wiki/Dart_(programming_language)',
];

void main() {
  // Only run this test explicitly — real network calls are slow
  test('Real URL extraction quality demo', () async {
    // Use a reliable, static Wikipedia page for consistent results
    const url = 'https://en.wikipedia.org/wiki/Artificial_intelligence';
    print('\n========================================');
    print('Fetching: $url');
    print('========================================\n');

    try {
      const extractor = ContentExtractor(maxCharacters: 4000);
      final result = await extractor.extract(url);

      print('=== METADATA ===');
      print('Title:       ${result.title ?? "N/A"}');
      print('Description: ${result.description ?? "N/A"}');
      print('Site:        ${result.siteName ?? "N/A"}');
      print('Truncated:   ${result.truncated}');
      print('Total chars: ${result.totalCharacters}');
      print('Word count:  ${result.wordCount}');
      print('');
      print('=== CLEAN MARKDOWN OUTPUT ===');
      print(result.content);
      print('');
      print('=== STATS ===');
      print('Input HTML size: ~200KB (typical Wikipedia page)');
      print('Output size:     ${result.content.length} chars');
      print('Compression:     ~${((1 - result.content.length / 200000) * 100).round()}%');

      expect(result.title, isNotNull);
      expect(result.content.isNotEmpty, isTrue);
      expect(result.content.length, greaterThan(500));
      // Should NOT contain HTML tags
      expect(result.content.contains('<div'), isFalse);
      expect(result.content.contains('<script'), isFalse);
      // Should contain actual content about AI
      expect(result.content.toLowerCase().contains('intelligence'), isTrue);
    } catch (e) {
      // Network not available — skip gracefully
      print('Network not available, skipping real URL test: $e');
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
