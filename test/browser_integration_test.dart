// ignore_for_file: avoid_print

/// Simulates the browser→pipeline integration.
///
/// Tests what happens when browser_get_content(format:'markdown') and
/// browser_summarize run on a real page's outerHTML.
///
/// The HTML simulates what document.documentElement.outerHTML returns
/// from a typical news article page loaded in the WebView.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/features/tools/data/content/html_pipeline.dart';
import 'package:myminimax/features/tools/data/content/content_scorer.dart';

// Simulates what the browser WebView's outerHTML would return for a news page
const browserPageHtml = r'''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta property="og:title" content="GPT-5发布：AI推理能力首次超越人类博士">
<meta property="og:description" content="OpenAI发布GPT-5，在数学、编程、科学推理方面超越人类专家。">
<meta property="og:site_name" content="机器之心">
<meta name="article:published_time" content="2026-05-03T10:30:00+08:00">
<meta name="author" content="张明">
<title>GPT-5发布 | 机器之心</title>
</head>
<body>
<nav><a href="/">首页</a><a href="/ai">AI</a></nav>
<header class="site-header"><div class="ad-banner">广告</div></header>
<main>
<article>
<h1>GPT-5发布：AI推理能力首次超越人类博士</h1>
<div class="meta"><span>张明</span><time datetime="2026-05-03">2026-05-03</time></div>
<h2>核心突破</h2>
<p>GPT-5在MATH基准测试中达到<strong>96.2%</strong>准确率，超越人类专家的94%。</p>
<table><thead><tr><th>测试</th><th>GPT-4o</th><th>GPT-5</th><th>人类</th></tr></thead>
<tbody><tr><td>MATH</td><td>76.6</td><td>96.2</td><td>94.0</td></tr></tbody></table>
<h2>技术细节</h2>
<p>新模型引入深度推理链技术，可将复杂问题分解为上百个子问题。</p>
<ul><li>自动拆解子问题</li><li>交叉验证推理</li></ul>
</article>
</main>
<aside><h3>相关推荐</h3><ul><li><a href="/1">Claude发布</a></li></ul></aside>
<footer><p>© 2026 版权所有 京ICP备12345号</p></footer>
</body>
</html>
''';

void main() {
  group('Browser→Pipeline Integration', () {
    test('browser_get_content(format: markdown) simulated', () {
      // This is what _getContent does when format:'markdown':
      //   1. controller.evaluateJavascript('document.documentElement.outerHTML')
      //   2. HtmlPipeline(html).toMarkdown()
      final pipeline = HtmlPipeline(browserPageHtml);
      final markdown = pipeline.toMarkdown();

      print('\n=== browser_get_content(format:"markdown") ===');
      print(markdown);
      print('');

      // Must preserve actual content
      expect(markdown.contains('GPT-5'), isTrue);
      expect(markdown.contains('96.2%'), isTrue);
      expect(markdown.contains('推理链'), isTrue);

      // Must remove boilerplate
      expect(markdown.contains('版权所有'), isFalse);
      expect(markdown.contains('京ICP备'), isFalse);
      expect(markdown.contains('相关推荐'), isFalse);
      expect(markdown.contains('首页'), isFalse);
      expect(markdown.contains('广告'), isFalse);

      // Must preserve structure
      expect(markdown.contains('# GPT-5'), isTrue);
      expect(markdown.contains('## 核心突破'), isTrue);
      expect(markdown.contains('| MATH |'), isTrue);
      expect(markdown.contains('**96.2%**'), isTrue);
    });

    test('browser_summarize simulated', () {
      // This is what _browserSummarize does:
      //   1. Get outerHTML from WebView
      //   2. HtmlPipeline → metadata + markdown + scoring
      //   3. Format structured summary
      final pipeline = HtmlPipeline(browserPageHtml);
      final meta = pipeline.extractMetadata('');
      final markdown = pipeline.toMarkdown();
      final score = scoreContent(markdown, browserPageHtml);

      final buffer = StringBuffer();
      if (meta.title != null) buffer.writeln('# ${meta.title}');
      if (meta.siteName != null) buffer.writeln('**Source:** ${meta.siteName}');
      if (meta.author != null) buffer.writeln('**Author:** ${meta.author}');
      if (meta.publishedDate != null) buffer.writeln('**Published:** ${meta.publishedDate}');
      buffer.writeln('**Reading:** ~${((markdown.length / 400).ceil())} min');
      buffer.writeln('**Quality:** ${score.score.toStringAsFixed(0)}/100');
      buffer.writeln('**Signals:** ${score.reasons.join(", ")}');
      if (meta.description != null) buffer.writeln('\n> ${meta.description}');
      buffer.writeln('\n---\n');
      buffer.write(markdown);

      print('\n=== browser_summarize ===');
      print(buffer.toString());
      print('');

      // Metadata verification
      expect(meta.title, contains('GPT-5'));
      expect(meta.siteName, equals('机器之心'));
      expect(meta.author, equals('张明'));
      expect(meta.publishedDate, contains('2026'));

      // Score verification
      expect(score.headingCount, greaterThanOrEqualTo(2));
      expect(score.score, greaterThan(30));

      // Output contains structured header
      expect(buffer.toString().contains('**Source:** 机器之心'), isTrue);
      expect(buffer.toString().contains('**Author:** 张明'), isTrue);
      expect(buffer.toString().contains('**Published:**'), isTrue);
      expect(buffer.toString().contains('**Quality:**'), isTrue);
    });

    test('format: text still works (backward compat)', () {
      // Legacy mode: raw innerText
      // Simulates what browser_get_content(format:'text') does
      const rawInnerText = '首页 AI 广告 GPT-5发布 核心突破 96.2% '
          '技术细节 推理链 相关推荐 Claude发布 © 2026 版权所有';

      // Should NOT be structured
      expect(rawInnerText.contains('#'), isFalse);

      // But should contain all text (including boilerplate — that's the legacy behavior)
      expect(rawInnerText.contains('首页'), isTrue);
      expect(rawInnerText.contains('版权所有'), isTrue);

      // Markdown mode should be different
      final pipeline = HtmlPipeline(browserPageHtml);
      final markdown = pipeline.toMarkdown();
      // Markdown is structured, old format is flat
      expect(markdown, isNot(equals(rawInnerText)));
    });

    test('WebAgent _captureState simulation', () {
      // Simulates what the agent sees each step after the P1 change
      // (format:'markdown', truncated to 4000 chars)
      final pipeline = HtmlPipeline(browserPageHtml);
      final markdown = pipeline.toMarkdown();
      final actualLen = markdown.length;
      final truncated = actualLen > 4000
          ? '${markdown.substring(0, 4000)}\n\n[Truncated]'
          : markdown;

      print('\n=== Agent <page_text> block ===');
      print(truncated);

      // Agent's page_text should be clean and structured
      expect(truncated.contains('版权所有'), isFalse);
      expect(truncated.contains('# '), isTrue);
      expect(truncated.contains('| MATH |'), isTrue);

      // Should be under or close to 4000 char limit
      expect(truncated.length, lessThanOrEqualTo(4100));
    });
  });
}
