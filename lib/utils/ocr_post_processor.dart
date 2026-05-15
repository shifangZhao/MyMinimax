// ═══════════════════════════════════════════════════════════════════════
// OCR 后处理器 (OCRPostProcessor)
// 功能: 将 OCR 原始输出转为按阅读顺序排列的段落
// 支持: PaddleOCR / 百度OCR / 通用格式
// 版本: 1.0.0
// ═══════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

// ───────────────────────────────────────────────────────────────
// 1. 数据模型
// ───────────────────────────────────────────────────────────────

/// 二维点
class OcrPoint {
  final double x;
  final double y;
  const OcrPoint(this.x, this.y);
  double distTo(OcrPoint other) => math.sqrt(math.pow(x - other.x, 2) + math.pow(y - other.y, 2));
}

/// OCR 原始检测结果
class OCRBox {
  final String text;
  final double confidence;
  final List<OcrPoint> box;        // 四边形四个点 (顺时针)
  final OcrPoint center;         // 中心点
  final double angle;            // 旋转角度(度)
  final double width;
  final double height;
  final double area;

  OCRBox({
    required this.text,
    required this.confidence,
    required this.box,
    required this.center,
    required this.angle,
    required this.width,
    required this.height,
  }) : area = width * height;

  /// 从 PaddleOCR JSON 解析
  factory OCRBox.fromPaddleJson(Map<String, dynamic> json) {
    final region = json['text_region'] as List? ?? json['box'] as List? ?? [];
    final points = region.map<OcrPoint>((p) {
      if (p is List && p.length >= 2) {
        return OcrPoint(p[0].toDouble(), p[1].toDouble());
      }
      return const OcrPoint(0, 0);
    }).toList();

    double cx = 0, cy = 0;
    for (final p in points) { cx += p.x; cy += p.y; }
    if (points.isNotEmpty) { cx /= points.length; cy /= points.length; }

    double w = 0, h = 0;
    if (points.length >= 4) {
      w = (points[0].distTo(points[1]) + points[2].distTo(points[3])) / 2;
      h = (points[1].distTo(points[2]) + points[3].distTo(points[0])) / 2;
    }

    return OCRBox(
      text: (json['text'] ?? '').toString(),
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      box: points,
      center: OcrPoint(cx, cy),
      angle: (json['angle'] ?? 0.0).toDouble(),
      width: w,
      height: h,
    );
  }

  /// 从百度OCR JSON 解析
  factory OCRBox.fromBaiduJson(Map<String, dynamic> json) {
    final words = json['words']?.toString() ?? '';
    final loc = json['location'] as Map<String, dynamic>? ?? {};
    final l = (loc['left'] ?? 0).toDouble();
    final t = (loc['top'] ?? 0).toDouble();
    final w = (loc['width'] ?? 0).toDouble();
    final h = (loc['height'] ?? 0).toDouble();
    final pts = [OcrPoint(l, t), OcrPoint(l + w, t), OcrPoint(l + w, t + h), OcrPoint(l, t + h)];
    return OCRBox(
      text: words,
      confidence: (json['probability']?['average'] ?? 0.0).toDouble(),
      box: pts,
      center: OcrPoint(l + w / 2, t + h / 2),
      angle: 0,
      width: w,
      height: h,
    );
  }
}

/// 文本行
class TextLine {
  final List<OCRBox> boxes;
  final double avgY;
  final double minX;
  final double maxX;
  final double lineHeight;
  TextLine({
    required this.boxes,
    required this.avgY,
    required this.minX,
    required this.maxX,
    required this.lineHeight,
  });
  String get mergedText => boxes.map((b) => b.text).join('');
  bool get endsWithPunct {
    final t = mergedText.trim();
    if (t.isEmpty) return false;
    return '.。!！?？;；'.contains(t[t.length - 1]);
  }
}

enum ParagraphType { paragraph, heading, list, code, quote }

class Paragraph {
  final ParagraphType type;
  final String content;
  final int? level;
  final List<String>? items;
  final List<OCRBox> rawBoxes;
  Paragraph({
    required this.type,
    required this.content,
    this.level,
    this.items,
    required this.rawBoxes,
  });

  String toMarkdown() {
    switch (type) {
      case ParagraphType.heading:
        return '${'#' * (level ?? 1)} $content';
      case ParagraphType.list:
        return items?.map((i) => '- $i').join('\n') ?? '- $content';
      case ParagraphType.code:
        return '```\n$content\n```';
      case ParagraphType.quote:
        return '> $content';
      default:
        return content;
    }
  }
}

// ───────────────────────────────────────────────────────────────
// 2. 主处理器
// ───────────────────────────────────────────────────────────────

class OCRPostProcessor {
  final double minConfidence;
  final double noiseAreaMin;
  final double noiseAreaMaxRatio;
  final double maxAspectRatio;
  final double minAspectRatio;
  final double lineClusterFactor;
  final double paragraphGapFactor;
  final bool enableMultiColumn;
  final double columnGapRatio;

  OCRPostProcessor({
    this.minConfidence = 0.35,
    this.noiseAreaMin = 50,
    this.noiseAreaMaxRatio = 0.3,
    this.maxAspectRatio = 15,
    this.minAspectRatio = 0.05,
    this.lineClusterFactor = 0.4,
    this.paragraphGapFactor = 1.5,
    this.enableMultiColumn = true,
    this.columnGapRatio = 0.3,
  });

  List<Paragraph> process(
    List<OCRBox> boxes, {
    required double imageWidth,
    required double imageHeight,
  }) {
    if (boxes.isEmpty) return [];
    var filtered = _filterNoise(boxes, imageWidth * imageHeight);
    var sorted =
        enableMultiColumn ? _multiColumnSort(filtered, imageWidth) : _singleColumnSort(filtered);
    var lines = _clusterLines(sorted);
    var paragraphs = _mergeParagraphs(lines);
    return _semanticFix(paragraphs);
  }

  List<OCRBox> _filterNoise(List<OCRBox> boxes, double imgArea) {
    final noiseRe = RegExp(r'^[\s×•❤🎶●🙌☀-➿⭐-⯿ -⁯]+$');
    return boxes.where((b) {
      if (b.confidence < minConfidence) return false;
      if (noiseRe.hasMatch(b.text.trim())) return false;
      if (b.area < noiseAreaMin || b.area > imgArea * noiseAreaMaxRatio) return false;
      final ar = b.width / b.height;
      if (ar > maxAspectRatio || ar < minAspectRatio) return false;
      return true;
    }).toList();
  }

  List<OCRBox> _singleColumnSort(List<OCRBox> boxes) {
    final sorted = List<OCRBox>.from(boxes)
      ..sort((a, b) {
        final dy = a.center.y - b.center.y;
        return dy.abs() > 5 ? dy.sign.toInt() : (a.center.x - b.center.x).sign.toInt();
      });
    return sorted;
  }

  List<OCRBox> _multiColumnSort(List<OCRBox> boxes, double imgW) {
    if (boxes.length < 4) return _singleColumnSort(boxes);
    final sx = List<OCRBox>.from(boxes)
      ..sort((a, b) => a.center.x.compareTo(b.center.x));
    double maxGap = 0;
    int gapIdx = -1;
    for (int i = 1; i < sx.length; i++) {
      final g = sx[i].center.x - sx[i - 1].center.x;
      if (g > maxGap) {
        maxGap = g;
        gapIdx = i;
      }
    }
    if (maxGap > imgW * columnGapRatio && gapIdx > 0) {
      final left = _singleColumnSort(sx.sublist(0, gapIdx));
      final right = _singleColumnSort(sx.sublist(gapIdx));
      return _interleaveByY(left, right);
    }
    return _singleColumnSort(boxes);
  }

  List<OCRBox> _interleaveByY(List<OCRBox> a, List<OCRBox> b) {
    final r = <OCRBox>[];
    int i = 0, j = 0;
    while (i < a.length || j < b.length) {
      if (i >= a.length) {
        r.add(b[j++]);
      } else if (j >= b.length) {
        r.add(a[i++]);
      } else {
        r.add(a[i].center.y <= b[j].center.y ? a[i++] : b[j++]);
      }
    }
    return r;
  }

  List<TextLine> _clusterLines(List<OCRBox> boxes) {
    if (boxes.isEmpty) return [];
    final heights = boxes.map((b) => b.height).toList()..sort();
    final threshold = heights[heights.length ~/ 2] * lineClusterFactor;
    final sorted = List<OCRBox>.from(boxes)
      ..sort((a, b) => a.center.y.compareTo(b.center.y));
    final lines = <TextLine>[];
    final cur = <OCRBox>[];
    double cy = sorted.first.center.y;
    for (final b in sorted) {
      if ((b.center.y - cy).abs() <= threshold) {
        cur.add(b);
      } else {
        if (cur.isNotEmpty) lines.add(_makeLine(cur));
        cur.clear();
        cur.add(b);
        cy = b.center.y;
      }
    }
    if (cur.isNotEmpty) lines.add(_makeLine(cur));
    return lines;
  }

  TextLine _makeLine(List<OCRBox> boxes) {
    boxes.sort((a, b) => a.center.x.compareTo(b.center.x));
    final avgY = boxes.map((b) => b.center.y).reduce((a, b) => a + b) / boxes.length;
    final hs = boxes.map((b) => b.height).toList();
    return TextLine(
      boxes: List.unmodifiable(boxes),
      avgY: avgY,
      minX: boxes.first.center.x - boxes.first.width / 2,
      maxX: boxes.last.center.x + boxes.last.width / 2,
      lineHeight: hs.reduce((a, b) => a + b) / hs.length,
    );
  }

  List<Paragraph> _mergeParagraphs(List<TextLine> lines) {
    if (lines.isEmpty) return [];
    final ps = <Paragraph>[];
    final cur = <TextLine>[lines.first];
    for (int i = 1; i < lines.length; i++) {
      final prev = lines[i - 1];
      final curr = lines[i];
      final gap = curr.avgY - prev.avgY;
      final avgH = (prev.lineHeight + curr.lineHeight) / 2;
      final samePara = gap < avgH * paragraphGapFactor;
      final indent = curr.minX - prev.minX > avgH * 2;
      final heading = curr.lineHeight > avgH * 1.5;
      if (!samePara || indent || prev.endsWithPunct || _isListItem(curr.mergedText) || heading) {
        ps.add(_makeParagraph(cur));
        cur.clear();
      }
      cur.add(curr);
    }
    if (cur.isNotEmpty) ps.add(_makeParagraph(cur));
    return ps;
  }

  bool _isListItem(String t) {
    return RegExp(r'^(\s*[\-\*•]\s+|\s*\d+[\.\)]\s+|\s*[①②③④⑤⑥⑦⑧⑨⑩]\s+)')
        .hasMatch(t.trim());
  }

  Paragraph _makeParagraph(List<TextLine> lines) {
    final boxes = lines.expand((l) => l.boxes).toList();
    final text = lines.map((l) => l.mergedText).join(' ');
    if (lines.length == 1 && lines.first.lineHeight > 30) {
      return Paragraph(
        type: ParagraphType.heading,
        content: text,
        level: lines.first.lineHeight > 40 ? 1 : 2,
        rawBoxes: boxes,
      );
    }
    final items = <String>[];
    var isList = true;
    for (final l in lines) {
      if (_isListItem(l.mergedText)) {
        items.add(l.mergedText.trim());
      } else {
        isList = false;
        break;
      }
    }
    if (isList && items.isNotEmpty) {
      return Paragraph(
        type: ParagraphType.list,
        content: text,
        items: items,
        rawBoxes: boxes,
      );
    }
    return Paragraph(type: ParagraphType.paragraph, content: text, rawBoxes: boxes);
  }

  List<Paragraph> _semanticFix(List<Paragraph> ps) {
    return ps.map((p) {
      var t = p.content;
      t = _fixWordBreaks(t);
      t = _fixCommonErrors(t);
      return Paragraph(
        type: p.type,
        content: t,
        level: p.level,
        items: p.items,
        rawBoxes: p.rawBoxes,
      );
    }).toList();
  }

  String _fixWordBreaks(String text) {
    return text.replaceAllMapped(RegExp(r'([a-zA-Z]{2,})\s+([a-zA-Z]{2,})'), (m) {
      final c = m.group(1)! + m.group(2)!;
      return _isCommonWord(c.toLowerCase()) ? c : m.group(0)!;
    });
  }

  static final _commonWords = {
    'flutter',
    'android',
    'ios',
    'dart',
    'python',
    'java',
    'kotlin',
    'javascript',
    'typescript',
    'react',
    'vue',
    'angular',
    'function',
    'class',
    'import',
    'export',
    'return',
    'string',
    'number',
    'boolean',
    'array',
    'object',
    'container',
    'widget',
    'state',
    'builder',
    'future',
    'async',
    'await',
    'stream',
    'listener',
    'provider',
  };

  bool _isCommonWord(String w) => _commonWords.contains(w);

  String _fixCommonErrors(String text) {
    final corrections = {
      'Flutte r': 'Flutter',
      'Andro id': 'Android',
      'lOS': 'iOS',
      'Pytho n': 'Python',
      'Jav a': 'Java',
      'Kotli n': 'Kotlin',
    };
    corrections.forEach((k, v) {
      text = text.replaceAll(k, v);
    });
    return text;
  }
}

// ───────────────────────────────────────────────────────────────
// 3. 便捷入口
// ───────────────────────────────────────────────────────────────

class OCRProcessor {
  static final _p = OCRPostProcessor();

  static List<Paragraph> fromPaddleJson(
    Map<String, dynamic> json, {
    required double imageWidth,
    required double imageHeight,
  }) {
    final texts = json['texts'] as List? ?? json['result'] as List? ?? [];
    return _p.process(
      texts.map((e) => OCRBox.fromPaddleJson(e as Map<String, dynamic>)).toList(),
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
  }

  static List<Paragraph> fromBaiduJson(
    Map<String, dynamic> json, {
    required double imageWidth,
    required double imageHeight,
  }) {
    final results = json['words_result'] as List? ?? [];
    return _p.process(
      results.map((e) => OCRBox.fromBaiduJson(e as Map<String, dynamic>)).toList(),
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
  }

  static List<Paragraph> process(
    List<OCRBox> boxes, {
    required double imageWidth,
    required double imageHeight,
  }) {
    return _p.process(boxes, imageWidth: imageWidth, imageHeight: imageHeight);
  }

  static String toMarkdown(List<Paragraph> ps) {
    return ps.map((p) => p.toMarkdown()).join('\n\n');
  }
}