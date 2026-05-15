// ignore_for_file: avoid_print

/// Verification test for content extraction pipeline.
///
/// Tests the full pipeline against a realistic HTML page containing:
/// - Navigation boilerplate
/// - Article content
/// - Sidebar with "related articles"
/// - Footer with copyright
/// - Cookie notice
///
/// Run: flutter test test/content_extraction_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/shared/utils/url_classifier.dart';
import 'package:myminimax/shared/utils/text_cleaner.dart';
import 'package:myminimax/shared/utils/content_budget.dart';
import 'package:myminimax/features/tools/data/content/html_visibility.dart';
import 'package:myminimax/features/tools/data/content/article_extractor.dart';
import 'package:myminimax/features/tools/data/content/metadata_extractor.dart';
import 'package:myminimax/features/tools/data/content/jsonld_extractor.dart';
import 'package:myminimax/features/tools/data/content/html_to_markdown.dart';
import 'package:myminimax/features/tools/data/content/content_scorer.dart';
import 'package:myminimax/features/tools/data/content/youtube_extractor.dart';

// Simulates a typical Chinese news article page
const testHtml = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head><title>中国航天完成第500次发射任务 - 科技日报</title></head>
<body>
  <nav>
    <ul><li><a href="/">首页</a></li><li><a href="/tech">科技</a></li><li><a href="/space">航天</a></li></ul>
  </nav>
  <div id="cookie-notice" style="position:fixed;bottom:0">本网站使用Cookie来改善用户体验。继续浏览表示您同意我们的Cookie政策。</div>
  <article>
    <h1>中国航天完成第500次发射任务</h1>
    <p><strong>本报讯</strong> 2026年5月3日，中国航天科技集团在文昌航天发射场成功完成第500次轨道发射任务。</p>
    <p>本次发射使用长征五号B运载火箭，成功将"天和"核心舱扩展模块送入预定轨道。这是中国空间站建设的又一重要里程碑。</p>
    <h2>里程碑意义</h2>
    <p>国家航天局表示，第500次发射标志着中国航天进入高质量发展新阶段。从1970年东方红一号首飞，到今日第500次发射，中国航天走过了56年不平凡的历程。</p>
    <h2>技术突破</h2>
    <p>长征五号B是中国目前运载能力最大的火箭，近地轨道运力达到25吨。本次任务中，火箭首次采用了新型复合材料整流罩，相比传统铝合金材料减重30%。</p>
    <p>"这项技术突破为后续深空探测任务奠定了坚实基础。"航天科技集团总工程师李明表示。</p>
    <table>
      <thead><tr><th>里程碑</th><th>年份</th><th>运载火箭</th></tr></thead>
      <tbody>
        <tr><td>首次发射</td><td>1970</td><td>长征一号</td></tr>
        <tr><td>第100次</td><td>2007</td><td>长征三号甲</td></tr>
        <tr><td>第500次</td><td>2026</td><td>长征五号B</td></tr>
      </tbody>
    </table>
  </article>
  <aside>
    <h3>相关推荐</h3>
    <ul>
      <li><a href="/article/1">SpaceX星舰完成第10次试飞</a></li>
      <li><a href="/article/2">嫦娥七号月球车成功着陆</a></li>
    </ul>
  </aside>
  <footer>
    <p>Copyright © 2026 科技日报 版权所有 | 京ICP备20240503001号</p>
  </footer>
</body>
</html>
''';

void main() {
  group('URL Classifier', () {
    test('detects YouTube URLs', () {
      expect(isYouTubeUrl('https://www.youtube.com/watch?v=abc123def45'), isTrue);
      expect(isYouTubeUrl('https://youtu.be/abc123def45'), isTrue);
      expect(isYouTubeUrl('https://www.bilibili.com/video/BV1xx411c7mD'), isFalse);
    });

    test('extracts YouTube video ID', () {
      expect(extractYouTubeVideoId('https://www.youtube.com/watch?v=abc123def45'), equals('abc123def45'));
      expect(extractYouTubeVideoId('https://youtu.be/abc123def45'), equals('abc123def45'));
      expect(extractYouTubeVideoId('https://www.bilibili.com/video/BV1xx411c7mD'), isNull);
    });

    test('detects direct media URLs', () {
      expect(isDirectMediaUrl('https://example.com/video.mp4'), isTrue);
      expect(isDirectMediaUrl('https://example.com/audio.mp3'), isTrue);
      expect(isDirectMediaUrl('https://example.com/page.html'), isFalse);
    });

    test('detects podcast hosts', () {
      expect(isPodcastHost('https://podcasts.apple.com/podcast/123'), isTrue);
      expect(isPodcastHost('https://open.spotify.com/show/abc'), isTrue);
      expect(isPodcastHost('https://example.com/blog'), isFalse);
    });
  });

  group('Text Cleaner', () {
    test('decodes HTML entities', () {
      expect(decodeHtmlEntities('Hello &amp; World &lt;3'), equals('Hello & World <3'));
      expect(decodeHtmlEntities('&#39;quoted&#39;'), equals("'quoted'"));
      expect(decodeHtmlEntities('Price: &nbsp; \$10'), equals('Price:   \$10'));
    });

    test('normalizes whitespace', () {
      const input = 'Hello   \t  World\n\n\n\nFoo  Bar';
      final result = normalizeForPrompt(input);
      expect(result, equals('Hello World\nFoo Bar'));
    });
  });

  group('Content Budget', () {
    test('clips at sentence boundary', () {
      const long = 'First sentence. Second sentence. Third sentence. Fourth.';
      final result = clipAtSentenceBoundary(long, 35);
      // Should clip at ". " after "First sentence."
      expect(result.length, lessThanOrEqualTo(35));
      expect(result.endsWith('.'), isTrue);
    });

    test('returns full text when under budget', () {
      const short = 'Short text.';
      final result = clipAtSentenceBoundary(short, 100);
      expect(result, equals(short));
    });

    test('applyContentBudget works correctly', () {
      final result = applyContentBudget('Hello World. This is a longer text.', 20);
      expect(result.truncated, isTrue);
      expect(result.totalCharacters, equals(35));
      // Clipped at sentence boundary
      expect(result.content.length, lessThanOrEqualTo(20));
    });
  });

  group('HTML Visibility', () {
    test('strips hidden elements', () {
      const html = '<div><p style="display:none">hidden</p><p>visible</p></div>';
      final result = stripHiddenHtml(html);
      expect(result.contains('visible'), isTrue);
      expect(result.contains('hidden'), isFalse);
    });

    test('strips script and style tags', () {
      const html = '<div><script>alert(1)</script><style>.x{}</style><p>text</p></div>';
      final result = stripHiddenHtml(html);
      expect(result.contains('alert(1)'), isFalse);
      expect(result.contains('.x{}'), isFalse);
      expect(result.contains('text'), isTrue);
    });
  });

  group('Article Extractor', () {
    test('extracts article content from real HTML', () {
      final result = extractArticleContent(testHtml);
      expect(result.isNotEmpty, isTrue);
      expect(result.contains('500次发射'), isTrue);
      expect(result.contains('技术突破'), isTrue);
      expect(result.contains('长征五号B'), isTrue);
    });

    test('extracts plain text without tags', () {
      final result = extractPlainText(testHtml);
      expect(result.contains('<h1>'), isFalse);
      expect(result.contains('中国航天'), isTrue);
    });

    test('sanitizeHtmlForMarkdownConversion removes non-content tags', () {
      final result = sanitizeHtmlForMarkdownConversion(testHtml);
      expect(result.contains('<script'), isFalse);
      expect(result.contains('<style'), isFalse);
      expect(result.contains('<nav'), isFalse);
    });
  });

  group('Metadata Extractor', () {
    test('extracts title from HTML', () {
      final meta = extractMetadataFromHtml(testHtml, 'https://example.com/article');
      expect(meta.title, contains('500次发射'));
      expect(meta.siteName, isNotNull);
    });

    test('falls back to hostname for siteName', () {
      final meta = extractMetadataFromHtml('<html></html>', 'https://www.example.com/page');
      expect(meta.siteName, equals('example.com'));
    });
  });

  group('JSON-LD Extractor', () {
    test('extracts nothing from HTML without JSON-LD', () {
      final result = extractJsonLdContent(testHtml);
      // Our test HTML doesn't have JSON-LD, which is fine
      expect(result, isNull);
    });

    test('extracts from JSON-LD script tag', () {
      const html = '''
        <html><head>
        <script type="application/ld+json">
        {"@type":"Article","name":"Test Title","description":"Test description text"}
        </script>
        </head></html>
      ''';
      final result = extractJsonLdContent(html);
      expect(result, isNotNull);
      expect(result!.title, equals('Test Title'));
      expect(result.description, equals('Test description text'));
      expect(result.type, equals('article'));
    });
  });

  group('HTML to Markdown', () {
    test('converts headings', () {
      const html = '<h1>Title</h1><h2>Subtitle</h2><h3>Section</h3>';
      final md = convertHtmlToMarkdown(html);
      expect(md.contains('# Title'), isTrue);
      expect(md.contains('## Subtitle'), isTrue);
      expect(md.contains('### Section'), isTrue);
    });

    test('converts bold and italic', () {
      const html = '<p>This is <strong>bold</strong> and <em>italic</em> text.</p>';
      final md = convertHtmlToMarkdown(html);
      expect(md.contains('**bold**'), isTrue);
      expect(md.contains('*italic*'), isTrue);
    });

    test('converts links', () {
      const html = '<a href="https://example.com">Click here</a>';
      final md = convertHtmlToMarkdown(html);
      expect(md.contains('[Click here](https://example.com)'), isTrue);
    });

    test('converts tables', () {
      const html = '''
        <table>
          <thead><tr><th>Name</th><th>Value</th></tr></thead>
          <tbody><tr><td>Foo</td><td>1</td></tr><tr><td>Bar</td><td>2</td></tr></tbody>
        </table>
      ''';
      final md = convertHtmlToMarkdown(html);
      expect(md.contains('| Name | Value |'), isTrue);
      expect(md.contains('|---|---|'), isTrue);
      expect(md.contains('| Foo | 1 |'), isTrue);
      expect(md.contains('| Bar | 2 |'), isTrue);
    });

    test('converts real article HTML to structured markdown', () {
      // Use the same pipeline as production: sanitize first, then convert
      final sanitized = sanitizeHtmlForMarkdownConversion(testHtml);
      final md = convertHtmlToMarkdown(sanitized);
      // Verify key content is present
      expect(md.contains('# 中国航天完成第500次发射任务'), isTrue);
      expect(md.contains('**本报讯**'), isTrue);
      expect(md.contains('## 里程碑意义'), isTrue);
      expect(md.contains('## 技术突破'), isTrue);

      // Verify table is converted
      expect(md.contains('| 里程碑 | 年份 | 运载火箭 |'), isTrue);
      expect(md.contains('| 首次发射 | 1970 | 长征一号 |'), isTrue);
      expect(md.contains('| 第500次 | 2026 | 长征五号B |'), isTrue);

      // Verify semantic boilerplate sections are removed
      // Navigation items, footer copyright, sidebar recommendations
      expect(md.contains('版权所有'), isFalse);
      expect(md.contains('京ICP备'), isFalse);
      expect(md.contains('相关推荐'), isFalse);
      // Cookie notice is visible DOM content — may appear but scorer penalizes it
      expect(md.contains('首页'), isFalse,
          reason: 'Nav menu links should be removed');
    });
  });

  group('Content Scorer', () {
    test('scores well-structured content higher', () {
      const good = '# Title\n\nThis is a well structured paragraph with good content.\n\n'
          '## Section 2\n\nAnother paragraph with meaningful text for testing purposes.';
      final goodScore = scoreContent(good, null);

      const bad = '• Home\n• About\n• Contact\n• Services\n• Blog\n• FAQ\n'
          '• Terms\n• Privacy\n• Help\n• Support\n• Login\n• Register\n'
          '• Search\n• Menu\n• More\n• Settings';
      final badScore = scoreContent(bad, null);

      expect(goodScore.score, greaterThan(badScore.score));
    });

    test('detects CJK content', () {
      const cjk = '这是一段中文测试文本。中国航天完成第500次发射任务。'
          '这是一个里程碑式的重要成就。';
      final score = scoreContent(cjk, null);
      print('CJK count: ${score.cjkCount}, total chars: ${score.totalChars}');
      expect(score.cjkCount, greaterThan(20),
          reason: 'Expected CJK count > 20 for Chinese text');
    });

    test('penalizes boilerplate', () {
      const boilerplate = '版权所有 © 2026 科技日报。保留所有权利。'
          '京ICP备20240503001号。阅读更多相关文章。点击查看详情。';
      final score = scoreContent(boilerplate, null);
      expect(score.score, lessThan(0));
    });

    test('prefers real article over navigation HTML', () {
      // Test that the scorer can discriminate article vs nav
      final articleMd = convertHtmlToMarkdown(testHtml);
      final articleScore = scoreContent(articleMd, testHtml);

      const navHtml = '<ul><li>Home</li><li>About</li><li>Contact</li></ul>';
      final navMd = convertHtmlToMarkdown(navHtml);
      final navScore = scoreContent(navMd, navHtml);

      expect(articleScore.score, greaterThan(navScore.score));
      expect(articleScore.headingCount, greaterThan(0));
      expect(articleScore.paragraphCount, greaterThan(3));
    });
  });

  group('YouTube Extractor', () {
    test('returns null for non-YouTube HTML', () {
      final result = extractYouTubeShortDescription(testHtml);
      expect(result, isNull);
    });
  });

  group('Full Pipeline Integration', () {
    test('end-to-end: extracts clean content from real HTML', () {
      // Step 1: Metadata
      final meta = extractMetadataFromHtml(testHtml, 'https://example.com/article');
      expect(meta.title, isNotNull);

      // Step 2: Visibility stripping
      final visibleHtml = stripHiddenHtml(testHtml);
      expect(visibleHtml.contains('cookie-notice'), isFalse); // hidden div, but it's fixed position with no display:none

      // Step 3: Multi-strategy extraction
      // Strategy A: raw segments
      final rawSegments = normalizeForPrompt(extractArticleContent(testHtml));

      // Strategy B: sanitized markdown (our key improvement)
      final sanitized = sanitizeHtmlForMarkdownConversion(testHtml);
      final markdown = convertHtmlToMarkdown(sanitized);
      final normalizedMd = normalizeForPrompt(markdown);

      // Strategy C: clean segments
      final cleanSegments = normalizeForPrompt(extractArticleContent(sanitized));

      // All three should produce meaningful content
      expect(rawSegments.isNotEmpty, isTrue);
      expect(normalizedMd.isNotEmpty, isTrue);
      expect(cleanSegments.isNotEmpty, isTrue);

      // Step 4: Score and pick best
      final rawScore = scoreContent(rawSegments, testHtml);
      final mdScore = scoreContent(normalizedMd, testHtml);
      final cleanScore = scoreContent(cleanSegments, testHtml);

      // Print scores for inspection
      print('=== Content Scoring Results ===');
      print('Raw segments:  score=${rawScore.score.toStringAsFixed(1)}, '
          'paras=${rawScore.paragraphCount}, headings=${rawScore.headingCount}, '
          'chars=${rawScore.totalChars}, CJK=${rawScore.cjkCount}');
      print('Markdown:      score=${mdScore.score.toStringAsFixed(1)}, '
          'paras=${mdScore.paragraphCount}, headings=${mdScore.headingCount}, '
          'chars=${mdScore.totalChars}, CJK=${mdScore.cjkCount}');
      print('Clean segments: score=${cleanScore.score.toStringAsFixed(1)}, '
          'paras=${cleanScore.paragraphCount}, headings=${cleanScore.headingCount}, '
          'chars=${cleanScore.totalChars}, CJK=${mdScore.cjkCount}');

      // Verify markdown has structure (headings preserved)
      expect(mdScore.headingCount, greaterThanOrEqualTo(2),
          reason: 'Markdown should preserve at least 2 headings');

      // Verify content contains the key article info
      expect(rawSegments.contains('500次发射'), isTrue);
      expect(normalizedMd.contains('500次发射'), isTrue);

      // Verify boilerplate is filtered from markdown (the pipeline's preferred output)
      expect(normalizedMd.contains('版权所有'), isFalse,
          reason: 'Footer copyright removed by sanitizeHtmlForMarkdownConversion');
      expect(normalizedMd.contains('相关推荐'), isFalse,
          reason: 'Sidebar removed by sanitizeHtmlForMarkdownConversion');
      expect(normalizedMd.contains('首页'), isFalse,
          reason: 'Navigation menu removed by sanitizeHtmlForMarkdownConversion');
      // Verify markdown preserves structure (heading-based content)
      expect(normalizedMd.contains('##'), isTrue,
          reason: 'Markdown output preserves heading structure');

      // The markdown preserves table structure
      expect(normalizedMd.contains('| 年份 |'), isTrue,
          reason: 'Table structure should be preserved in markdown');

      print('\nAll assertions passed!');
      print('=== Markdown Output Sample ===');
      print(normalizedMd.substring(0, normalizedMd.length < 500 ? normalizedMd.length : 500));
    });
  });
}
