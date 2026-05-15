import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class VoskService {
  static const _channel = MethodChannel('com.myminimax/vosk');
  static const _partialChannel = EventChannel('com.myminimax/vosk_partial');

  bool _isInitialized = false;
  StreamSubscription<dynamic>? _partialSub;
  final StreamController<String> _partialController = StreamController<String>.broadcast();

  Stream<String> get partialResults => _partialController.stream;

  Future<bool> get isAvailable async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> ensureInitialized() async {
    if (_isInitialized) return true;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelPath = '${dir.path}/vosk_model/vosk-model-small-cn-0.22';
      await _channel.invokeMethod('init', {'modelPath': modelPath});
      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('[Vosk] Init error: $e');
      return false;
    }
  }

  Future<void> startListening() async {
    if (!_isInitialized) {
      final ok = await ensureInitialized();
      if (!ok) throw Exception('Vosk initialization failed / Vosk 初始化失败');
    }
    // Subscribe to partial results before starting recognition
    _partialSub?.cancel();
    _partialSub = _partialChannel.receiveBroadcastStream().listen(
      (data) {
        if (data is String && data.isNotEmpty) {
          _partialController.add(data);
        }
      },
      onError: (e) => debugPrint('[Vosk] Partial stream error: $e'),
    );
    await _channel.invokeMethod('start');
  }

  Future<String> stopListening() async {
    try {
      final result = await _channel.invokeMethod<String>('stop');
      await _partialSub?.cancel();
      _partialSub = null;
      return result ?? '';
    } catch (e) {
      debugPrint('[Vosk] Stop error: $e');
      return '';
    }
  }

  Future<void> dispose() async {
    await _partialSub?.cancel();
    _partialSub = null;
    await _partialController.close();
    try {
      await _channel.invokeMethod('dispose');
    } catch (_) {}
    _isInitialized = false;
  }
}
