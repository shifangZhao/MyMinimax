/// Semantic content scoring — goes beyond summarize's simple length-based selection.
///
/// The TS version just picks whichever extraction method produces more characters.
/// We score content by semantic structure, penalizing boilerplate and preferring
/// well-structured main content.
///
/// Scoring factors:
///   + paragraph count (signal of actual prose)
///   + heading count (signal of structured content)
///   + CJK character density (important for Chinese pages)
///   - high link density (navigation menus)
///   - list-heavy text (menus, sidebars)
///   - boilerplate phrases (cookie notices, "read more", etc.)
///   - very short paragraphs (UI labels, not prose)
library;

const _boilerplateEn = {
  'accept cookies', 'cookie policy', 'privacy policy', 'terms of service',
  'subscribe to our newsletter', 'sign up for our newsletter',
  'click here to', 'read more', 'continue reading', 'share this',
  'follow us on', 'all rights reserved', 'copyright ©', 'powered by',
  'advertisement', 'sponsored content', 'you might also like',
  'related articles', 'recommended for you', 'popular posts',
  'leave a comment', 'comments are closed', 'log in to', 'create an account',
  'forgot password', 'reset your password', 'please enable javascript',
  'your browser does not support', 'this website uses cookies',
  'we use cookies to', 'by continuing to use this site',
};

const _boilerplateZh = {
  '版权所有', '保留所有权利', '京ICP备', '粤ICP备', '沪ICP备',
  '阅读更多', '查看更多', '点击查看', '相关推荐', '猜你喜欢',
  '热门文章', '最新文章', '评论', '发表评论', '登录', '注册',
  '忘记密码', '密码重置', '订阅', '广告', '赞助',
  'Cookie政策', '隐私政策', '使用条款', '免责声明',
  '分享到', '关注我们', '联系客服', '关于我们',
  '扫一扫', '二维码', '微信', '微博', '小程序',
};

class ContentScore {

  const ContentScore({
    required this.text,
    required this.score,
    required this.paragraphCount,
    required this.headingCount,
    required this.totalChars,
    required this.linkDensity,
    required this.cjkCount,
    required this.reasons,
  });
  final String text;
  final double score;
  final int paragraphCount;
  final int headingCount;
  final int totalChars;
  final double linkDensity;
  final int cjkCount;
  final List<String> reasons;
}

ContentScore scoreContent(String text, String? originalHtml) {
  var score = 0.0;
  final reasons = <String>[];
  final totalChars = text.length;

  // Count CJK first (before length check — CJK text is denser)
  final cjkCount = _countCjk(text);
  final cjkRatio = totalChars > 0 ? cjkCount / totalChars : 0;

  // CJK-adjusted minimum: 25 CJK chars ≈ 50 Latin chars
  final effectiveMin = cjkRatio > 0.5 ? 25 : 50;
  if (totalChars < effectiveMin) {
    return ContentScore(
      text: text, score: -100, paragraphCount: 0, headingCount: 0,
      totalChars: totalChars, linkDensity: 1.0, cjkCount: cjkCount,
      reasons: ['Content too short (< $effectiveMin chars)'],
    );
  }

  // ---- Positive signals ----

  // Length bonus (log scale — diminishing returns after ~5000 chars)
  score += _logScale(totalChars, 100, 5000, 30);

  // Paragraph count — split on markdown structure boundaries, not just \n\n
  final paragraphs = _splitMarkdownParagraphs(text);
  final paraCount = paragraphs.length;
  score += paraCount * 2.0;
  if (paraCount >= 3) reasons.add('$paraCount paragraphs');

  // Heading count (structure quality)
  final headings = RegExp(r'^#{1,6} ', multiLine: true).allMatches(text).length;
  score += headings * 4.0;
  if (headings >= 2) reasons.add('$headings headings (well-structured)');

  // Average paragraph length excluding headings (very short = UI labels)
  final contentParas = paragraphs.where((p) => !p.startsWith('#')).toList();
  final avgParaLen = contentParas.isNotEmpty
      ? contentParas.fold<int>(0, (sum, p) => sum + p.length) / contentParas.length
      : totalChars.toDouble();
  if (avgParaLen > 150) {
    score += 10;
    reasons.add('dense prose (avg ${avgParaLen.round()} chars/para)');
  } else if (avgParaLen < 40 && paraCount > 10) {
    score -= 15;
    reasons.add('sparse text (avg ${avgParaLen.round()} chars/para — likely UI)');
  }

  // ---- CJK signals ----
  if (cjkRatio > 0.3) {
    score += 5;
    if (cjkRatio > 0.6) reasons.add('CJK-dominant (${(cjkRatio * 100).round()}%)');
  }

  // ---- Negative signals ----

  // Link density (high link ratio = navigation, not content)
  final linkDensity = originalHtml != null
      ? _estimateLinkDensity(text, originalHtml)
      : 0.0;
  if (linkDensity > 0.3) {
    score -= linkDensity * 25;
    reasons.add('high link density (${(linkDensity * 100).round()}%)');
  }

  // Boilerplate phrase penalty
  final bpCount = _countBoilerplate(text);
  if (bpCount > 0) {
    score -= bpCount * 8.0;
    if (bpCount >= 3) reasons.add('$bpCount boilerplate phrases detected');
  }

  // Excessive list items (menus typically have many <li>)
  final listItemCount = '• '.allMatches(text).length;
  if (listItemCount > 15) {
    score -= (listItemCount - 15) * 1.5;
    if (listItemCount > 25) reasons.add('excessive list items ($listItemCount — likely menu)');
  }

  return ContentScore(
    text: text, score: score, paragraphCount: paraCount,
    headingCount: headings, totalChars: totalChars,
    linkDensity: linkDensity, cjkCount: cjkCount,
    reasons: reasons,
  );
}

/// Score a candidate against [baseline]. Returns true if candidate is better.
bool shouldPrefer(ContentScore candidate, ContentScore baseline) {
  // Huge quality difference
  if (candidate.score > baseline.score + 10) return true;

  // Similar scores but candidate is more structured
  if (candidate.score >= baseline.score - 5 && candidate.headingCount > baseline.headingCount + 1) {
    return true;
  }

  // Candidate has significantly more prose paragraphs
  if (candidate.score >= baseline.score - 5 && candidate.paragraphCount > baseline.paragraphCount * 2) {
    return true;
  }

  return false;
}

bool isLikelyBoilerplate(String text) {
  final score = scoreContent(text, null);
  return score.score < -5 || score.totalChars < 100;
}

double _logScale(num value, num min, num max, double maxScore) {
  if (value <= min) return 0;
  if (value >= max) return maxScore;
  return maxScore * (_log(value / min) / _log(max / min));
}

double _log(num x) {
  final v = x.toDouble();
  var result = 0.0;
  var term = (v - 1) / (v + 1);
  var power = term;
  for (var i = 1; i < 20; i += 2) {
    result += power / i;
    power *= term * term;
  }
  return 2 * result;
}

int _countCjk(String text) {
  var count = 0;
  for (final ch in text.runes) {
    if ((ch >= 0x4E00 && ch <= 0x9FFF) || // CJK Unified
        (ch >= 0x3400 && ch <= 0x4DBF) || // CJK Ext-A
        (ch >= 0x20000 && ch <= 0x2A6DF) || // CJK Ext-B
        (ch >= 0xF900 && ch <= 0xFAFF) || // CJK Compat
        (ch >= 0x3040 && ch <= 0x309F) || // Hiragana
        (ch >= 0x30A0 && ch <= 0x30FF) || // Katakana
        (ch >= 0xAC00 && ch <= 0xD7AF)) { // Hangul
      count++;
    }
  }
  return count;
}

int _countBoilerplate(String text) {
  final lower = text.toLowerCase();
  var count = 0;
  for (final phrase in _boilerplateEn) {
    if (lower.contains(phrase)) count++;
  }
  for (final phrase in _boilerplateZh) {
    if (text.contains(phrase)) count++;
  }
  return count;
}

/// Split markdown text into logical paragraphs using structural boundaries:
/// headings, list items, table rows, blockquotes, code fences, hr, blank lines.
List<String> _splitMarkdownParagraphs(String text) {
  final result = <String>[];
  final lines = text.split('\n');
  var buf = StringBuffer();
  var prevBlank = false;

  for (final line in lines) {
    final trimmed = line.trim();

    // Structural boundary — flush current paragraph
    final isStructural = trimmed.startsWith('#') || // heading
        trimmed.startsWith('> ') || // blockquote
        trimmed.startsWith('|') || // table row
        trimmed.startsWith('```') || // code fence
        trimmed.startsWith('---') || // hr
        trimmed.startsWith('- ') || // unordered list
        RegExp(r'^\d+\. ').hasMatch(trimmed); // ordered list

    if (isStructural) {
      if (buf.isNotEmpty) {
        result.add(buf.toString().trim());
        buf = StringBuffer();
      }
      result.add(trimmed);
      prevBlank = false;
      continue;
    }

    // Blank line — paragraph boundary
    if (trimmed.isEmpty) {
      if (!prevBlank && buf.isNotEmpty) {
        result.add(buf.toString().trim());
        buf = StringBuffer();
        prevBlank = true;
      }
      continue;
    }

    // Continuation of current paragraph
    if (buf.isNotEmpty) buf.write(' ');
    buf.write(trimmed);
    prevBlank = false;
  }

  if (buf.isNotEmpty) result.add(buf.toString().trim());
  return result;
}

double _estimateLinkDensity(String text, String html) {
  // Count Markdown-style links [text](url) in the text output
  final linkMatchCount = RegExp(r'\[([^\]]*)\]\([^)]*\)').allMatches(text).length;
  if (linkMatchCount == 0) return 0;

  final totalChars = text.length;
  if (totalChars == 0) return 0;

  // Rough estimate: each link takes ~30 characters on average
  final linkChars = linkMatchCount * 30;
  return (linkChars / totalChars).clamp(0.0, 1.0);
}
