import 'dart:io' show Platform;
import 'package:flutter/services.dart';

/// Manages the CDP proxy on Android.
///
/// The proxy is a TCP server (Kotlin side) that forwards bytes between
/// a localhost TCP port and the WebView's DevTools Unix socket.
/// Dart connects via standard WebSocket — the proxy is transparent.
class CdpProxyClient {
  static const _channel = MethodChannel('com.myminimax/chromium');

  /// Enable WebView debugging globally.
  static Future<bool> enableDebugging() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod('enableWebViewDebugging') == true;
    } catch (_) {
      return false;
    }
  }

  /// Start the CDP TCP proxy.
  /// Returns a map with {port, ready} on success.
  static Future<CdpProxyResult> startProxy({int port = 9229}) async {
    if (!Platform.isAndroid) {
      return const CdpProxyResult(ready: false);
    }
    try {
      final result = await _channel.invokeMethod('startProxy', {'port': port});
      if (result is Map) {
        return CdpProxyResult(
          ready: result['ready'] == true,
          port: result['port'] as int? ?? port,
        );
      }
      return const CdpProxyResult(ready: false);
    } catch (e) {
      print('[cdp] error: \$e');
      return CdpProxyResult(ready: false, error: e.toString());
    }
  }

  /// Stop the CDP proxy.
  static Future<void> stopProxy() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stopProxy');
    } catch (_) {}
  }

  /// Check if proxy is running.
  static Future<bool> isRunning() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod('isProxyRunning') == true;
    } catch (_) {
      return false;
    }
  }

  /// Get current proxy port.
  static Future<int> getProxyPort() async {
    if (!Platform.isAndroid) return 9223;
    try {
      return await _channel.invokeMethod('getProxyPort') as int? ?? 9223;
    } catch (_) {
      return 9223;
    }
  }
}

class CdpProxyResult {

  const CdpProxyResult({
    required this.ready,
    this.port = 9229,
    this.error,
  });
  final bool ready;
  final int port;
  final String? error;
}
