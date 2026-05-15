import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/browser/browser_state.dart';
import '../../../../core/browser/browser_event_bridge.dart';
import '../../data/browser_tool_handler.dart';
import '../../../../core/browser/adapters/tool_backend_router.dart';
import '../../../../core/browser/adapters/cdp_tool_backend.dart';
import '../../../../core/browser/cdp/cdp_chromium_client.dart';
import '../../../../app/theme.dart';

class BrowserWebView extends ConsumerStatefulWidget {
  const BrowserWebView({super.key});

  @override
  ConsumerState<BrowserWebView> createState() => _BrowserWebViewState();
}

class _BrowserWebViewState extends ConsumerState<BrowserWebView> {
  final Map<String, InAppWebViewController> _controllers = {};
  bool _handlerRegistered = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    final backend = ref.read(browserBackendProvider);
    if (backend != null) {
      backend.dispose();
      ref.read(browserBackendProvider.notifier).state = null;
    }
    CdpProxyClient.stopProxy();
    super.dispose();
  }

  void _registerHandler() {
    if (_handlerRegistered && ref.read(browserToolHandlerProvider) != null) return;
    _handlerRegistered = true;
    final handler = BrowserToolHandler(controllers: _controllers, widgetRef: ref);
    ref.read(browserToolHandlerProvider.notifier).state = handler;

    // Initialize the backend via router (CDP on Android, JS on iOS)
    _initBackend(handler);
  }

  Future<void> _initBackend(BrowserToolHandler handler) async {
    ref.read(browserBackendModeProvider.notifier).state =
        BrowserBackendMode.initializing;

    try {
      await CdpProxyClient.enableDebugging();

      final backend = await ToolBackendRouter.create(
        jsHandler: handler,
        onPermanentFailure: () {
          // CDP reconnect exhausted — permanently fall back to JS.
          // Resetting browserBackendProvider makes ToolExecutor use
          // browserToolHandler (JS) instead.
          if (!mounted) return;
          ref.read(browserBackendProvider.notifier).state = null;
          ref.read(browserCdpAvailableProvider.notifier).state = false;
          ref.read(browserBackendModeProvider.notifier).state =
              BrowserBackendMode.jsFallback;
        },
      );

      ref.read(browserBackendProvider.notifier).state = backend;
      ref.read(browserCdpAvailableProvider.notifier).state =
          backend.capability.supportsCdp;
      ref.read(browserBackendModeProvider.notifier).state = backend
              .capability.supportsCdp
          ? BrowserBackendMode.cdp
          : BrowserBackendMode.jsFallback;

      // Wire up screenshot fallback: CDP Page.captureScreenshot doesn't work
      // on Android WebView, so we fall back to InAppWebViewController.takeScreenshot().
      if (backend is CdpToolBackend) {
        (backend as CdpToolBackend).onTakeScreenshot = () async {
          final h = ref.read(browserToolHandlerProvider);
          if (h == null || h.controllers.isEmpty) return null;
          final c = h.controllers.values.first;
          try {
            final bytes = await c.takeScreenshot();
            if (bytes != null) return base64Encode(bytes);
          } catch (_) {}
          return null;
        };
      }
    } catch (_) {
      // CDP init threw — fall back to JS
      await handler.initialize();
      ref.read(browserBackendProvider.notifier).state = handler;
      ref.read(browserBackendModeProvider.notifier).state =
          BrowserBackendMode.jsFallback;
    }
  }

  int? _currentIndex(String tabId) {
    final tabs = ref.read(browserTabsProvider);
    final idx = tabs.indexWhere((t) => t.id == tabId);
    return idx >= 0 ? idx : null;
  }

  Future<void> _injectDarkMode(InAppWebViewController controller) async {
    const css = 'html{background-color:#1a1a1a!important}'
        'html,body,div,section,article,main,header,footer,nav,aside,'
        'table,tbody,thead,tr,th,td,ul,ol,li,dl,dt,dd,form,fieldset,'
        'pre,code,blockquote,details,summary,figure,figcaption'
        '{background-color:#1a1a1a!important;color:#e0e0e0!important}'
        'a{color:#8ab4f8!important}'
        'input,textarea,select,button'
        '{background-color:#333!important;color:#e0e0e0!important;border-color:#555!important}'
        'img,video,canvas,svg{opacity:0.9}';
    final encoded = jsonEncode(css);
    await controller.evaluateJavascript(source: '''
(function() {
  var style = document.getElementById('_browser_dark_mode');
  if (!style) {
    style = document.createElement('style');
    style.id = '_browser_dark_mode';
    style.textContent = $encoded;
    var parent = document.head || document.documentElement;
    if (parent) parent.appendChild(style);
  }
})()
''');
  }

  void _onWebViewCreated(String tabId, InAppWebViewController controller) {
    _controllers[tabId] = controller;

    controller.addJavaScriptHandler(
      handlerName: 'browserStateReport',
      callback: (args) {
        if (args.isEmpty) return;
        final data = args[0] as Map<String, dynamic>?;
        if (data == null) return;
        final idx = _currentIndex(tabId);
        if (idx == null) return;
        final tabsNotifier = ref.read(browserTabsProvider.notifier);
        final newTitle = (data['title'] as String?) ?? '';
        final newUrl = (data['url'] as String?) ?? '';
        if (newTitle.isNotEmpty) tabsNotifier.setTabTitle(idx, newTitle);
        if (newUrl.isNotEmpty) tabsNotifier.setTabUrl(idx, newUrl);
      },
    );

    _registerHandler();
  }

  Future<void> _onLoadStart(String tabId, WebUri? uri) async {
    final idx = _currentIndex(tabId);
    if (idx == null) return;
    if (uri != null) {
      ref.read(browserTabsProvider.notifier).setTabUrl(idx, uri.toString());
    }
    ref.read(browserTabsProvider.notifier).setTabLoading(idx, true);
    final activeIdx = ref.read(browserActiveTabIndexProvider);
    if (idx == activeIdx) {
      ref.read(browserProgressProvider.notifier).state = 10;
      try {
        await _controllers[tabId]?.evaluateJavascript(
            source: 'window.__clearFindHighlights?.()');
      } catch (_) {}
    }
  }

  Future<void> _onLoadStop(String tabId, WebUri? uri) async {
    final idx = _currentIndex(tabId);
    if (idx == null) return;
    ref.read(browserTabsProvider.notifier).setTabLoading(idx, false);
    if (uri != null) {
      ref.read(browserTabsProvider.notifier).setTabUrl(idx, uri.toString());
    }
    final controller = _controllers[tabId];
    if (controller != null) {
      final canBack = await controller.canGoBack();
      final canForward = await controller.canGoForward();
      ref.read(browserTabsProvider.notifier).setTabNavState(idx, canBack, canForward);

      final title = await controller.getTitle() ?? '';
      if (title.isNotEmpty) {
        ref.read(browserTabsProvider.notifier).setTabTitle(idx, title);
      }

      await controller.evaluateJavascript(source: browserStateReportJs);

      final darkMode = ref.read(browserDarkModeProvider);
      if (darkMode) {
        await _injectDarkMode(controller);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(browserTabsProvider);
    final activeIdx = ref.watch(browserActiveTabIndexProvider);
    final desktopMode = ref.watch(browserDesktopModeProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) => _registerHandler());

    // 清理已关闭标签的 controller
    final activeIds = tabs.map((t) => t.id).toSet();
    _controllers.removeWhere((id, _) => !activeIds.contains(id));

    if (tabs.isEmpty) {
      return const Center(child: Text('没有打开的标签页'));
    }

    const mobileUA =
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
    const desktopUA =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

    return IndexedStack(
      index: activeIdx < tabs.length ? activeIdx : 0,
      children: List.generate(tabs.length, (i) {
        final tabId = tabs[i].id;
        final initialUrl = tabs[i].initialUrl ?? tabs[i].url;
        final uri = WebUri(initialUrl);

        return InAppWebView(
          key: ValueKey('tab_$tabId'),
          initialUrlRequest: URLRequest(url: uri),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            databaseEnabled: true,
            useShouldOverrideUrlLoading: true,
            supportZoom: true,
            builtInZoomControls: true,
            displayZoomControls: false,
            useWideViewPort: true,
            loadWithOverviewMode: true,
            allowFileAccess: true,
            allowContentAccess: true,
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
            cacheEnabled: true,
            userAgent: desktopMode ? desktopUA : mobileUA,
          ),
          pullToRefreshController: PullToRefreshController(
            options: PullToRefreshOptions(color: PixelTheme.brandBlue),
            onRefresh: () => _controllers[tabId]?.reload(),
          ),
          shouldOverrideUrlLoading: (controller, request) async {
            return NavigationActionPolicy.ALLOW;
          },
          onCreateWindow: (controller, createWindowAction) async {
            if (createWindowAction.request.url != null) {
              controller.loadUrl(
                urlRequest: URLRequest(url: createWindowAction.request.url!),
              );
            }
            return false;
          },
          onReceivedError: (controller, request, error) {
            final cur = _currentIndex(tabId);
            if (cur != null && cur == ref.read(browserActiveTabIndexProvider)) {
              ref.read(browserErrorProvider.notifier).state = error.description;
            }
            if (cur != null) {
              ref.read(browserTabsProvider.notifier).setTabLoading(cur, false);
            }
          },
          onReceivedHttpError: (controller, request, response) {
            final cur = _currentIndex(tabId);
            if (cur != null && cur == ref.read(browserActiveTabIndexProvider)) {
              ref.read(browserErrorProvider.notifier).state =
                  'HTTP ${response.statusCode}: ${response.reasonPhrase ?? request.url.toString()}';
            }
          },
          onDownloadStartRequest: (controller, request) async {
            await controller.loadUrl(urlRequest: URLRequest(url: request.url));
          },
          onWebViewCreated: (controller) => _onWebViewCreated(tabId, controller),
          onLoadStart: (controller, url) async {
            await _onLoadStart(tabId, url);
            final cur = _currentIndex(tabId);
            if (cur != null && cur == ref.read(browserActiveTabIndexProvider)) {
              ref.read(browserErrorProvider.notifier).state = null;
            }
          },
          onLoadStop: (controller, url) => _onLoadStop(tabId, url),
          onProgressChanged: (controller, progress) {
            final cur = _currentIndex(tabId);
            if (cur != null && cur == ref.read(browserActiveTabIndexProvider)) {
              ref.read(browserProgressProvider.notifier).state = progress;
            }
          },
        );
      }),
    );
  }
}
