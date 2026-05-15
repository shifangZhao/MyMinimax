import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../../core/browser/browser_state.dart';
import '../../../core/browser/browser_constants.dart';
import 'widgets/browser_toolbar.dart';
import 'widgets/browser_tab_bar.dart';
import 'widgets/browser_webview.dart';

class BrowserPanel extends ConsumerStatefulWidget {
  const BrowserPanel({super.key});

  @override
  ConsumerState<BrowserPanel> createState() => _BrowserPanelState();
}

class _BrowserPanelState extends ConsumerState<BrowserPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;
  final _findController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _findController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _executeOnActiveTab(
      Future<void> Function(InAppWebViewController) action) async {
    final handler = ref.read(browserToolHandlerProvider);
    if (handler == null || handler.controllers.isEmpty) return;
    final tabs = ref.read(browserTabsProvider);
    final activeIdx = ref.read(browserActiveTabIndexProvider);
    if (activeIdx >= tabs.length) return;
    final controller = handler.controllers[tabs[activeIdx].id];
    if (controller == null) return;
    await action(controller);
  }

  void _navigateTo(String url) {
    String finalUrl = url.trim();
    if (finalUrl.isEmpty) return;
    if (!finalUrl.startsWith('http://') && !finalUrl.startsWith('https://')) {
      if (finalUrl.contains('.') && !finalUrl.contains(' ')) {
        finalUrl = 'https://$finalUrl';
      } else {
        finalUrl = 'https://cn.bing.com/search?q=${Uri.encodeComponent(finalUrl)}';
      }
    }
    _executeOnActiveTab(
        (c) => c.loadUrl(urlRequest: URLRequest(url: WebUri(finalUrl))));
  }

  void _findInPage(String text) {
    _executeOnActiveTab((c) async {
      if (text.isEmpty) {
        await c.evaluateJavascript(source: 'window.__clearFindHighlights?.()');
        return;
      }
      final search = jsonEncode(text.toLowerCase());
      final len = text.length;
      await c.evaluateJavascript(source: '''
(function() {
  if (window.__clearFindHighlights) window.__clearFindHighlights();
  var marks = [];
  var q = $search;
  function walk(node) {
    if (node.nodeType === 3) {
      var idx = node.textContent.toLowerCase().indexOf(q);
      if (idx >= 0) {
        var span = document.createElement('mark');
        span.style.cssText = 'background:#FFEB3B;color:#000;padding:0 2px;border-radius:2px';
        span.textContent = node.textContent.substring(idx, idx + $len);
        var after = node.splitText(idx);
        after.splitText($len);
        after.parentNode.replaceChild(span, after);
        marks.push(span);
      }
    } else if (node.nodeType === 1 && !/^(SCRIPT|STYLE|MARK|NOSCRIPT)\$/i.test(node.tagName)) {
      for (var c = node.firstChild; c; c = c.nextSibling) walk(c);
    }
  }
  if (document.body) walk(document.body);
  if (marks.length > 0) marks[0].scrollIntoView({behavior: 'smooth', block: 'center'});
  window.__clearFindHighlights = function() {
    marks.forEach(function(m) {
      var p = m.parentNode;
      if (p) { p.replaceChild(document.createTextNode(m.textContent), m); p.normalize(); }
    });
    marks = [];
  };
})()
''');
    });
  }

  void _hidePanel() {
    ref.read(browserPanelVisibleProvider.notifier).state = false;
  }

  void _closeBrowser() {
    _hidePanel();
    ref.read(browserEngineActiveProvider.notifier).state = false;
    ref.read(browserToolHandlerProvider.notifier).state = null;
    ref.read(browserTabsProvider.notifier).closeAllButFirst();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(browserTabsProvider);
    final activeIdx = ref.watch(browserActiveTabIndexProvider);
    final isLoading = ref.watch(browserIsLoadingProvider);
    final currentUrl = ref.watch(browserCurrentUrlProvider);
    final progress = ref.watch(browserProgressProvider);
    final error = ref.watch(browserErrorProvider);
    final desktopMode = ref.watch(browserDesktopModeProvider);
    final darkMode = ref.watch(browserDarkModeProvider);
    final findBarVisible = ref.watch(browserFindBarVisibleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canGoBack = (tabs.isNotEmpty && activeIdx < tabs.length) && tabs[activeIdx].canGoBack;
    final canGoForward = (tabs.isNotEmpty && activeIdx < tabs.length) && tabs[activeIdx].canGoForward;

    final panelVisible = ref.watch(browserPanelVisibleProvider);

    // Animate panel
    if (panelVisible) {
      _slideController.forward();
    } else {
      _slideController.reverse();
    }

    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? PixelTheme.darkBase : PixelTheme.background,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header row with minimize + close buttons
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4, right: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Minimize button
                  GestureDetector(
                    onTap: _hidePanel,
                    child: Icon(Icons.horizontal_rule, size: 20,
                        color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText),
                  ),
                  const SizedBox(width: 16),
                  // Close button
                  GestureDetector(
                    onTap: _closeBrowser,
                    child: Icon(Icons.close, size: 20,
                        color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText),
                  ),
                ],
              ),
            ),
              BrowserToolbar(
                url: currentUrl,
                isLoading: isLoading,
                tabCount: tabs.length,
                canGoBack: canGoBack,
                canGoForward: canGoForward,
                desktopMode: desktopMode,
                darkMode: darkMode,
                onUrlSubmit: _navigateTo,
                onToggleDarkMode: () {
                  ref.read(browserDarkModeProvider.notifier).state = !darkMode;
                  // Reload current page to apply/remove dark CSS
                  _executeOnActiveTab((c) => c.reload());
                },
                onBack: () => _executeOnActiveTab((c) => c.goBack()),
                onForward: () => _executeOnActiveTab((c) => c.goForward()),
                onReload: () => _executeOnActiveTab((c) => c.reload()),
                onHome: () => _navigateTo(BrowserConstants.homeUrl),
                onNewTab: () {
                  ref.read(browserTabsProvider.notifier).addTab();
                  final newLen = ref.read(browserTabsProvider).length;
                  ref.read(browserActiveTabIndexProvider.notifier).state = newLen - 1;
                },
                onToggleDesktop: () =>
                    ref.read(browserDesktopModeProvider.notifier).state = !desktopMode,
                onFindInPage: tabs.length > 1
                    ? null
                    : () => ref.read(browserFindBarVisibleProvider.notifier).state = !findBarVisible,
              ),
              if (tabs.length > 1)
                BrowserTabBar(
                  tabs: tabs,
                  activeIndex: activeIdx,
                  onTabSelected: (i) =>
                      ref.read(browserActiveTabIndexProvider.notifier).state = i,
                  onTabClosed: (i) {
                    ref.read(browserTabsProvider.notifier).closeTab(i);
                    final newLen = ref.read(browserTabsProvider).length;
                    if (activeIdx >= newLen) {
                      ref
                          .read(browserActiveTabIndexProvider.notifier)
                          .state = newLen - 1;
                    }
                  },
                ),
              if (progress > 0 && progress < 100)
                LinearProgressIndicator(
                  value: progress / 100,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDark ? PixelTheme.darkPrimary : PixelTheme.brandBlue,
                  ),
                ),
              if (error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: PixelTheme.error.withValues(alpha: 0.15),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 16, color: PixelTheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(error, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText)),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          ref.read(browserErrorProvider.notifier).state = null;
                          _executeOnActiveTab((c) => c.reload());
                        },
                        child: const Icon(Icons.refresh, size: 18, color: PixelTheme.brandBlue),
                      ),
                    ],
                  ),
                ),
              if (findBarVisible)
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: isDark ? PixelTheme.darkSurface : PixelTheme.surfaceVariant,
                    border: Border(bottom: BorderSide(color: isDark ? PixelTheme.darkBorderSubtle : PixelTheme.border, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.find_in_page, size: 16, color: PixelTheme.brandBlue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _findController,
                          autofocus: true,
                          style: TextStyle(fontSize: 13, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText),
                          decoration: InputDecoration(
                            hintText: '在页面中查找...',
                            hintStyle: TextStyle(fontSize: 13, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: _findInPage,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          _findController.clear();
                          _findInPage('');
                          ref.read(browserFindBarVisibleProvider.notifier).state = false;
                        },
                        child: Icon(Icons.close, size: 18, color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText),
                      ),
                    ],
                  ),
                ),
              const Expanded(child: BrowserWebView()),
            ],
          ),
        ),
      );
  }
}
