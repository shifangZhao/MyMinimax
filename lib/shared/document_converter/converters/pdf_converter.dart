import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import '../domain/document_converter_interface.dart';
import '../domain/document_converter_result.dart';
import '../document_converter.dart' show kCancelToken;
import '../services/cancellation_token.dart';
import '../services/pdf_native_bridge.dart';
import '../services/pdf_ocr_bridge.dart';

typedef VisionCallback = Future<String> Function(Uint8List imageBytes);

/// A positioned word extracted from a PDF page.
class _PdfWord {
  _PdfWord({required this.text, required this.x0, required this.x1, required this.top});
  final String text;
  final double x0;
  final double x1;
  final double top;
}

/// Pattern for MasterFormat-style partial numbering (e.g., ".1", ".2", ".10")
final _partialNumberingPattern = RegExp(r'^\.\d+$');

class PdfConverter extends BaseDocumentConverter {
  @override
  int get priority => ConverterPriority.specific;

  @override
  List<String> get supportedMimeTypes => const ['application/pdf', 'application/x-pdf'];

  @override
  List<String> get supportedExtensions => const ['.pdf'];

  @override
  String get formatName => 'PDF';

  /// Image description callback — used ONLY for image-only pages that OCR cannot read.
  /// No longer used for text OCR (PaddleOCR handles that).
  static VisionCallback? visionCallback;

  /// LLM structuring — raw page text → clean Markdown. Called once for the entire document.
  static Future<String> Function(String markdown)? llmCleanup;

  /// Progress callback — called per page during OCR/extraction loops.
  /// [current] is 1-based, [total] is the total page count.
  static void Function(int current, int total)? onProgress;

  /// Stage 1: Simple transcription prompt for Vision API (image description only).
  static const visionPrompt =
      'Describe the content of this image concisely. '
      'Focus on what is shown — charts, diagrams, photos, logos. '
      'If the image contains text, transcribe it. '
      'Output in plain text, no markdown formatting.';

  /// Stage 2: Structuring prompt sent to the chat LLM.
  static const structurePrompt =
      'You are a document restoration expert. '
      'Convert the following raw OCR transcription into clean, well-organized Markdown.\n'
      'Rules:\n'
      '- Add proper # ## ### heading levels based on context and position.\n'
      '- Format tables using pipe syntax: | col | col |\n'
      '- Format lists with - or 1.\n'
      '- Fix obvious OCR errors (spelling, split words, missing spaces).\n'
      '- Remove transcription artifacts (page numbers, headers/footers if repetitive).\n'
      '- Preserve ALL factual content. Do not summarize.\n'
      '- For image/chart descriptions in [brackets], keep them as-is.\n'
      '- Output ONLY the final Markdown. No commentary.';

  @override
  Future<DocumentConverterResult> convert({
    required Uint8List bytes,
    String? mimeType,
    String? fileName,
    Map<String, dynamic>? options,
  }) async {
    final maxPages = (options?['maxPages'] as int?) ?? 0; // 0 = no limit
    final cancelToken = options?[kCancelToken] as CancellationToken?;
    String method = 'unknown';

    cancelToken?.throwIfCancelled();

    // ─── Tier 0: PaddleOCR OCR (primary — free, unlimited, offline) ───
    if (PdfOcrBridge.isSupported && PdfNativeBridge.isSupported) {
      try {
        final result = await _ocrExtract(bytes, maxPages, cancelToken);
        if (result != null) {
          var md = result;
          // Post-process: detect tables and merge partial numbering
          md = _detectTablesFromPlainText(md);
          md = _mergePartialNumberingLines(md);
          // Single LLM structuring pass
          if (llmCleanup != null && (options?['skipLlmCleanup'] != true)) {
            try {
              md = await llmCleanup!(md);
              method = 'paddleocr+llm';
            } catch (e) {
              debugPrint('PdfConverter: PaddleOCR LLM cleanup failed: $e');
              method = 'paddleocr';
            }
          } else {
            method = 'paddleocr';
          }
          return DocumentConverterResult(
            markdownContent: md,
            mimeType: mimeType,
            detectedFormat: 'pdf',
            metadata: {'method': method, 'maxPages': maxPages, 'ocr': 'paddleocr-ncnn'},
          );
        }
      } catch (e) {
        debugPrint('PdfConverter: PaddleOCR extraction failed, falling back to Tier 1: $e');
      }
    }

    // ─── Tier 1: Vision OCR fallback (per-page API calls — for non-Android or OCR failure) ───
    if (visionCallback != null && PdfNativeBridge.isSupported) {
      final result = await _visionFirstExtract(bytes, maxPages, cancelToken);
      if (result != null) {
        var md = result;
        // Post-process: detect tables and merge partial numbering
        md = _detectTablesFromPlainText(md);
        md = _mergePartialNumberingLines(md);
        if (llmCleanup != null) {
          try {
            md = await llmCleanup!(md);
            method = 'vision-ocr+llm';
          } catch (e) {
            debugPrint('PdfConverter: Vision OCR LLM cleanup failed: $e');
            method = 'vision-ocr';
          }
        } else {
          method = 'vision-ocr';
        }
        return DocumentConverterResult(
          markdownContent: md,
          mimeType: mimeType,
          detectedFormat: 'pdf',
          metadata: {'method': method},
        );
      }
    }

    // ─── Tier 2: Dart regex extraction (last resort — no rendering needed) ───
    String dartText;
    try {
      dartText = _extractTextDart(bytes);
      if (dartText.trim().isNotEmpty) {
        // Post-process: detect tables in plain text, merge partial numbering
        dartText = _detectTablesFromPlainText(dartText);
        dartText = _mergePartialNumberingLines(dartText);
        method = 'dart-regex';
        if (llmCleanup != null) {
          try {
            dartText = await llmCleanup!(dartText);
            method = 'dart-regex+llm';
          } catch (e) { debugPrint('PdfConverter: Dart regex LLM cleanup failed: $e'); }
            print('[pdf] error: \$e');
        }
      } else {
        dartText = '*No readable text found in this PDF. '
            'It may be a scanned/image-based PDF.*\n';
        method = 'dart-regex-empty';
      }
    } catch (e) {
      debugPrint('PdfConverter: Dart text extraction failed: $e');
      dartText = '*Failed to extract text from this PDF.*\n';
      method = 'failed';
    }

    return DocumentConverterResult(
      markdownContent: dartText,
      mimeType: mimeType,
      detectedFormat: 'pdf',
      metadata: {'method': method},
    );
  }

  // ─── Tier 0: PaddleOCR OCR extraction ─────────────────────────────────────

  /// Render pages to PNG, run PaddleOCR on each, combine results.
  Future<String?> _ocrExtract(Uint8List bytes, int maxPages, CancellationToken? cancelToken) async {
    // Ensure the native OCR model is loaded before first use
    if (!await PdfOcrBridge.ensureLoaded()) return null;

    final pageFiles = await PdfNativeBridge.renderPagesToFiles(bytes, maxPages: maxPages);
    if (pageFiles.isEmpty) return null;

    final ocrBridge = PdfOcrBridge();
    final results = <String>[];
    final isMultiPage = pageFiles.length > 1;
    int imageOnlyPages = 0;

    for (int i = 0; i < pageFiles.length; i++) {
      cancelToken?.throwIfCancelled();
      onProgress?.call(i + 1, pageFiles.length);
      final ocrResult = await ocrBridge.recognizeFile(pageFiles[i], pageIndex: i);

      if (ocrResult.hasText) {
        if (isMultiPage) {
          results.add('## Page ${i + 1}\n\n${ocrResult.text}');
        } else {
          results.add(ocrResult.text);
        }
      } else {
        // OCR produced no text — possibly an image-only page
        final imageDescription = await _tryImageDescription(bytes, pageFiles[i], i);
        if (imageDescription != null) {
          if (isMultiPage) {
            results.add('## Page ${i + 1}\n\n[Image: $imageDescription]');
          } else {
            results.add('[Image: $imageDescription]');
          }
          imageOnlyPages++;
        }
      }
    }

    // Clean up temp files
    for (final f in pageFiles) {
      try { await File(f).delete(); } catch (e) { debugPrint('PdfConverter: Failed to delete temp file $f: $e'); }
        print('[pdf] error: \$e');
    }

    if (results.isEmpty) return null;

    final combined = results.join('\n\n---\n\n');
    final pagesNote = '${pageFiles.length - imageOnlyPages} text pages, $imageOnlyPages image pages';
    return '$combined\n\n*Extracted via PaddleOCR ($pagesNote).*\n';
  }

  /// Try Vision API to describe an image-only page.
  Future<String?> _tryImageDescription(Uint8List pdfBytes, String pngPath, int pageIndex) async {
    if (visionCallback == null) return null;

    // Check if PDF contains image streams for this page
    if (!_pageHasImages(pdfBytes)) return null;

    try {
      final pngBytes = await File(pngPath).readAsBytes();
      return await visionCallback!(pngBytes);
    } catch (e) {
      debugPrint('PdfConverter: Vision image description failed for page $pageIndex: $e');
      return null;
    }
  }

  /// Check if PDF contains embedded images by scanning bytes directly
  /// Check if PDF contains embedded images by scanning bytes directly
  /// instead of decoding the entire file to a string.
  bool _pageHasImages(Uint8List bytes) {
    try {
      // Only scan a prefix — image resources are declared early in the PDF
      const search = '/Subtype /Image';
      final limit = bytes.length < 200000 ? bytes.length : 200000;
      for (int i = 0; i <= limit - search.length; i++) {
        bool match = true;
        for (int j = 0; j < search.length; j++) {
          if (bytes[i + j] != search.codeUnitAt(j)) {
            match = false;
            break;
          }
        }
        if (match) return true;
      }
      return false;
    } catch (e) {
      debugPrint('PdfConverter: Image detection failed: $e');
      return false;
    }
  }

  // ─── Tier 1: Vision-first extraction (fallback, kept for non-Android) ───

  Future<String?> _visionFirstExtract(Uint8List bytes, int maxPages, CancellationToken? cancelToken) async {
    final pages = await PdfNativeBridge.renderPagesFromBytes(bytes, maxPages: maxPages);
    if (pages.isEmpty) return null;

    final results = <String>[];
    final isMultiPage = pages.length > 1;

    for (int i = 0; i < pages.length; i++) {
      cancelToken?.throwIfCancelled();
      onProgress?.call(i + 1, pages.length);
      try {
        var text = await visionCallback!(pages[i]);
        if (text.trim().isEmpty) continue;
        if (isMultiPage) {
          results.add('## Page ${i + 1}\n\n$text');
        } else {
          results.add(text);
        }
      } catch (e) { debugPrint('PdfConverter: Vision OCR failed for page ${i + 1}: $e'); }
        print('[pdf] error: \$e');
    }

    if (results.isEmpty) return null;

    final combined = results.join('\n\n---\n\n');
    return '$combined\n\n*Extracted via Vision OCR from ${pages.length} page(s).*\n';
  }

  // ─── Tier 2: Dart-based regex extraction with table/position detection ──

  String _extractTextDart(Uint8List bytes) {
    try {
      return _extractFromPdfBytes(bytes);
    } catch (e) {
      debugPrint('PdfConverter: Binary extraction failed, trying text fallback: $e');
      final content = latin1.decode(bytes);
      return _extractFromText(content);
    }
  }

  String _extractFromPdfBytes(Uint8List bytes) {
    const maxSize = 4 * 1024 * 1024; // 4 MB
    final Uint8List processBytes;
    if (bytes.length > maxSize) {
      processBytes = bytes.sublist(0, maxSize);
    } else {
      processBytes = bytes;
    }
    final content = latin1.decode(processBytes);

    // Collect all decompressed page streams
    final pageStreams = <String>[];
    final filterPattern = RegExp(r'/Filter\s*/FlateDecode');
    final objPattern = RegExp(r'(\d+ \d+ obj.*?endobj)', dotAll: true);

    for (final objMatch in objPattern.allMatches(content)) {
      final objContent = objMatch.group(1)!;
      final hasFlate = filterPattern.hasMatch(objContent);
      final streamMatch =
          RegExp(r'stream\r?\n(.*?)endstream', dotAll: true).firstMatch(objContent);
      if (streamMatch == null) continue;

      var streamData = streamMatch.group(1)!;
      if (streamData.endsWith('\r\n')) {
        streamData = streamData.substring(0, streamData.length - 2);
      } else if (streamData.endsWith('\n')) {
        streamData = streamData.substring(0, streamData.length - 1);
      }

      if (hasFlate) {
        try {
          final decompressed =
              const ZLibDecoder().decodeBytes(streamData.codeUnits);
          pageStreams.add(latin1.decode(Uint8List.fromList(decompressed)));
        } catch (e) {
          print('[pdf] error: \$e');
          pageStreams.add(streamData);
        }
      } else {
        pageStreams.add(streamData);
      }
    }

    // Try position-based table extraction first
    if (pageStreams.isNotEmpty) {
      final results = <String>[];
      for (final streamContent in pageStreams) {
        final words = _extractWordsWithPositions(streamContent);
        if (words.isNotEmpty) {
          final formContent = _extractFormContentFromWords(words);
          if (formContent != null) {
            results.add(formContent);
          } else {
            results.add(_extractFromText(streamContent));
          }
        } else {
          final text = _extractFromText(streamContent);
          if (text.trim().isNotEmpty) results.add(text);
        }
      }
      if (results.isNotEmpty) return results.join('\n\n');
    }

    // Fall back to simple text extraction
    final result = _extractFromText(content).trim();
    if (result.isEmpty) {
      throw Exception('No extractable text found in PDF (possibly a scanned/image-based PDF)');
    }
    return result;
  }

  /// Extract words with their positions from a PDF content stream.
  /// Tracks Tm (text matrix), Tf (font size), and Td/TD (position moves).
  /// Uses font-size-aware character width estimation instead of a fixed 6pt.
  List<_PdfWord> _extractWordsWithPositions(String content) {
    final words = <_PdfWord>[];
    double tx = 0, ty = 0;
    double fontSize = 12; // default, updated by Tf operator

    // text matrix: a b c d e f  where e=tx, f=ty
    final tmPattern = RegExp(r'([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)\s+Tm');
    // font selection: /F1 12 Tf  or  /Helvetica 10 Tf
    final tfPattern = RegExp(r'/(\w+)\s+([\d.]+)\s+Tf');

    double charWidth() => fontSize * 0.6; // avg char width at current font size

    int i = 0;
    final len = content.length;

    String remaining() => content.substring(i);

    while (i < len) {
      final rest = remaining();

      // Check for Tf (font selection) to update fontSize
      final tfMatch = tfPattern.firstMatch(rest);
      if (tfMatch != null && tfMatch.start == 0) {
        fontSize = double.tryParse(tfMatch.group(2)!) ?? fontSize;
        i += tfMatch.end;
        continue;
      }

      // Check for Tm (text matrix) to update position
      final tmMatch = tmPattern.firstMatch(rest);
      if (tmMatch != null) {
        // Process text before this Tm using current positions
        final before = rest.substring(0, tmMatch.start);
        _extractTextOps(before, tx, ty, charWidth, words, fontSize);
        tx = double.tryParse(tmMatch.group(5)!) ?? tx;
        ty = double.tryParse(tmMatch.group(6)!) ?? ty;
        i += tmMatch.end;
        continue;
      }

      // No more Tm operators; process remainder
      _extractTextOps(rest, tx, ty, charWidth, words, fontSize);
      break;
    }

    return words;
  }

  void _extractTextOps(String content, double tx, double ty, double Function() charWidth, List<_PdfWord> words, double fontSize) {
    final cw = charWidth();

    void addWord(String text) {
      text = _unescapePdfText(text).trim();
      if (text.isNotEmpty) {
        words.add(_PdfWord(
          text: text,
          x0: tx,
          x1: tx + text.length * cw,
          top: ty,
        ));
        tx += text.length * cw + cw * 0.3; // word spacing
      }
    }

    // Td: tx ty Td — relative move
    final tdPattern = RegExp(r'([\d.\-]+)\s+([\d.\-]+)\s+Td');
    tdPattern.allMatches(content).forEach((m) {
      tx += double.tryParse(m.group(1)!) ?? 0;
      ty += double.tryParse(m.group(2)!) ?? 0;
    });

    // TD: tx ty TD — move with leading
    final td2Pattern = RegExp(r'([\d.\-]+)\s+([\d.\-]+)\s+TD');
    td2Pattern.allMatches(content).forEach((m) {
      tx += double.tryParse(m.group(1)!) ?? 0;
      ty += double.tryParse(m.group(2)!) ?? 0;
    });

    // T*: next line
    RegExp(r'T\*').allMatches(content).forEach((_) {
      tx = 0;
      ty -= cw * 2; // approx line height
    });

    // Tj: (text) Tj
    final tjPattern = RegExp(r'\(((?:[^()]|\\[()\nrt\\]|\\[0-7]{1,3})*)\)\s*Tj');
    for (final m in tjPattern.allMatches(content)) {
      addWord(m.group(1)!);
    }

    // ': (text) ' — move to next line, show text
    final quotePattern = RegExp(r"\(((?:[^()]|\\[()\nrt\\]|\\[0-7]{1,3})*)\)\s*'");
    for (final m in quotePattern.allMatches(content)) {
      addWord(m.group(1)!);
      tx = 0;
      ty -= cw * 2;
    }

    // ": (text) " — set spacing, move to next line, show text
    final dquotePattern = RegExp(r'\(((?:[^()]|\\[()\nrt\\]|\\[0-7]{1,3})*)\)\s*"');
    for (final m in dquotePattern.allMatches(content)) {
      addWord(m.group(1)!);
      tx = 0;
      ty -= cw * 2;
    }

    // TJ: [ elements ] TJ — array of strings and numeric adjustments
    final tjArrayPattern = RegExp(r'\[(.*?)\]\s*TJ', dotAll: true);
    for (final arrMatch in tjArrayPattern.allMatches(content)) {
      final arrContent = arrMatch.group(1)!;
      // Parse elements in order: strings and numbers interleaved
      final elemPattern = RegExp(r'\(((?:[^()]|\\[()\nrt\\]|\\[0-7]{1,3})*)\)|([\d.\-]+)');
      for (final em in elemPattern.allMatches(arrContent)) {
        if (em.group(1) != null) {
          // Text element
          final text = _unescapePdfText(em.group(1)!).trim();
          if (text.isNotEmpty) {
            words.add(_PdfWord(
              text: text,
              x0: tx,
              x1: tx + text.length * cw,
              top: ty,
            ));
          }
          tx += text.length * cw;
        } else if (em.group(2) != null) {
          // Numeric adjustment (kerning/spacing in 1/1000 em)
          final adj = double.tryParse(em.group(2)!) ?? 0;
          tx += adj / 1000 * fontSize;
        }
      }
    }
  }

  /// Port of markitdown's _extract_form_content_from_words algorithm.
  /// Groups words by Y-position, detects global column boundaries using
  /// adaptive gap analysis, classifies rows as table/paragraph, and outputs
  /// aligned Markdown tables for table regions.
  String? _extractFormContentFromWords(List<_PdfWord> words) {
    if (words.isEmpty) return null;

    // Group words by Y position
    const yTolerance = 5.0;
    final rowsByY = <double, List<_PdfWord>>{};
    for (final w in words) {
      final yKey = (w.top / yTolerance).round() * yTolerance;
      rowsByY.putIfAbsent(yKey, () => []);
      rowsByY[yKey]!.add(w);
    }

    final sortedYKeys = rowsByY.keys.toList()..sort();
    const pageWidth = 612.0; // standard letter width in points

    // First pass: analyze each row
    final rowInfo = <_RowInfo>[];
    for (final yKey in sortedYKeys) {
      final rowWords = rowsByY[yKey]!;
      rowWords.sort((a, b) => a.x0.compareTo(b.x0));
      if (rowWords.isEmpty) continue;

      final firstX0 = rowWords.first.x0;
      final lastX1 = rowWords.last.x1;
      final lineWidth = lastX1 - firstX0;
      final combinedText = rowWords.map((w) => w.text).join(' ');

      // Count distinct x-position groups
      final xPositions = rowWords.map((w) => w.x0).toList()..sort();
      final xGroups = <double>[];
      for (final x in xPositions) {
        if (xGroups.isEmpty || x - xGroups.last > 50) xGroups.add(x);
      }

      final isParagraph = lineWidth > pageWidth * 0.55 && combinedText.length > 60;
      final hasPartialNumbering = rowWords.isNotEmpty &&
          _partialNumberingPattern.hasMatch(rowWords.first.text.trim());

      rowInfo.add(_RowInfo(
        yKey: yKey,
        words: rowWords,
        text: combinedText,
        xGroups: xGroups,
        isParagraph: isParagraph,
        numColumns: xGroups.length,
        hasPartialNumbering: hasPartialNumbering,
      ));
    }

    if (rowInfo.isEmpty) return null;

    // Collect all x-positions from rows with 3+ columns
    final allTableXPositions = <double>[];
    for (final info in rowInfo) {
      if (info.numColumns >= 3 && !info.isParagraph) {
        allTableXPositions.addAll(info.xGroups);
      }
    }

    if (allTableXPositions.isEmpty) return null;

    allTableXPositions.sort();

    // Compute adaptive tolerance from gap analysis
    final gaps = <double>[];
    for (int i = 0; i < allTableXPositions.length - 1; i++) {
      final gap = allTableXPositions[i + 1] - allTableXPositions[i];
      if (gap > 5) gaps.add(gap);
    }

    final double adaptiveTolerance;
    if (gaps.length >= 3) {
      final sortedGaps = gaps.toList()..sort();
      final p70Idx = (sortedGaps.length * 0.70).round();
      adaptiveTolerance = sortedGaps[p70Idx].clamp(25, 50);
    } else {
      adaptiveTolerance = 35;
    }

    // Compute global column boundaries
    final globalColumns = <double>[];
    for (final x in allTableXPositions) {
      if (globalColumns.isEmpty || x - globalColumns.last > adaptiveTolerance) {
        globalColumns.add(x);
      }
    }

    // Validate column count
    if (globalColumns.length < 2) return null;
    if (globalColumns.length > 1) {
      final contentWidth = globalColumns.last - globalColumns.first;
      final avgColWidth = contentWidth / globalColumns.length;
      if (avgColWidth < 30) return null;

      final columnsPerInch = globalColumns.length / (contentWidth / 72);
      if (columnsPerInch > 10) return null;

      final adaptiveMaxColumns = (20 * (pageWidth / 612)).round().clamp(15, 50);
      if (globalColumns.length > adaptiveMaxColumns) return null;
    }

    // Classify rows as table or not
    for (final info in rowInfo) {
      if (info.isParagraph || info.hasPartialNumbering) {
        info.isTableRow = false;
        continue;
      }

      final alignedColumns = <int>{};
      for (final word in info.words) {
        for (int colIdx = 0; colIdx < globalColumns.length; colIdx++) {
          if ((word.x0 - globalColumns[colIdx]).abs() < 40) {
            alignedColumns.add(colIdx);
            break;
          }
        }
      }
      info.isTableRow = alignedColumns.length >= 2;
    }

    // Find table regions (consecutive table rows)
    final tableRegions = <(int, int)>[];
    int ri = 0;
    while (ri < rowInfo.length) {
      if (rowInfo[ri].isTableRow) {
        final start = ri;
        while (ri < rowInfo.length && rowInfo[ri].isTableRow) { ri++; }
        tableRegions.add((start, ri));
      } else {
        ri++;
      }
    }

    // At least 20% of rows must be table rows
    final totalTableRows = tableRegions.fold<int>(0, (sum, r) => sum + (r.$2 - r.$1));
    if (rowInfo.isNotEmpty && totalTableRows / rowInfo.length < 0.2) return null;

    // Build output
    final resultLines = <String>[];
    final numCols = globalColumns.length;

    List<String> extractCells(_RowInfo info) {
      final cells = List.filled(numCols, '');
      for (final word in info.words) {
        int assignedCol = numCols - 1;
        for (int colIdx = 0; colIdx < numCols - 1; colIdx++) {
          if (word.x0 < globalColumns[colIdx + 1] - 20) {
            assignedCol = colIdx;
            break;
          }
        }
        cells[assignedCol] = cells[assignedCol].isEmpty ? word.text : '${cells[assignedCol]} ${word.text}';
      }
      return cells;
    }

    int idx = 0;
    while (idx < rowInfo.length) {
      final info = rowInfo[idx];

      (int, int)? tableRegion;
      for (final tr in tableRegions) {
        if (idx == tr.$1) { tableRegion = tr; break; }
      }

      if (tableRegion != null) {
        final (start, end) = tableRegion;
        final tableData = <List<String>>[];
        for (int ti = start; ti < end; ti++) {
          tableData.add(extractCells(rowInfo[ti]));
        }

        if (tableData.isNotEmpty) {
          final colWidths = List.filled(numCols, 0);
          for (final row in tableData) {
            for (int c = 0; c < numCols; c++) {
              colWidths[c] = math.max(colWidths[c], row[c].length);
            }
          }
          final header = tableData[0];
          resultLines.add('| ${header.asMap().entries.map((e) => e.value.padRight(colWidths[e.key])).join(' | ')} |');
          resultLines.add('| ${colWidths.map((w) => '-' * w).join(' | ')} |');
          for (int ri = 1; ri < tableData.length; ri++) {
            resultLines.add('| ${tableData[ri].asMap().entries.map((e) => e.value.padRight(colWidths[e.key])).join(' | ')} |');
          }
        }
        idx = end;
      } else {
        bool inTable = false;
        for (final tr in tableRegions) {
          if (tr.$1 < idx && idx < tr.$2) { inTable = true; break; }
        }
        if (!inTable) resultLines.add(info.text);
        idx++;
      }
    }

    final output = resultLines.join('\n').trim();
    return output.isNotEmpty ? output : null;
  }

  /// Fallback table detection for plain text (OCR / Vision output).
  /// Detects whitespace-aligned columns and converts to Markdown tables.
  String _detectTablesFromPlainText(String text) {
    final lines = text.split('\n');
    if (lines.length < 3) return text;

    // Find blocks of consecutive lines with consistent gap patterns
    final result = <String>[];
    int i = 0;
    while (i < lines.length) {
      final line = lines[i];
      // Check if this line looks like it could be part of a table
      // (multiple whitespace-separated tokens that align with adjacent lines)
      final tokens = line.split(RegExp(r'\s{2,}')).where((t) => t.trim().isNotEmpty).toList();

      if (tokens.length >= 3 && i + 2 < lines.length) {
        // Check if next lines have similar token counts
        final nextLine = lines[i + 1];
        final nextTokens = nextLine.split(RegExp(r'\s{2,}')).where((t) => t.trim().isNotEmpty).toList();

        if (nextTokens.length >= 3 && (nextTokens.length - tokens.length).abs() <= 2) {
          // This might be a table - collect consecutive similar lines
          final tableLines = <List<String>>[];
          int j = i;
          while (j < lines.length) {
            final tl = lines[j].split(RegExp(r'\s{2,}')).where((t) => t.trim().isNotEmpty).toList();
            if (tl.length < 2) break; // stop at single-token or empty lines
            // Stop if token count changes drastically
            if (tableLines.isNotEmpty && (tl.length - tableLines.first.length).abs() > 3) break;
            tableLines.add(tl);
            j++;
          }

          if (tableLines.length >= 3) {
            // Convert to Markdown table
            final colCount = tableLines.fold<int>(0, (mx, r) => math.max(mx, r.length));
            // Normalize
            for (final row in tableLines) {
              while (row.length < colCount) { row.add(''); }
            }

            final buf = StringBuffer();
            buf.writeln();
            buf.writeln('| ${tableLines[0].join(' | ')} |');
            buf.writeln('| ${List.filled(colCount, '---').join(' | ')} |');
            for (int ri = 1; ri < tableLines.length; ri++) {
              buf.writeln('| ${tableLines[ri].join(' | ')} |');
            }
            buf.writeln();
            result.add(buf.toString());
            i = j;
            continue;
          }
        }
      }
      result.add(line);
      i++;
    }

    return result.join('\n');
  }

  /// Merge MasterFormat-style partial numbering with following text lines.
  /// e.g., ".1" + "The intent of this Request..." → ".1 The intent of this Request..."
  String _mergePartialNumberingLines(String text) {
    final lines = text.split('\n');
    final resultLines = <String>[];
    int i = 0;

    while (i < lines.length) {
      final line = lines[i];
      final stripped = line.trim();

      if (_partialNumberingPattern.hasMatch(stripped)) {
        int j = i + 1;
        while (j < lines.length && lines[j].trim().isEmpty) { j++; }

        if (j < lines.length) {
          resultLines.add('$stripped ${lines[j].trim()}');
          i = j + 1;
        } else {
          resultLines.add(line);
          i++;
        }
      } else {
        resultLines.add(line);
        i++;
      }
    }

    return resultLines.join('\n');
  }

  /// Convert a 2D list into an aligned Markdown table.
  String _toMarkdownTable(List<List<String>> table, {bool includeSeparator = true}) {
    if (table.isEmpty) return '';
    var normalized = table.map((row) => row.map((c) => c ?? '').toList()).toList();
    normalized = normalized.where((row) => row.any((c) => c.trim().isNotEmpty)).toList();
    if (normalized.isEmpty) return '';

    final colWidths = <int>[];
    for (int c = 0; c < normalized[0].length; c++) {
      int maxW = 3;
      for (final row in normalized) {
        if (c < row.length) maxW = math.max(maxW, row[c].length);
      }
      colWidths.add(maxW);
    }

    final buf = StringBuffer();
    if (includeSeparator && normalized.length >= 2) {
      buf.writeln('| ${normalized[0].asMap().entries.map((e) => e.value.padRight(colWidths[e.key])).join(' | ')} |');
      buf.writeln('| ${colWidths.map((w) => '-' * w).join(' | ')} |');
      for (int r = 1; r < normalized.length; r++) {
        buf.writeln('| ${normalized[r].asMap().entries.map((e) => e.value.padRight(colWidths[e.key])).join(' | ')} |');
      }
    } else {
      for (final row in normalized) {
        buf.writeln('| ${row.asMap().entries.map((e) => e.value.padRight(colWidths[e.key])).join(' | ')} |');
      }
    }
    return buf.toString();
  }

  String _extractFromText(String content) {
    final textBlocks = <String>[];
    final btPattern = RegExp(r'BT\s*(.*?)\s*ET', dotAll: true);

    for (final match in btPattern.allMatches(content)) {
      final block = match.group(1)!;
      _findPdfStrings(block, 'Tj', textBlocks);
      _findPdfStrings(block, "'", textBlocks);
      _findPdfStrings(block, '"', textBlocks);

      final tjArrayPattern = RegExp(r'\[(.*?)\]\s*TJ', dotAll: true);
      for (final tjArray in tjArrayPattern.allMatches(block)) {
        for (final s in _extractParenStrings(tjArray.group(1)!)) {
          final text = _unescapePdfText(s);
          if (text.trim().isNotEmpty) textBlocks.add(text);
        }
      }
    }

    if (textBlocks.isEmpty) {
      throw Exception('No extractable text found in PDF (possibly a scanned/image-based PDF)');
    }
    return textBlocks.join('\n\n');
  }

  void _findPdfStrings(String content, String op, List<String> out) {
    final opLen = op.length;
    int i = 0;
    while (i < content.length) {
      if (content[i] != '(') { i++; continue; }
      int depth = 1;
      int j = i + 1;
      while (j < content.length && depth > 0) {
        if (content[j] == '\\') { j += 2; continue; }
        if (content[j] == '(') depth++;
        if (content[j] == ')') depth--;
        j++;
      }
      if (depth != 0) break;
      final inner = content.substring(i + 1, j - 1);
      int k = j;
      while (k < content.length &&
          (content[k] == ' ' || content[k] == '\t' ||
           content[k] == '\r' || content[k] == '\n')) {
        k++;
      }
      if (k + opLen <= content.length &&
          content.substring(k, k + opLen) == op) {
        final text = _unescapePdfText(inner);
        if (text.trim().isNotEmpty) out.add(text);
      }
      i = j;
    }
  }

  List<String> _extractParenStrings(String content) {
    final result = <String>[];
    int i = 0;
    while (i < content.length) {
      if (content[i] != '(') { i++; continue; }
      int depth = 1;
      int j = i + 1;
      while (j < content.length && depth > 0) {
        if (content[j] == '\\') { j += 2; continue; }
        if (content[j] == '(') depth++;
        if (content[j] == ')') depth--;
        j++;
      }
      if (depth == 0) {
        result.add(content.substring(i + 1, j - 1));
      }
      i = j;
    }
    return result;
  }

  String _unescapePdfText(String text) {
    final octalPattern = RegExp(r'\\([0-7]{1,3})');
    text = text.replaceAllMapped(octalPattern, (m) {
      final code = int.parse(m.group(1)!, radix: 8);
      return String.fromCharCode(code);
    });
    return text
        .replaceAll('\\(', '(')
        .replaceAll('\\)', ')')
        .replaceAll('\\n', '\n')
        .replaceAll('\\r', '\r')
        .replaceAll('\\t', '\t')
        .replaceAll('\\\\', '\\');
  }
}

/// Internal row classification for table detection.
class _RowInfo {

  _RowInfo({
    required this.yKey,
    required this.words,
    required this.text,
    required this.xGroups,
    required this.isParagraph,
    required this.numColumns,
    required this.hasPartialNumbering,
  }) : isTableRow = false;
  final double yKey;
  final List<_PdfWord> words;
  final String text;
  final List<double> xGroups;
  final bool isParagraph;
  final int numColumns;
  final bool hasPartialNumbering;
  bool isTableRow;
}
