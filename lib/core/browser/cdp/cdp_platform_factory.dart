import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, HttpClient;
import 'cdp_chromium_client.dart';

/// Detects CDP capability on the current device.
///
/// Android: Starts a TCP→Unix socket proxy that connects to the
///   system WebView's DevTools server. Zero APK size increase.
/// iOS: WKWebView does not expose CDP. Always returns null.
/// Desktop: Returns the CDP URL if configured (for development).
class CdpPlatformFactory {
  CdpPlatformFactory._();

  static const defaultPort = 9229; // 9223 often taken on emulators

  /// Whether the current platform can potentially support CDP.
  static bool get isCdpPossible {
    if (Platform.isAndroid) return true;
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) return true;
    return false;
  }

  /// Build the CDP WebSocket URL for the given host/port.
  /// The Dart side connects via standard WebSocket to the local TCP proxy.
  /// The proxy forwards bytes to the WebView's DevTools Unix socket.
  static Uri buildCdpUrl({String host = '127.0.0.1', int port = defaultPort}) {
    return Uri.parse('ws://$host:$port');
  }

  /// Discover or start a CDP endpoint.
  ///
  /// Returns the browser-level WebSocket URL for CDP communication.
  /// The returned URL is ready to connect via [CdpConnection].
  static Future<Uri?> discover() async {
    if (Platform.isAndroid) {
      await CdpProxyClient.enableDebugging();

      // Only start proxy if not already running (avoid EADDRINUSE)
      if (!await CdpProxyClient.isRunning()) {
        final proxyResult = await CdpProxyClient.startProxy(port: defaultPort);
        if (!proxyResult.ready) {
          // Proxy failed — fallback to JS
          return null;
        }
      }

      // HTTP discover via proxy (may retry internally)
      final proxyPort = await CdpProxyClient.getProxyPort();
      return await _discoverWsEndpoint(port: proxyPort);
    }

    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      return await _discoverWsEndpoint(port: 9222);
    }

    return null;
  }

  /// Query the CDP HTTP endpoint for the browser-level WebSocket URL.
  static Future<Uri?> _discoverWsEndpoint({int port = defaultPort}) async {
    try {
      final httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 3);
      final request = await httpClient.getUrl(
          Uri.parse('http://127.0.0.1:$port/json/version'));
      final response = await request.close().timeout(
            const Duration(seconds: 2),
            onTimeout: () => throw TimeoutException('CDP HTTP timeout'),
          );
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        httpClient.close();
        // Extract the browser WebSocket URL from /json/version response
        final data = jsonDecode(body) as Map<String, dynamic>;
        final wsUrl = data['webSocketDebuggerUrl'] as String?;
        if (wsUrl != null && wsUrl.isNotEmpty) {
          return Uri.parse(wsUrl);
        }
        // Fallback: use standard browser endpoint
        return buildCdpUrl(port: port);
      }
      httpClient.close();
    } catch (_) {
      // HTTP discovery failed — fall back to direct WebSocket
    }
    return buildCdpUrl(port: port);
  }

  /// Stop the CDP proxy on Android.
  static Future<void> shutdown() async {
    if (Platform.isAndroid) {
      await CdpProxyClient.stopProxy();
    }
  }
}
