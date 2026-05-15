import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'domain/document_converter_result.dart';
import 'document_converter_registry.dart';
import 'services/cancellation_token.dart';
import 'services/content_detector.dart';

/// Options key for [CancellationToken] passed through to converters.
const String kCancelToken = '_cancelToken';
/// Options key for progress callback: void Function(int current, int total).
const String kOnProgress = '_onProgress';

class MarkItDown {

  MarkItDown({DocumentConverterRegistry? registry})
      : _registry = registry ?? DocumentConverterRegistry();
  final DocumentConverterRegistry _registry;

  /// Convert document bytes to Markdown.
  ///
  /// - If [mimeType] / [fileName] are not given, detected from byte signatures.
  /// - [maxBytes] limits input size (default 50 MB). Throws if exceeded.
  /// - [cancelToken] enables cooperative cancellation (timeout, user cancel).
  /// - Dispatch: primary match → fallback all converters → plain text preview.
  Future<DocumentConverterResult> convert(
    Uint8List bytes, {
    String? mimeType,
    String? fileName,
    int maxBytes = 50 * 1024 * 1024, // 50 MB default
    CancellationToken? cancelToken,
    void Function(int current, int total)? onProgress,
    Map<String, dynamic>? options,
  }) async {
    // ── Size guard ──
    if (bytes.length > maxBytes) {
      return DocumentConverterResult(
        markdownContent:
            '*File too large: ${_formatBytes(bytes.length)} exceeds limit of ${_formatBytes(maxBytes)}.*\n'
            '*Please reduce the file size and try again.*\n',
        mimeType: mimeType,
        detectedFormat: 'error',
        metadata: {'error': 'file_too_large', 'fileSize': bytes.length, 'maxBytes': maxBytes},
      );
    }

    cancelToken?.throwIfCancelled();

    // ── Auto-detect MIME ──
    String? detectedMime = mimeType;
    String? detectedExt = fileName?.toLowerCase();

    if (detectedMime == null) {
      final detected = ContentDetector.detect(bytes);
      detectedMime ??= detected.mimeType;
      detectedExt ??= detected.extension;
    }

    // Pass cancellation and progress through options
    final mergedOptions = <String, dynamic>{};
    if (options != null) mergedOptions.addAll(options);
    if (cancelToken != null) mergedOptions[kCancelToken] = cancelToken;
    if (onProgress != null) mergedOptions[kOnProgress] = onProgress;

    // ── Phase 1: Best-match converter ──
    final primary = _registry.findConverter(
      mimeType: detectedMime,
      fileName: detectedExt,
    );

    if (primary != null) {
      try {
        cancelToken?.throwIfCancelled();
        final result = await primary.convert(
          bytes: bytes,
          mimeType: detectedMime,
          fileName: detectedExt,
          options: mergedOptions,
        );
        if (result.markdownContent.isNotEmpty &&
            result.metadata?['unsupported'] != true) {
          return result;
        }
      } on CancellationException {
        rethrow;
      } catch (e) {
        debugPrint('MarkItDown: Primary converter ${primary.formatName} failed: $e');
      }
    }

    // ── Phase 2: Fallback all other converters ──
    for (final converter in _registry.converters) {
      if (converter == primary) continue;
      try {
        cancelToken?.throwIfCancelled();
        final result = await converter.convert(
          bytes: bytes,
          mimeType: detectedMime,
          fileName: detectedExt,
          options: mergedOptions,
        );
        if (result.markdownContent.isNotEmpty &&
            result.metadata?['unsupported'] != true) {
          debugPrint('MarkItDown: Fallback converter ${converter.formatName} succeeded');
          return result;
        }
      } on CancellationException {
        rethrow;
      } catch (e) { /* try next */ }
        print('[document] error: \$e');
    }

    cancelToken?.throwIfCancelled();

    // ── Phase 3: Last resort ──
    return _fallbackResult(bytes, detectedMime, detectedExt ?? fileName);
  }

  DocumentConverterResult _fallbackResult(
    Uint8List bytes, String? mimeType, String? fileName) {
    final truncated = bytes.length > 500 ? bytes.sublist(0, 500) : bytes;
    String preview;
    try {
      preview = utf8.decode(truncated);
    } catch (_) {
      preview = latin1.decode(truncated);
    }
    return DocumentConverterResult(
      markdownContent:
          '```\n[Unsupported format: ${mimeType ?? fileName ?? "unknown"}]\n'
          '${preview.replaceAll('```', "'''")}\n'
          '${bytes.length > 500 ? '...(truncated)' : ''}\n'
          '```\n',
      mimeType: mimeType,
      detectedFormat: 'unknown',
      metadata: {'unsupported': true},
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
