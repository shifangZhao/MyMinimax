import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:mime/mime.dart';
import 'package:xml/xml.dart';
import '../document_converter/document_converter.dart';
import '../document_converter/document_converter_registry.dart';
import '../document_converter/domain/document_converter_result.dart';
import '../document_converter/converters/docx_converter.dart';
import '../document_converter/converters/xlsx_converter.dart';
import '../document_converter/converters/pptx_converter.dart';
import '../document_converter/converters/pdf_converter.dart';

enum AttachmentType { image, document }

class FileUtils {
  static const int maxImageSize = 20 * 1024 * 1024;
  static const int maxPdfSize = 50 * 1024 * 1024;
  static const int maxDocxSize = 20 * 1024 * 1024;
  static const int maxDocumentSize = 10 * 1024 * 1024;

  static String detectMimeType(String fileName) {
    return lookupMimeType(fileName) ?? 'application/octet-stream';
  }

  /// Validate that image bytes match known magic bytes (JPEG, PNG, GIF, WebP, BMP, HEIF).
  /// Returns an error string if unrecognized, or null if valid.
  static String? validateImageFormat(Uint8List bytes) {
    if (bytes.length < 4) return '图片文件太小，不是有效的图片格式';
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return null;
    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return null;
    // GIF: 47 49 46 38 (GIF8)
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) return null;
    // WebP: 52 49 46 46 ... 57 45 42 50 (RIFF....WEBP)
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes.length >= 12 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return null;
    }
    // BMP: 42 4D
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) return null;
    // HEIF/HEIC: ftyp box at offset 4 (00 00 00 XX 66 74 79 70 68 65 69)
    if (bytes.length >= 12 &&
        bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) {
      return null;
    }
    return '不支持的图片格式（仅支持 JPEG、PNG、GIF、WebP、BMP、HEIC）';
  }

  static AttachmentType classifyFile(String mimeType) {
    if (mimeType.startsWith('image/')) return AttachmentType.image;
    return AttachmentType.document;
  }

  static String? validateFileSize(int bytes, AttachmentType type, {String? mimeType}) {
    int maxSize;
    String labelZh;
    String labelEn;

    if (type == AttachmentType.image) {
      maxSize = maxImageSize;
      labelZh = '图片';
      labelEn = 'images';
    } else if (mimeType == 'application/pdf') {
      maxSize = maxPdfSize;
      labelZh = 'PDF 文档';
      labelEn = 'PDF documents';
    } else if (mimeType == 'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
      maxSize = maxDocxSize;
      labelZh = 'Word 文档';
      labelEn = 'Word documents';
    } else {
      maxSize = maxDocumentSize;
      labelZh = '文档';
      labelEn = 'documents';
    }

    if (bytes > maxSize) {
      final maxMB = (maxSize / (1024 * 1024)).toStringAsFixed(0);
      return '文件过大：${formatFileSize(bytes)}，$labelZh最大支持 ${maxMB}MB\n'
          'File too large: ${formatFileSize(bytes)}, $labelEn supports up to ${maxMB}MB';
    }
    return null;
  }

  /// Convert 0-based column index to Excel column letter: 0→A, 1→B, … 25→Z, 26→AA.
  static String colNumToLetter(int n) {
    if (n < 0) return 'A';
    final buf = StringBuffer();
    int num = n;
    do {
      buf.writeCharCode('A'.codeUnitAt(0) + (num % 26));
      num = num ~/ 26 - 1;
    } while (num >= 0);
    return buf.toString().split('').reversed.join('');
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ── Document Converter integration ──

  static MarkItDown? _markitdown;
  static DocumentConverterRegistry? _registry;

  static void _ensureConvertersInitialized() {
    if (_markitdown != null) return;
    _registry = DocumentConverterRegistry();
    _registry!.registerAll([
      DocxConverter(),
      XlsxConverter(),
      PptxConverter(),
      PdfConverter(),
    ]);
    _markitdown = MarkItDown(registry: _registry!);
  }

  /// Convert document bytes to structured Markdown.
  static Future<DocumentConverterResult> convertToMarkdown({
    required Uint8List bytes,
    String? mimeType,
    String? fileName,
    Map<String, dynamic>? options,
  }) async {
    _ensureConvertersInitialized();
    return _markitdown!.convert(
      bytes,
      mimeType: mimeType,
      fileName: fileName,
      options: options,
    );
  }

  /// Whether the given file is a non-plain-text document that should be converted.
  static bool isDocumentFile({String? mimeType, String? fileName}) {
    if (mimeType == null && fileName == null) return false;
    if (mimeType != null && (_isTextMime(mimeType) || mimeType == 'text/markdown')) return false;
    _ensureConvertersInitialized();
    return _registry!
        .findConverter(mimeType: mimeType, fileName: fileName) != null;
  }

  static Future<String> extractText(String filePath, String mimeType) async {
    switch (mimeType) {
      case 'text/plain':
      case 'text/markdown':
      case 'text/csv':
      case 'text/html':
      case 'text/xml':
      case 'application/json':
      case 'application/xml':
      case 'application/javascript':
      case 'application/x-yaml':
        return await _readPlainText(filePath);
      case 'application/pdf':
        return await _extractPdfText(filePath);
      case 'application/msword':
        return await _extractDocText(filePath);
      case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        return await _extractDocxText(filePath);
      case 'application/vnd.openxmlformats-officedocument.presentationml.presentation':
        return await _extractPptxText(filePath);
      case 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':
        return await _extractXlsxText(filePath);
      default:
        if (_isTextMime(mimeType)) {
          return await _readPlainText(filePath);
        }
        throw UnsupportedError('Unsupported file format: $mimeType / 不支持的文件格式: $mimeType');
    }
  }

  static bool _isTextMime(String mimeType) {
    return mimeType.startsWith('text/') ||
        mimeType == 'application/json' ||
        mimeType == 'application/xml' ||
        mimeType == 'application/javascript' ||
        mimeType == 'application/x-yaml' ||
        mimeType == 'application/x-sh';
  }

  static Future<String> _readPlainText(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  static Future<String> _extractDocText(String filePath) async {
    throw UnsupportedError(
      'Legacy .doc format is not supported. Please convert to .docx first.\n'
      '旧版 .doc 格式不支持，请先转换为 .docx 格式。',
    );
  }

  static Future<String> _extractDocxText(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final docXml = archive.findFile('word/document.xml');
    if (docXml == null) throw Exception('Invalid DOCX: missing word/document.xml / 无效的 DOCX：缺少 word/document.xml');

    final xmlString = utf8.decode(docXml.content as List<int>);
    final document = XmlDocument.parse(xmlString);

    final buffer = StringBuffer();
    for (final para in document.findAllElements('w:p')) {
      final texts = para.findAllElements('w:t').map((t) => t.innerText);
      buffer.writeln(texts.join(''));
    }
    return buffer.toString().trim();
  }

  static Future<String> _extractPptxText(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final slideFiles = archive.files
        .where((f) => f.name.startsWith('ppt/slides/slide') && f.name.endsWith('.xml'))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final buffer = StringBuffer();
    for (final file in slideFiles) {
      final xmlString = utf8.decode(file.content as List<int>);
      final document = XmlDocument.parse(xmlString);
      final slideTexts = document.findAllElements('a:t').map((t) => t.innerText).join(' ');
      if (slideTexts.trim().isNotEmpty) {
        buffer.writeln(slideTexts);
      }
    }
    return buffer.toString().trim();
  }

  static Future<String> _extractXlsxText(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final sharedStrings = <String>[];
    final ssFile = archive.findFile('xl/sharedStrings.xml');
    if (ssFile != null) {
      final xmlString = utf8.decode(ssFile.content as List<int>);
      final document = XmlDocument.parse(xmlString);
      for (final si in document.findAllElements('si')) {
        sharedStrings.add(si.findAllElements('t').map((t) => t.innerText).join(''));
      }
    }

    final buffer = StringBuffer();
    final sheetFiles = archive.files
        .where((f) => f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml'))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    for (final file in sheetFiles) {
      final xmlString = utf8.decode(file.content as List<int>);
      final document = XmlDocument.parse(xmlString);
      for (final row in document.findAllElements('row')) {
        final cells = <String>[];
        for (final c in row.findAllElements('c')) {
          final v = c.findElements('v').firstOrNull;
          if (v != null) {
            if (c.getAttribute('t') == 's') {
              final idx = int.tryParse(v.innerText) ?? -1;
              if (idx >= 0 && idx < sharedStrings.length) {
                cells.add(sharedStrings[idx]);
              }
            } else {
              cells.add(v.innerText);
            }
          }
        }
        if (cells.isNotEmpty) buffer.writeln(cells.join('\t'));
      }
    }
    return buffer.toString().trim();
  }

  static Future<String> _extractPdfText(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final content = latin1.decode(bytes);

    final textBlocks = <String>[];
    final btPattern = RegExp(r'BT(.*?)ET', dotAll: true);
    for (final match in btPattern.allMatches(content)) {
      final block = match.group(1)!;
      final tjPattern = RegExp(r'\(([^)]*)\)\s*Tj');
      for (final tj in tjPattern.allMatches(block)) {
        final text = tj.group(1) ?? '';
        if (text.trim().isNotEmpty) textBlocks.add(text);
      }
      final tjArrayPattern = RegExp(r'\[(.*?)\]\s*TJ', dotAll: true);
      for (final tjArray in tjArrayPattern.allMatches(block)) {
        final arrayContent = tjArray.group(1)!;
        final strPattern = RegExp(r'\(([^)]*)\)');
        for (final str in strPattern.allMatches(arrayContent)) {
          final text = str.group(1) ?? '';
          if (text.trim().isNotEmpty) textBlocks.add(text);
        }
      }
    }

    if (textBlocks.isEmpty) {
      throw Exception('No extractable text found in PDF (possibly a scanned/image-based PDF) / '
          'PDF 中未找到可提取的文本（可能是扫描图片型 PDF）');
    }
    return textBlocks.join('\n');
  }
}
