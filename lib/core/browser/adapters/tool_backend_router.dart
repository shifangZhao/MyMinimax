import 'dart:math';

import '../../../features/browser/data/browser_tool_handler.dart';
import '../cdp/cdp_connection.dart';
import '../cdp/cdp_platform_factory.dart';
import 'browser_tool_adapter.dart';
import 'cdp_tool_backend.dart';

/// Creates the appropriate [IBrowserBackend] for the current platform.
///
/// - Android: attempts CDP via embedded Chromium, falls back to JS injection
/// - iOS/WKWebView: always uses JS injection (JsToolBackend, backed by BrowserToolHandler)
/// - Desktop: attempts CDP (useful for development against local Chrome), falls back to JS
class ToolBackendRouter {
  ToolBackendRouter._();

  /// Build the platform-appropriate backend.
  ///
  /// [jsHandler] is the existing [BrowserToolHandler] that already implements
  /// [IBrowserBackend] with JS-injection tools. It serves as the fallback.
  ///
  /// [preferCdp] forces CDP even on platforms where it might fail (for testing).
  /// Defaults to true on Android, false on iOS.
  ///
  /// [maxReconnectAttempts] limits CDP reconnect attempts before permanent
  /// fallback to JS. null (default) = 10 attempts, 0 = no retries.
  ///
  /// [onPermanentFailure] is called when CDP reconnect attempts are exhausted.
  static Future<IBrowserBackend> create({
    required BrowserToolHandler jsHandler,
    bool? preferCdp,
    int? maxReconnectAttempts,
    void Function()? onPermanentFailure,
  }) async {
    preferCdp ??= CdpPlatformFactory.isCdpPossible;

    if (preferCdp) {
      // Retry CDP discovery — WebView DevTools socket may take a moment
      Uri? cdpUrl;
      for (int attempt = 0; attempt < 5; attempt++) {
        cdpUrl = await CdpPlatformFactory.discover();
        if (cdpUrl != null) break;
        // Exponential backoff: 200ms, 400ms, 800ms, 1.6s, 3.2s
        await Future.delayed(
            Duration(milliseconds: 200 * pow(2, attempt).round()));
      }

      if (cdpUrl != null) {
        try {
          final connection = CdpConnection(
            wsUrl: cdpUrl.toString(),
            maxReconnectAttempts: maxReconnectAttempts ?? 10,
            onPermanentFailure: onPermanentFailure,
          );
          final cdpBackend = CdpToolBackend(connection: connection);
          await cdpBackend.initialize();
          return cdpBackend;
        } catch (_) {
          // CDP failed — fall through to JS backend
        }
      }
    }

    // Fallback: JS injection backend
    await jsHandler.initialize();
    return jsHandler;
  }

  /// Create a JS-only backend directly (skipping CDP detection).
  static Future<IBrowserBackend> createJsOnly({
    required BrowserToolHandler jsHandler,
  }) async {
    await jsHandler.initialize();
    return jsHandler;
  }
}
