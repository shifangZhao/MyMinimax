import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class PdfNativeBridge {
  static const _channel = MethodChannel('com.myminimax/pdf');

  static bool get isSupported {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  static Future<Uint8List?> renderPageBytes(
    String filePath,
    int pageIndex,
  ) async {
    try {
      final tmpDir = await getTemporaryDirectory();
      final pngPath = '${tmpDir.path}/pdf_page_$pageIndex.png';
      final result = await _channel.invokeMethod<String>('renderPageAsImage', {
        'path': filePath,
        'page': pageIndex,
        'outputPath': pngPath,
      });
      if (result == null) return null;
      final pngFile = File(pngPath);
      if (!pngFile.existsSync()) return null;
      try {
        final bytes = await pngFile.readAsBytes();
        return bytes;
      } finally {
        try { pngFile.deleteSync(); } catch (_) {}
      }
    } catch (e) {
      print('[pdf] error: \$e');
      return null;
    }
  }

  static Future<int?> getPageCount(String filePath) async {
    try {
      final result = await _channel.invokeMethod<int>('getPageCount', {
        'path': filePath,
      });
      return result;
    } catch (e) {
      print('[pdf] error: \$e');
      return null;
    }
  }

  /// Write PDF bytes to a temp file, render up to [maxPages] pages as PNG bytes.
  static Future<List<Uint8List>> renderPagesFromBytes(
    Uint8List pdfBytes, {
    int maxPages = 10,
  }) async {
    if (!isSupported) return [];
    try {
      final tmpDir = await getTemporaryDirectory();
      final pdfPath = '${tmpDir.path}/_temp_render.pdf';
      final pdfFile = File(pdfPath);
      await pdfFile.writeAsBytes(pdfBytes);

      final pageCount = await getPageCount(pdfPath) ?? 0;
      final pages = <Uint8List>[];
      final limit = pageCount < maxPages ? pageCount : maxPages;

      for (int i = 0; i < limit; i++) {
        final png = await renderPageBytes(pdfPath, i);
        if (png != null) pages.add(png);
      }

      await pdfFile.delete();
      return pages;
    } catch (_) {
      return [];
    }
  }

  /// Render PDF pages to PNG files, returning their paths (files kept on disk for downstream processing).
  /// Caller is responsible for deleting the files when done.
  /// Uses a unique prefix per call so concurrent invocations do not overwrite each other.
  static Future<List<String>> renderPagesToFiles(
    Uint8List pdfBytes, {
    int? maxPages,
  }) async {
    if (!isSupported) return [];
    try {
      final tmpDir = await getTemporaryDirectory();
      final prefix = '_ptr_${DateTime.now().microsecondsSinceEpoch}';
      final pdfPath = '${tmpDir.path}/$prefix.pdf';
      final pdfFile = File(pdfPath);
      await pdfFile.writeAsBytes(pdfBytes);

      final pageCount = await getPageCount(pdfPath) ?? 0;
      final limit = maxPages != null
          ? (pageCount < maxPages ? pageCount : maxPages)
          : (pageCount > 500 ? 500 : pageCount); // safety cap

      final files = <String>[];
      for (int i = 0; i < limit; i++) {
        final pngPath = '${tmpDir.path}/${prefix}_$i.png';
        final result = await _channel.invokeMethod<String>('renderPageAsImage', {
          'path': pdfPath,
          'page': i,
          'outputPath': pngPath,
        });
        if (result != null) {
          final pngFile = File(pngPath);
          if (pngFile.existsSync()) files.add(pngPath);
        }
      }

      await pdfFile.delete();
      return files;
    } catch (_) {
      return [];
    }
  }
}
