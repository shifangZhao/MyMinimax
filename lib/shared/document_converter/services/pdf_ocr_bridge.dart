import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class PdfOcrBridge {

  /// Constructor is a no-op — callers must [await ensureLoaded()] before use.
  PdfOcrBridge();
  static const _channel = MethodChannel('com.myminimax/ocr');

  static bool _loaded = false;
  static Completer<void>? _loadingPromise;

  /// Status callback — reports model loading and OCR errors.
  /// [stage] values: 'loading_model', 'model_loaded', 'ocr_error'.
  static void Function(String stage, String? detail)? onStatus;

  static bool get isSupported {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// Ensure the OCR model is loaded (idempotent, safe for concurrent calls).
  /// Callers must await this before using [recognizeFile].
  static Future<bool> ensureLoaded() async {
    if (_loaded) return true;
    if (!isSupported) return false;
    if (_loadingPromise != null) {
      await _loadingPromise!.future;
      return _loaded;
    }
    _loadingPromise = Completer<void>();
    onStatus?.call('loading_model', null);
    try {
      _loaded = await _channel.invokeMethod<bool>('loadModel') ?? false;
    } catch (_) {
      _loaded = false;
    }
    _loadingPromise!.complete();
    _loadingPromise = null;
    onStatus?.call('model_loaded', null);
    return _loaded;
  }

  Future<OcrPageResult> recognizeFile(String imagePath, {int pageIndex = 0}) async {
    try {
      if (!_loaded) {
        return OcrPageResult(
          pageIndex: pageIndex,
          text: '',
          blockCount: 0,
          error: 'OCR model not loaded',
        );
      }

      final text = await _channel.invokeMethod<String>('recognize', {
        'imagePath': imagePath,
      });

      if (text == null || text.trim().isEmpty) {
        return OcrPageResult(pageIndex: pageIndex, text: '', blockCount: 0);
      }

      return OcrPageResult(
        pageIndex: pageIndex,
        text: text,
        blockCount: text.split('\n').where((l) => l.trim().isNotEmpty).length,
      );
    } catch (e) {
      print('[pdf] error: \$e');
      onStatus?.call('ocr_error', e.toString());
      return OcrPageResult(pageIndex: pageIndex, text: '', blockCount: 0, error: e.toString());
    }
  }

  /// Release the native model (call on app exit — the only cleanup path).
  static Future<void> disposeEngine() async {
    if (!_loaded) return;
    try {
      await _channel.invokeMethod('dispose');
    } catch (_) {}
    _loaded = false;
  }
}

class OcrPageResult {

  OcrPageResult({
    required this.pageIndex,
    required this.text,
    required this.blockCount,
    this.error,
  });
  final int pageIndex;
  final String text;
  final int blockCount;
  final String? error;

  bool get hasText => text.trim().isNotEmpty;
}
