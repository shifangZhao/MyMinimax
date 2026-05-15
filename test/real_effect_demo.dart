// ignore_for_file: avoid_print

/// Real effect demonstration — mirrors the DOM structure of actual Chinese news sites.
///
/// This HTML is structurally identical to what you'd get from fetching
/// a real 36kr/IT之家/Hacker News article. Same tag soup, same boilerplate.
///
/// Run: flutter test test/real_effect_demo.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/features/tools/data/content/html_to_markdown.dart';
import 'package:myminimax/features/tools/data/content/article_extractor.dart';
import 'package:myminimax/features/tools/data/content/content_scorer.dart';
import 'package:myminimax/shared/utils/text_cleaner.dart';
import 'package:myminimax/shared/utils/content_budget.dart';

// Realistic news site HTML — mirrors 36kr/IT之家 structure
const realNewsHtml = r'''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta property="og:title" content="OpenAI发布GPT-5：推理能力超越人类博士水平">
<meta property="og:description" content="OpenAI今日正式发布GPT-5模型，在数学推理、代码生成、科学分析等多项基准测试中首次超越人类专家水平。">
<meta name="description" content="OpenAI今日正式发布GPT-5模型">
<meta property="og:site_name" content="36氪">
<title>OpenAI发布GPT-5：推理能力超越人类博士水平 | 36氪</title>
<script src="/analytics.js"></script>
<style>.ad{display:none}</style>
</head>
<body>
<!-- ====== NAV BAR ====== -->
<header class="site-header">
  <nav class="main-nav">
    <ul>
      <li><a href="/">首页</a></li>
      <li><a href="/tech">科技</a></li>
      <li><a href="/ai">人工智能</a></li>
      <li><a href="/startup">创业</a></li>
      <li><a href="/invest">投资</a></li>
    </ul>
  </nav>
  <div class="user-menu">
    <a href="/login">登录</a>
    <a href="/register">注册</a>
  </div>
</header>

<!-- ====== COOKIE BANNER ====== -->
<div id="cookie-consent-banner" style="position: fixed; bottom: 0; width: 100%; background: #333; color: white; padding: 12px; z-index: 9999;">
  本网站使用Cookie来改善用户体验。继续浏览表示您同意我们的Cookie政策。
  <button>接受</button>
</div>

<!-- ====== MAIN CONTENT ====== -->
<main>
  <article class="article-detail">
    <h1 class="article-title">OpenAI发布GPT-5：推理能力超越人类博士水平</h1>
    <div class="article-meta">
      <span>作者：张明</span>
      <span>2026年5月3日 10:30</span>
      <span>阅读时间：约8分钟</span>
    </div>

    <div class="article-summary">
      <p><strong>摘要：</strong>OpenAI今日正式发布GPT-5模型，在多项基准测试中首次超越人类专家水平。新模型引入了"深度推理链"技术，可将复杂问题分解为上百个推理步骤。</p>
    </div>

    <div class="article-body">
      <p>北京时间5月3日凌晨，OpenAI在旧金山总部举办了春季产品发布会，正式发布了其最新一代大语言模型——<strong>GPT-5</strong>。</p>

      <p>OpenAI CEO Sam Altman在发布会上表示："GPT-5代表了我们在AGI道路上的一个重要里程碑。它在数学、编程和科学推理方面的能力已经超越了大多数人类专家。"</p>

      <h2>核心性能突破</h2>

      <p>根据OpenAI公布的基准测试数据，GPT-5在以下领域实现了重大突破：</p>

      <table>
        <thead>
          <tr><th>测试项目</th><th>GPT-4o</th><th>GPT-5</th><th>人类专家</th></tr>
        </thead>
        <tbody>
          <tr><td>MATH-500</td><td>76.6%</td><td>96.2%</td><td>94.0%</td></tr>
          <tr><td>GPQA-Diamond</td><td>53.4%</td><td>87.9%</td><td>82.0%</td></tr>
          <tr><td>SWE-bench</td><td>41.7%</td><td>78.3%</td><td>75.0%</td></tr>
          <tr><td>HumanEval</td><td>92.0%</td><td>99.1%</td><td>99.5%</td></tr>
        </tbody>
      </table>

      <h2>深度推理链技术</h2>

      <p>GPT-5最大的技术创新是"深度推理链"（Deep Reasoning Chain）。传统LLM在回答复杂问题时一次性生成答案，而GPT-5会：</p>

      <ol>
        <li>将复杂问题自动拆解为多个子问题</li>
        <li>为每个子问题独立推理并交叉验证</li>
        <li>当推理结果出现矛盾时自动回溯修正</li>
        <li>最终整合所有子答案形成完整回复</li>
      </ol>

      <p>OpenAI CTO Mira Murati解释："这就像让一个团队里的多位专家分工协作，而不是一个人硬撑。"</p>

      <h2>定价与可用性</h2>

      <p>GPT-5将通过API和ChatGPT Plus/Pro订阅提供服务：</p>

      <ul>
        <li>API价格：输入 $15/M tokens，输出 $60/M tokens</li>
        <li>ChatGPT Plus用户（$20/月）：每月100条GPT-5消息</li>
        <li>ChatGPT Pro用户（$200/月）：无限制访问</li>
        <li>免费用户：可在"探索模式"下每天使用3次</li>
      </ul>

      <p>值得关注的是，GPT-5的上下文窗口扩展到了<strong>100万tokens</strong>，可以一次性处理超过15万行代码或整部《三体》三部曲。</p>

      <blockquote>
        <p>"这不仅是模型的胜利，更是人类理解智能本质的一大步。"—— Geoffrey Hinton，图灵奖得主</p>
      </blockquote>
    </div>
  </article>
</main>

<!-- ====== SIDEBAR ====== -->
<aside class="sidebar">
  <div class="related-articles">
    <h3>相关推荐</h3>
    <ul>
      <li><a href="/article/1">DeepMind发布Gemini 3.0</a></li>
      <li><a href="/article/2">Anthropic公布Claude 5技术细节</a></li>
      <li><a href="/article/3">中国大模型企业融资超百亿</a></li>
    </ul>
  </div>
  <div class="ad-banner">
    <img src="/ads/ai-tools-promo.jpg" alt="广告">
  </div>
</aside>

<!-- ====== FOOTER ====== -->
<footer>
  <div class="footer-links">
    <a href="/about">关于我们</a>
    <a href="/contact">联系我们</a>
    <a href="/privacy">隐私政策</a>
    <a href="/terms">服务条款</a>
  </div>
  <p class="copyright">Copyright © 2026 36氪 版权所有 | 京ICP备20240503001号 | 京公网安备11010102000001号</p>
</footer>

</body>
</html>
''';

void main() {
  group('Before vs After — real effect demonstration', () {
    test('BEFORE: raw HTML (what fetchUrl used to return)', () {
      print('\n========== BEFORE: 原始 HTML (旧版 fetchUrl) ==========');
      final rawText = extractPlainText(realNewsHtml);
      final snippet = rawText.length > 800
          ? '${rawText.substring(0, 800)}...'
          : rawText;
      print(snippet);
      print('原始 HTML 总字符: ${realNewsHtml.length}');
      print('提取纯文本总字符 (含噪音): ${rawText.length}');
      print('估算 token (中文): ~${(rawText.length / 2).round()} tokens');
    });

    test('AFTER: cleaned Markdown (new fetchUrl)', () {
      print('\n========== AFTER: 清洗后 (新版 fetchUrl) ==========');

      // Run the full pipeline manually
      final sanitized = sanitizeHtmlForMarkdownConversion(realNewsHtml);
      final markdown = convertHtmlToMarkdown(sanitized);
      final normalized = normalizeForPrompt(markdown);
      final budget = applyContentBudget(normalized, 4000);

      print(budget.content);
      print('');
      print('输出字符: ${budget.content.length}');
      print('估算 token (中文): ~${(budget.content.length / 2).round()} tokens');
      print('压缩比: ${(100 - budget.content.length * 100 / realNewsHtml.length).round()}%');
    });

    test('CONTENT SCORING: multi-strategy comparison', () {
      print('\n========== 多策略内容评分对比 ==========');

      // Strategy A: raw segments
      final rawSeg = normalizeForPrompt(extractArticleContent(realNewsHtml));
      final rawScore = scoreContent(rawSeg, realNewsHtml);

      // Strategy B: sanitized markdown (our key improvement)
      final sanitized = sanitizeHtmlForMarkdownConversion(realNewsHtml);
      final md = convertHtmlToMarkdown(sanitized);
      final normalizedMd = normalizeForPrompt(md);
      final mdScore = scoreContent(normalizedMd, realNewsHtml);

      // Strategy C: clean segments
      final cleanSeg = normalizeForPrompt(
          extractArticleContent(sanitizeHtmlForMarkdownConversion(realNewsHtml)));
      final cleanScore = scoreContent(cleanSeg, realNewsHtml);

      final strategies = [
        ('Raw Segments', rawScore),
        ('Markdown (OURS)', mdScore),
        ('Clean Segments', cleanScore),
      ];

      strategies.sort((a, b) => b.$2.score.compareTo(a.$2.score));

      print('Rank | Strategy         | Score  | Paras | Heads | Chars | CJK');
      print('-----|------------------|--------|-------|-------|-------|-----');
      for (var i = 0; i < strategies.length; i++) {
        final s = strategies[i];
        final marker = i == 0 ? '★' : ' ';
        print('$marker ${i + 1}   | ${s.$1.padRight(16)} | ${s.$2.score.toStringAsFixed(1).padLeft(6)} | '
            '${s.$2.paragraphCount.toString().padLeft(5)} | ${s.$2.headingCount.toString().padLeft(5)} | '
            '${s.$2.totalChars.toString().padLeft(5)} | ${s.$2.cjkCount.toString().padLeft(4)}');
      }

      // Winner gets selected
      final winner = strategies.first;
      print('\nPipeline selects: ${winner.$1} (score: ${winner.$2.score.toStringAsFixed(1)})');
      print('Reasons: ${winner.$2.reasons.join(", ")}');

      // Verify markdown wins (it preserves structure best)
      expect(mdScore.score, greaterThan(rawScore.score),
          reason: 'Markdown with structure MUST beat flat segments');
      expect(mdScore.headingCount, greaterThan(0),
          reason: 'Markdown preserves heading structure');
    });

    test('BOILERPLATE DETECTION: verify noise removal', () {
      final sanitized = sanitizeHtmlForMarkdownConversion(realNewsHtml);
      final md = convertHtmlToMarkdown(sanitized);

      print('\n========== 模板检测 ==========');

      final checks = {
        '导航链接 "首页"': md.contains('首页'),
        'Cookie横幅': md.contains('Cookie'),
        '页脚版权 "京ICP备"': md.contains('京ICP备'),
        '页脚 "版权所有"': md.contains('版权所有'),
        '登录链接': md.contains('登录') || md.contains('注册'),
        '侧栏 "相关推荐"': md.contains('相关推荐'),
        '广告文字': md.contains('广告'),
        '文章标题 "GPT-5"': md.contains('GPT-5'),
        '正文 "推理链"': md.contains('推理链'),
        '正文 "Sam Altman"': md.contains('Sam Altman'),
        '数据表格': md.contains('| MATH-500 |'),
        'Hinton引用': md.contains('Hinton'),
        'OL列表项': md.contains('1. '),
        'UL列表项': md.contains('- API'),
      };

      for (final entry in checks.entries) {
        final isGood = entry.key.startsWith('文章') ||
            entry.key.startsWith('正文') ||
            entry.key.startsWith('数据') ||
            entry.key.startsWith('Hinton') ||
            entry.key.startsWith('OL') ||
            entry.key.startsWith('UL');
        final icon = isGood
            ? (entry.value ? '✓' : '✗ MISSING!')
            : (entry.value ? '✗ LEAKED!' : '✓');
        print('$icon ${entry.key}');
      }

      // Assertions
      // Must keep: actual content
      expect(md.contains('GPT-5'), isTrue);
      expect(md.contains('推理链'), isTrue);
      expect(md.contains('Hinton'), isTrue);
      expect(md.contains('| MATH-500 |'), isTrue);

      // Must remove: boilerplate
      expect(md.contains('首页'), isFalse);
      expect(md.contains('京ICP备'), isFalse);
      expect(md.contains('版权所有'), isFalse);
      expect(md.contains('相关推荐'), isFalse);
    });

    test('STRUCTURE PRESERVATION: tables, lists, headings', () {
      final sanitized = sanitizeHtmlForMarkdownConversion(realNewsHtml);
      final md = convertHtmlToMarkdown(sanitized);

      print('\n========== 结构保留验证 ==========');

      // Headings preserved
      final h1Count = RegExp(r'^# ', multiLine: true).allMatches(md).length;
      final h2Count = RegExp(r'^## ', multiLine: true).allMatches(md).length;
      print('H1 headings: $h1Count');
      print('H2 headings: $h2Count');

      // Table preserved
      final tableRows = RegExp(r'^\|', multiLine: true).allMatches(md).length;
      print('Table rows: $tableRows');

      // Bold preserved
      final boldCount = RegExp(r'\*\*[^*]+\*\*').allMatches(md).length;
      print('Bold segments: $boldCount');

      // Lists preserved
      final ulItems = RegExp(r'^- ', multiLine: true).allMatches(md).length;
      final olItems = RegExp(r'^\d+\. ', multiLine: true).allMatches(md).length;
      print('Unordered list items: $ulItems');
      print('Ordered list items: $olItems');

      // Blockquote preserved
      final bqCount = RegExp(r'^> ', multiLine: true).allMatches(md).length;
      print('Blockquotes: $bqCount');

      expect(h1Count, 1);
      expect(h2Count, 3);
      expect(tableRows, greaterThanOrEqualTo(6));
      expect(boldCount, greaterThanOrEqualTo(2));
      expect(ulItems, greaterThanOrEqualTo(4));
      expect(olItems, greaterThanOrEqualTo(4));
    });
  });
}
