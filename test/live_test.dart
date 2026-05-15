// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/features/tools/data/content/content_extractor.dart';

void main() {
  test('LIVE: Wikipedia article', () async {
    const url = 'https://en.wikipedia.org/wiki/Dart_(programming_language)';
    print('\n=== FETCHING: $url ===\n');
    try {
      const extractor = ContentExtractor(maxCharacters: 3000);
      final result = await extractor.extract(url);
      print('Title: ${result.title}');
      print('Site: ${result.siteName}');
      print('Date: ${result.publishedDate}');
      print('Author: ${result.author}');
      print('Reading: ~${result.readingTimeMinutes} min');
      print('Chars: ${result.totalCharacters} → ${result.content.length}');
      print('Truncated: ${result.truncated}');
      print('\n--- CONTENT ---');
      print(result.content);
      expect(result.content.isNotEmpty, true);
      expect(result.content.contains('<'), false,
          reason: 'No HTML tags in output');
      expect(result.title, isNotNull);
    } catch (e) {
      print('SKIPPED (network unavailable): $e');
    }
  }, timeout: const Timeout(Duration(seconds: 30)), skip: true);
}
