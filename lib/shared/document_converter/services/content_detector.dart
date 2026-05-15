/// Content-based MIME type and extension detection from raw bytes.
/// Equivalent to markitdown's Magika integration.
library;

import 'dart:convert';
import 'dart:typed_data';

class ContentDetector {
  /// Detect MIME type and extension from raw bytes using signature matching.
  static ({String? mimeType, String? extension}) detect(Uint8List bytes) {
    if (bytes.isEmpty) return (mimeType: null, extension: null);

    // PDF: starts with %PDF
    if (_matchBytes(bytes, r'%PDF')) {
      return (mimeType: 'application/pdf', extension: '.pdf');
    }

    // PNG: \x89PNG\r\n\x1a\n
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 &&
        bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A) {
      return (mimeType: 'image/png', extension: '.png');
    }

    // JPEG: \xFF\xD8\xFF
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return (mimeType: 'image/jpeg', extension: '.jpg');
    }

    // GIF: GIF89a or GIF87a
    if (bytes.length >= 6) {
      final header = String.fromCharCodes(bytes.sublist(0, 6));
      if (header == 'GIF89a' || header == 'GIF87a') {
        return (mimeType: 'image/gif', extension: '.gif');
      }
    }

    // ZIP-based formats (DOCX, XLSX, PPTX, EPUB, ZIP)
    if (bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      return _detectZipFormat(bytes);
    }

    // OLE2 compound document (.doc, .xls, .msg)
    if (bytes.length >= 8 &&
        bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0 &&
        bytes[4] == 0xA1 && bytes[5] == 0xB1 && bytes[6] == 0x1A && bytes[7] == 0xE1) {
      return (mimeType: 'application/msword', extension: '.doc');
    }

    // Try text-based detection
    return _detectTextFormat(bytes);
  }

  /// Match ASCII prefix bytes against a pattern string.
  static bool _matchBytes(Uint8List bytes, String pattern) {
    if (bytes.length < pattern.length) return false;
    for (int i = 0; i < pattern.length; i++) {
      if (bytes[i] != pattern.codeUnitAt(i)) return false;
    }
    return true;
  }

  /// Detect ZIP-based formats by scanning only the local-file-header region.
  /// ZIP filenames appear in plain text near the file headers, typically within
  /// the first 64 KB for the small XML entry files that identify the format.
  /// This avoids decoding the entire file as UTF-8.
  static ({String? mimeType, String? extension}) _detectZipFormat(Uint8List bytes) {
    // Scan only the first 64 KB for format-identifying filenames
    final scanSize = bytes.length < 65536 ? bytes.length : 65536;
    try {
      final content = utf8.decode(bytes.sublist(0, scanSize), allowMalformed: true);

      if (content.contains('word/document.xml')) {
        return (mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', extension: '.docx');
      }
      if (content.contains('xl/workbook.xml') || content.contains('xl/worksheets/')) {
        return (mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', extension: '.xlsx');
      }
      if (content.contains('ppt/presentation.xml') || content.contains('ppt/slides/')) {
        return (mimeType: 'application/vnd.openxmlformats-officedocument.presentationml.presentation', extension: '.pptx');
      }
      if (content.contains('META-INF/container.xml')) {
        return (mimeType: 'application/epub+zip', extension: '.epub');
      }
    } catch (_) {}

    return (mimeType: 'application/zip', extension: '.zip');
  }

  /// Detect text-based formats (HTML, XML, JSON, CSV, plain text).
  static ({String? mimeType, String? extension}) _detectTextFormat(Uint8List bytes) {
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      // Try UTF-16
      if (bytes.length >= 2) {
        try {
          if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
            content = utf8.decode(bytes.sublist(2));
          } else if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
            // UTF-16BE - not handled here, fall through
            return (mimeType: 'text/plain', extension: '.txt');
          } else {
            return (mimeType: 'application/octet-stream', extension: null);
          }
        } catch (_) {
          return (mimeType: 'application/octet-stream', extension: null);
        }
      } else {
        return (mimeType: 'application/octet-stream', extension: null);
      }
    }

    final trimmed = content.trim().toLowerCase();

    // HTML
    if (trimmed.startsWith('<!doctype html') || trimmed.startsWith('<html') || trimmed.contains('<head>') || trimmed.contains('<body>')) {
      return (mimeType: 'text/html', extension: '.html');
    }

    // XML
    if (trimmed.startsWith('<?xml')) {
      return (mimeType: 'application/xml', extension: '.xml');
    }

    // JSON
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        json.decode(content);
        return (mimeType: 'application/json', extension: '.json');
      } catch (_) {}
    }

    // CSV (heuristic: first few lines have consistent comma/tab counts)
    final lines = content.replaceAll('\r\n', '\n').split('\n').where((l) => l.trim().isNotEmpty).take(5).toList();
    if (lines.length >= 2) {
      final commaCounts = lines.map((l) => ','.allMatches(l).length).toList();
      final tabCounts = lines.map((l) => '\t'.allMatches(l).length).toList();

      if (commaCounts.length >= 2 &&
          commaCounts.every((c) => c > 0) &&
          commaCounts.toSet().length <= 2) {
        return (mimeType: 'text/csv', extension: '.csv');
      }
      if (tabCounts.length >= 2 &&
          tabCounts.every((c) => c > 0) &&
          tabCounts.toSet().length <= 2) {
        return (mimeType: 'text/tab-separated-values', extension: '.tsv');
      }
    }

    return (mimeType: 'text/plain', extension: '.txt');
  }
}
