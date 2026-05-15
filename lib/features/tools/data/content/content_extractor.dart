/// Multi-strategy content extraction orchestrator — tiered edition.
///
/// Tier 1 (HTTP): fast Dio fetch with charset-aware decoding.
/// Tier 2 (encoding): re-decode with detected charset when UTF-8 fails.
/// Tier 3 (browser): delegated to ToolExecutor which owns the browser lifecycle.
///   ContentExtractor stays pure — no browser dependency, no Riverpod.
///
/// Pipeline: fetch → HtmlPipeline(parse once, clean once) →
///           metadata+JSON-LD (from original DOM) →
///           markdown + segments (from cleaned DOM) →
///           multi-strategy scoring → best selection →
///           description/YouTube fallback → strip title → budget → result
library;

import 'dart:convert';

import 'package:charset/charset.dart' show eucJp, eucKr, gbk, shiftJis;
import 'package:dio/dio.dart';

import '../../../../shared/utils/content_budget.dart';
import '../../../../shared/utils/text_cleaner.dart';
import '../../../../shared/utils/url_classifier.dart';
import '../../domain/extracted_content.dart';
import 'content_scorer.dart';
import 'html_pipeline.dart';
import 'youtube_extractor.dart';

const _defaultMaxCharacters = 8000;
const _minContentCharacters = 200;
const _minDescriptionCharacters = 120;
const _maxRetries = 2;
const _baseRetryDelayMs = 800;

const _retryableStatuses = {429, 500, 502, 503, 504};

/// Thresholds for detecting SPA / near-empty pages.
const spaShellMaxChars = 200;
const spaShellMinTextRatio = 0.03;

const _userAgentPool = [
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0',
];

int _uaIndex = 0;

const _requestHeaders = {
  'Accept':
      'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
  'Accept-Language': 'en-US,en;q=0.9,zh-CN;q=0.8',
  'Accept-Encoding': 'gzip, deflate, br',
  'Cache-Control': 'no-cache',
  'Pragma': 'no-cache',
  'Sec-Fetch-Dest': 'document',
  'Sec-Fetch-Mode': 'navigate',
  'Sec-Fetch-Site': 'none',
};

final _charsetMetaPattern = RegExp(
  r'''<meta[^>]+charset\s*=\s*["']?([a-zA-Z0-9_-]+)''',
  caseSensitive: false,
);
final _charsetContentTypePattern = RegExp(
  r'charset\s*=\s*([a-zA-Z0-9_-]+)',
  caseSensitive: false,
);

final _leadingControlPattern = RegExp(r'^[\s\p{Cc}]+', unicode: true);
final _spaTagPattern = RegExp(r'</(html|body|head)>', caseSensitive: false);

class ContentExtractor {

  const ContentExtractor({this.maxCharacters = _defaultMaxCharacters});
  final int maxCharacters;

  // ── Tier 1: HTTP fetch (with retry + charset detection) ──

  Future<ExtractedLinkContent> extract(String url) async {
    final (html, _) = await _fetchHtml(url);
    return extractFromHtml(html, url);
  }

  /// Fetch HTML via Dio with retry, UA rotation, and charset-aware decoding.
  /// Returns (html, source) where source describes how the HTML was obtained.
  Future<(String, String)> fetchHtmlForTiered(String url) async {
    return _fetchHtml(url);
  }

  Future<(String, String)> _fetchHtml(String url) async {
    final ua = _nextUA();
    final headers = Map<String, String>.from(_requestHeaders);
    headers['User-Agent'] = ua;

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: headers,
      followRedirects: true,
      maxRedirects: 5,
      responseType: ResponseType.bytes,
      validateStatus: (status) => status != null && status < 500,
    ));

    Response? response;
    Object? lastError;

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        response = await dio.get(url);
        break;
      } on DioException catch (e) {
        lastError = e;
        if (attempt < _maxRetries && _isRetryable(e)) {
          final delay = _baseRetryDelayMs * (1 << attempt);
          final jitter = (delay * 0.25).round();
          await Future<void>.delayed(
            Duration(milliseconds: delay + jitter),
          );
          continue;
        }
        rethrow;
      }
    }

    if (response == null) {
      throw DioException(
        requestOptions: RequestOptions(path: url),
        message:
            'All $_maxRetries retry attempts failed. Last error: $lastError',
      );
    }

    final bytes = response.data is List<int>
        ? response.data as List<int>
        : (response.data as String).codeUnits;

    // Decode with charset awareness
    final contentType = response.headers.value('content-type') ?? '';
    var charset = _extractCharset(contentType);
    var html = _decodeBytes(bytes, charset);

    // If the declared charset produced garbled text, try meta tag
    if (charset == null && _looksGarbled(html)) {
      final metaCharset = _extractCharsetFromHtml(html);
      if (metaCharset != null && metaCharset != charset) {
        charset = metaCharset;
        html = _decodeBytes(bytes, charset);
      }
    }

    // Final fallback: UTF-8 with malformed allowance
    if (_looksGarbled(html) && charset != 'utf-8') {
      try {
        html = utf8.decode(bytes, allowMalformed: true);
        charset = 'utf-8+malformed';
      } catch (_) {}
    }

    // If still looks like binary, throw
    if (html.isEmpty && bytes.isNotEmpty) {
      html = latin1.decode(bytes);
    }

    final source = charset != null ? 'http;charset=$charset' : 'http';
    return (html, source);
  }

  // ── Tier 2 / Tier 3 entry: extract from pre-acquired HTML ──

  Future<ExtractedLinkContent> extractFromHtml(
      String html, String url) async {
    // Build single-pass pipeline (parse + clean once)
    final pipeline = HtmlPipeline(html);

    // Metadata: OG tags + JSON-LD (from original DOM — read-only)
    final ogMeta = pipeline.extractMetadata(url);
    final jsonLd = pipeline.jsonLd;
    final mergedTitle = _pickFirst([jsonLd?.title, ogMeta.title]);
    final mergedDescription =
        _pickFirst([jsonLd?.description, ogMeta.description]);

    // Multi-strategy content from cleaned DOM (single pass)
    final candidates = <({String text, String label})>[];

    final markdown = pipeline.toMarkdown();
    if (markdown.isNotEmpty) {
      candidates.add((text: markdown, label: 'sanitized-markdown'));
    }

    final articleContent = pipeline.toArticleContent();
    if (articleContent.isNotEmpty) {
      candidates.add((text: articleContent, label: 'article-segments'));
    }

    // Score candidates and pick best
    String? bestContent;
    String? bestSource;

    if (candidates.isNotEmpty) {
      final scored = candidates
          .map((c) => (
                text: c.text,
                label: c.label,
                score: scoreContent(c.text, html),
              ))
          .where((s) => s.score.totalChars >= _minContentCharacters)
          .toList()
        ..sort((a, b) => b.score.score.compareTo(a.score.score));

      if (scored.isNotEmpty) {
        bestContent = scored.first.text;
        bestSource = scored.first.label;
      }
    }

    // Fallback: metadata description
    final descCandidate = mergedDescription != null
        ? normalizeForPrompt(mergedDescription)
        : '';
    if (descCandidate.length >= _minDescriptionCharacters &&
        (bestContent == null || bestContent.length < _minContentCharacters)) {
      bestContent = descCandidate;
      bestSource = 'metadata-description';
    }

    // Fallback: plain text
    if (bestContent == null || bestContent.length < 50) {
      final plainText = normalizeForPrompt(pipeline.toPlainText());
      if (plainText.length > (bestContent?.length ?? 0)) {
        bestContent = plainText;
        bestSource = 'plain-text-fallback';
      }
    }

    // SPA/JS-page detection: if all strategies failed, use meta description
    if ((bestContent == null || bestContent.isEmpty) &&
        mergedDescription != null &&
        mergedDescription.isNotEmpty) {
      bestContent = normalizeForPrompt(mergedDescription);
      bestSource = 'spa-fallback-description';
    }

    // YouTube: short description fallback
    if (isYouTubeUrl(url) &&
        (bestContent == null || bestContent.length < _minContentCharacters)) {
      final ytDesc = extractYouTubeShortDescription(html);
      if (ytDesc != null && ytDesc.isNotEmpty) {
        bestContent = normalizeForPrompt(ytDesc);
        bestSource = 'youtube-description';
      }
    }

    // Strip leading title
    bestContent ??= '';
    if (bestSource != null && bestSource.contains('segment')) {
      bestContent =
          _stripLeadingTitle(bestContent, mergedTitle ?? ogMeta.title);
    }

    // Final normalization + budget
    final normalized = normalizeForPrompt(bestContent);
    final budget = applyContentBudget(normalized, maxCharacters);

    return ExtractedLinkContent(
      url: url,
      title: mergedTitle ?? ogMeta.title,
      description: mergedDescription ?? ogMeta.description,
      siteName: ogMeta.siteName,
      publishedDate: ogMeta.publishedDate,
      author: ogMeta.author,
      content: budget.content,
      truncated: budget.truncated,
      totalCharacters: budget.totalCharacters,
      wordCount: budget.wordCount,
    );
  }

  // ── Helpers ──

  /// Detect whether raw HTML looks like an SPA shell (JS-rendered page).
  static bool isSpaShell(String html) {
    if (html.isEmpty) return true;
    if (html.length < spaShellMaxChars) return true;

    // Text ratio: visible text characters / total HTML characters
    final visible =
        html.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'\s+'), '');
    if (visible.length / html.length < spaShellMinTextRatio) return true;

    // Count structural tags — SPA shells typically have very few
    final tagCount = _spaTagPattern.allMatches(html).length;
    if (tagCount < 2) return true;

    return false;
  }

  String? _pickFirst(List<String?> candidates) {
    for (final c in candidates) {
      if (c != null && c.isNotEmpty) return c;
    }
    return null;
  }

  String _stripLeadingTitle(String content, String? title) {
    if (content.isEmpty || title == null || title.trim().isEmpty) {
      return content;
    }
    final normalizedTitle = title.trim();
    final trimmedContent = content.trimLeft();
    if (!trimmedContent
        .toLowerCase()
        .startsWith(normalizedTitle.toLowerCase())) {
      return content;
    }
    return trimmedContent
        .substring(normalizedTitle.length)
        .replaceFirst(_leadingControlPattern, '');
  }

  String? _extractCharset(String contentType) {
    final m = _charsetContentTypePattern.firstMatch(contentType);
    return m?.group(1)?.toLowerCase();
  }

  String? _extractCharsetFromHtml(String html) {
    final m = _charsetMetaPattern.firstMatch(html);
    return m?.group(1)?.toLowerCase();
  }

  String _decodeBytes(List<int> bytes, String? charset) {
    if (charset == null || charset.isEmpty) {
      try {
        return utf8.decode(bytes);
      } catch (_) {
        return latin1.decode(bytes);
      }
    }

    final c = charset.toLowerCase().replaceAll('_', '-');
    switch (c) {
      case 'utf-8':
      case 'utf8':
        try {
          return utf8.decode(bytes);
        } catch (_) {
          return utf8.decode(bytes, allowMalformed: true);
        }
      case 'latin1':
      case 'iso-8859-1':
      case 'iso8859-1':
        return latin1.decode(bytes);
      case 'ascii':
        try {
          return ascii.decode(bytes);
        } catch (_) {
          return latin1.decode(bytes);
        }
      // --- CJK charsets via charset package ---
      case 'gbk':
      case 'gb2312':
      case 'gb18030':
        try {
          return gbk.decode(bytes);
        } catch (_) {
          return gbk.decode(bytes, allowMalformed: true);
        }
      case 'shift-jis':
      case 'shift_jis':
      case 'sjis':
        // shiftJis defaults to _allowMalformed=false; try/catch for safety
        try {
          return shiftJis.decode(bytes);
        } catch (_) {
          return utf8.decode(bytes, allowMalformed: true);
        }
      case 'euc-jp':
      case 'euc_jis':
        try {
          return eucJp.decode(bytes);
        } catch (_) {
          return utf8.decode(bytes, allowMalformed: true);
        }
      case 'euc-kr':
      case 'euc_kr':
      case 'ksc5601':
        // eucKr is pre-instantiated with allowInvalid=true
        try {
          return eucKr.decode(bytes);
        } catch (_) {
          return utf8.decode(bytes, allowMalformed: true);
        }
      // --- Other charset fallback ---
      default:
        // Try UTF-8 first (many sites declare wrong charset)
        try {
          return utf8.decode(bytes);
        } catch (_) {
          // Latin-1 is byte-safe: maps all 256 values, never throws
          return latin1.decode(bytes);
        }
    }
  }

  bool _looksGarbled(String text) {
    if (text.isEmpty) return false;
    // High replacement-character ratio indicates encoding mismatch
    final replacementCount = '�'.allMatches(text).length;
    if (replacementCount > text.length * 0.01) return true;
    // High ratio of unprintable control characters
    var control = 0;
    for (final ch in text.runes) {
      if (ch < 0x20 && ch != 0x09 && ch != 0x0A && ch != 0x0D) control++;
    }
    return control > text.length * 0.05;
  }
}

String _nextUA() {
  _uaIndex = (_uaIndex + 1) % _userAgentPool.length;
  return _userAgentPool[_uaIndex];
}

bool _isRetryable(DioException e) {
  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.connectionError) {
    return true;
  }
  final code = e.response?.statusCode;
  return code != null && _retryableStatuses.contains(code);
}
