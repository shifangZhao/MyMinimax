import 'dart:async';
import '../../../features/tools/domain/tool.dart';

/// Unified element representation from either CDP or JS backends.
class InteractiveElement {

  const InteractiveElement({
    required this.index,
    this.backendNodeId,
    this.tag = '',
    this.text = '',
    this.type = '',
    this.id = '',
    this.placeholder = '',
    this.ariaLabel = '',
    this.href = '',
    this.role = '',
    this.depth = 0,
    this.disabled = false,
    this.isVisible = true,
    this.isNew = false,
    this.isInIframe = false,
    this.scrollable = false,
    this.scrollInfo = '',
    this.listeners = const [],
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
  });
  final int index;
  final int? backendNodeId;
  final String tag;
  final String text;
  final String type;
  final String id;
  final String placeholder;
  final String ariaLabel;
  final String href;
  final String role;
  final int depth;
  final bool disabled;
  final bool isVisible;
  final bool isNew;
  final bool isInIframe;
  final bool scrollable;
  final String scrollInfo;
  final List<String> listeners; // e.g. ["click", "keydown"]

  // Layout (CDP: from DOMSnapshot; JS: from getBoundingClientRect if available)
  final double x;
  final double y;
  final double width;
  final double height;

  /// The element's center point in CSS coordinates (for CDP Input domain).
  double get centerX => x + width / 2;
  double get centerY => y + height / 2;
}

/// Captured browser page state for the agent.
class BrowserPageState { // For stagnation detection

  const BrowserPageState({
    this.url = '',
    this.pageText = '',
    this.elements = const [],
    this.captchaWarning,
    this.downloadsInfo,
    this.pageFingerprint,
  });
  final String url;
  final String pageText; // Markdown or plain text
  final List<InteractiveElement> elements;
  final String? captchaWarning;
  final String? downloadsInfo;
  final String? pageFingerprint;
}

class CdpMouseEvent {

  const CdpMouseEvent({
    required this.type,
    required this.x,
    required this.y,
    this.button = 'left',
    this.clickCount = 1,
    this.modifiers = 0,
  });
  final String type; // mousePressed, mouseReleased, mouseMoved, mouseWheel
  final double x;
  final double y;
  final String button; // left, right, middle
  final int clickCount;
  final int modifiers;
}

class CdpKeyEvent {

  const CdpKeyEvent({
    required this.type,
    required this.key,
    this.code,
    this.modifiers = 0,
    this.text,
    this.isKeypad = false,
  });
  final String type; // keyDown, keyUp, rawKeyDown, char
  final String key;
  final String? code;
  final int modifiers;
  final String? text;
  final bool isKeypad;
}

class CdpCookie {

  const CdpCookie({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.httpOnly = false,
    this.secure = false,
    this.session = true,
    this.expires,
  });
  final String name;
  final String value;
  final String domain;
  final String path;
  final bool httpOnly;
  final bool secure;
  final bool session;
  final double? expires;
}

class CdpLayoutMetrics {

  const CdpLayoutMetrics({
    this.devicePixelRatio = 1.0,
    this.viewportWidth = 0,
    this.viewportHeight = 0,
    this.contentWidth = 0,
    this.contentHeight = 0,
    this.scrollX = 0,
    this.scrollY = 0,
  });
  final double devicePixelRatio;
  final double viewportWidth;
  final double viewportHeight;
  final double contentWidth;
  final double contentHeight;
  final double scrollX;
  final double scrollY;
}

/// Capability flags for a browser backend.
class BrowserCapability {

  const BrowserCapability({
    this.supportsCdp = false,
    this.supportsCrossOriginIframes = false,
    this.supportsNetworkMonitoring = false,
    this.supportsTrustedEvents = false,
    this.supportsCookieAccess = false,
    this.supportsConsoleLogs = false,
  });
  final bool supportsCdp;
  final bool supportsCrossOriginIframes;
  final bool supportsNetworkMonitoring;
  final bool supportsTrustedEvents; // CDP Input domain = isTrusted:true
  final bool supportsCookieAccess; // includes HttpOnly
  final bool supportsConsoleLogs;

  static const jsOnly = BrowserCapability();
  static const cdp = BrowserCapability(
    supportsCdp: true,
    supportsCrossOriginIframes: true,
    supportsNetworkMonitoring: true,
    supportsTrustedEvents: true,
    supportsCookieAccess: true,
    supportsConsoleLogs: true,
  );
}

// ── Interface ──────────────────────────────────────────────────────

/// Unified browser backend interface.
///
/// Android: [CdpToolBackend] — Chrome DevTools Protocol via WebSocket.
/// iOS:     [JsToolBackend] — JavaScript injection via WKWebView.
///
/// The agent loop in [WebAgent] only depends on this interface,
/// never on concrete backend implementations.
abstract class IBrowserBackend {
  // ── Callbacks ──────────────────────────────────────────────────

  Future<String?> Function(String reason, String? prompt)? get onHumanAssist;
  set onHumanAssist(Future<String?> Function(String reason, String? prompt)? cb);

  // ── Tool execution ──────────────────────────────────────────────

  Future<ToolResult> execute(String toolName, Map<String, dynamic> params);

  // ── State capture ───────────────────────────────────────────────

  /// Capture the current page state. CDP uses 4 parallel calls;
  /// JS uses a single evaluateJavascript querySelectorAll.
  Future<BrowserPageState> capturePageState({
    Set<String>? previousElementKeys,
  });

  // ── CDP-native methods (return empty/null on JS backend) ───────

  Future<List<Map<String, dynamic>>> getEventListeners(int backendNodeId);

  Future<List<CdpCookie>> getCookies(String url);

  Future<CdpLayoutMetrics?> getLayoutMetrics();

  Future<void> dispatchMouseEvent(CdpMouseEvent event);

  Future<void> dispatchKeyEvent(CdpKeyEvent event);

  /// Capture a clean screenshot, returns base64 PNG or null.
  Future<String?> captureScreenshot();

  // ── Capability ──────────────────────────────────────────────────

  BrowserCapability get capability;

  // ── Events (watchdog data streams) ──────────────────────────────

  Stream<String>? get networkRequestStream;

  Stream<String>? get consoleMessageStream;

  Stream<String>? get downloadEventStream;

  // ── Lifecycle ───────────────────────────────────────────────────

  Future<void> initialize();

  Future<void> dispose();
}
