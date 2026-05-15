import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../tools/domain/tool.dart';
import '../../tools/data/content/html_pipeline.dart';
import '../../tools/data/content/content_scorer.dart';
import '../../../core/browser/browser_state.dart';
import '../../../core/browser/browser_constants.dart';
import '../../../core/browser/adapters/browser_tool_adapter.dart';

class BrowserToolHandler implements IBrowserBackend {

  BrowserToolHandler({required this.controllers, this.widgetRef});
  final Map<String, InAppWebViewController> controllers;
  final WidgetRef? widgetRef;

  // ── IBrowserBackend: capability ─────────────────────────────────

  @override
  BrowserCapability get capability => BrowserCapability.jsOnly;

  // ── IBrowserBackend: event streams (JS: no CDP events) ──────────

  @override
  Stream<String>? get networkRequestStream => null;

  @override
  Stream<String>? get consoleMessageStream => null;

  @override
  Stream<String>? get downloadEventStream => null;

  // ── IBrowserBackend: CDP-native methods (JS: not supported) ─────

  @override
  Future<List<Map<String, dynamic>>> getEventListeners(int backendNodeId) async => [];

  @override
  Future<List<CdpCookie>> getCookies(String url) async => [];

  @override
  Future<CdpLayoutMetrics?> getLayoutMetrics() async => null;

  @override
  Future<void> dispatchMouseEvent(CdpMouseEvent event) async {}

  @override
  Future<void> dispatchKeyEvent(CdpKeyEvent event) async {}

  @override
  Future<String?> captureScreenshot() async {
    // JS backend uses browser_screenshot via execute()
    final result = await execute('browser_screenshot', {});
    return result.success ? result.data : null;
  }

  // ── IBrowserBackend: state capture ──────────────────────────────

  @override
  Future<BrowserPageState> capturePageState({
    Set<String>? previousElementKeys,
  }) async {
    final urlResult = await execute('browser_get_url', {});
    final url = urlResult.success ? urlResult.output : 'unknown';

    // Elements
    final elementsResult = await execute('browser_get_elements', {});
    final elementsStr = elementsResult.success ? elementsResult.output : '';

    final elements = <InteractiveElement>[];
    String? captchaWarning;
    if (elementsStr.isNotEmpty) {
      try {
        final parsed = jsonDecode(elementsStr) as Map<String, dynamic>;
        final list = parsed['elements'] as List? ?? [];
        final currentKeys = <String>{};
        final keys = previousElementKeys ?? <String>{};
        final hasPrev = keys.isNotEmpty;

        for (final e in list.take(50)) {
          final m = e as Map<String, dynamic>;
          final tag = m['tag'] as String? ?? '';
          final text = m['text'] as String? ?? '';
          final id = m['id'] as String? ?? '';
          final ariaLabel = m['ariaLabel'] as String? ?? '';
          final key = '$tag|$text|$id|$ariaLabel';
          currentKeys.add(key);
          final isNew = hasPrev && !keys.contains(key);

          elements.add(InteractiveElement(
            index: m['index'] as int? ?? 0,
            tag: tag,
            text: text,
            type: m['type'] as String? ?? '',
            id: id,
            placeholder: m['placeholder'] as String? ?? '',
            ariaLabel: ariaLabel,
            href: m['href'] as String? ?? '',
            role: m['role'] as String? ?? '',
            depth: m['depth'] as int? ?? 0,
            disabled: m['disabled'] as bool? ?? false,
            scrollable: m['scrollable'] as bool? ?? false,
            scrollInfo: m['scrollInfo'] as String? ?? '',
            isNew: isNew,
          ));
        }

        // Captcha
        final captcha = parsed['captcha'] as Map<String, dynamic>?;
        if (captcha != null && captcha['found'] == true) {
          captchaWarning = 'CAPTCHA detected: ${captcha['type'] ?? 'unknown'} — ${captcha['hint'] ?? ''}';
        }
      } catch (e) {
        debugPrint('[BrowserToolHandler] captcha parse error: $e');
      }
    }

    // Page text
    final contentResult = await execute('browser_get_content', {'format': 'markdown'});
    final pageText = contentResult.success ? contentResult.output : '';

    // Downloads
    String? downloadsInfo;
    try {
      final dlResult = await execute('browser_list_downloads', {});
      if (dlResult.success && !dlResult.output.contains('"total":0')) {
        downloadsInfo = dlResult.output;
      }
    } catch (e) {
      debugPrint('[BrowserToolHandler] downloads list error: $e');
    }

    // Page fingerprint
    final elementCount = elements.length;
    final fp = '$url|$elementCount|${pageText.hashCode}';

    return BrowserPageState(
      url: url,
      pageText: pageText,
      elements: elements,
      captchaWarning: captchaWarning,
      downloadsInfo: downloadsInfo,
      pageFingerprint: fp,
    );
  }

  // ── IBrowserBackend: lifecycle ──────────────────────────────────

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  // Human-in-the-loop
  @override
  Future<String?> Function(String reason, String? prompt)? onHumanAssist;

  // Download tracking (populated by WebView's onDownloadStartRequest)
  final List<Map<String, String>> _downloads = [];
  static const _maxDownloads = 200;

  void recordDownload(String url, String? suggestedFilename, String? mimeType, String? filePath) {
    if (_downloads.length >= _maxDownloads) {
      _downloads.removeRange(0, _downloads.length - _maxDownloads + 1);
    }
    _downloads.add({
      'url': url,
      'filename': suggestedFilename ?? '',
      'mimeType': mimeType ?? '',
      'filePath': filePath ?? '',
      'time': DateTime.now().toIso8601String(),
    });
  }

  void _cleanupStaleControllers() {
    final tabs = widgetRef?.read(browserTabsProvider) ?? [];
    final activeIds = tabs.map((t) => t.id).toSet();
    controllers.removeWhere((id, _) => !activeIds.contains(id));
  }

  InAppWebViewController? _resolveController(String? tabId) {
    if (controllers.isEmpty) return null;
    if (tabId != null) {
      return controllers[tabId];
    }
    final tabs = widgetRef?.read(browserTabsProvider) ?? [];
    final activeIdx = widgetRef?.read(browserActiveTabIndexProvider) ?? 0;
    if (activeIdx >= tabs.length) return null;
    return controllers[tabs[activeIdx].id];
  }

  @override
  Future<ToolResult> execute(
      String toolName, Map<String, dynamic> params) async {
    final tabId = params['tabId'] as String?;

    switch (toolName) {
      case 'browser_open_tab':
        return _openTab(params);
      case 'browser_close_tab':
        return _closeTab(params);
      case 'browser_switch_tab':
        return _switchTab(params);
      case 'browser_get_url':
        return _getUrlFromState(tabId);
      case 'browser_get_title':
        return _getTitleFromState(tabId);
      case 'browser_list_downloads':
        return _listDownloads();
      case 'browser_human_assist':
        return _humanAssist(params);
      case 'browser_search':
        return _searchWeb(params);
    }

    final controller = _resolveController(tabId);
    if (controller == null) {
      return ToolResult(
        toolName: toolName,
        success: false,
        output: '',
        error: 'No browser tab open. Use browser_open_tab first.',
      );
    }

    switch (toolName) {
      case 'browser_navigate':
        return _navigate(controller, params);
      case 'browser_get_content':
        return _getContent(controller, params);
      case 'browser_summarize':
      case 'browser_extract':
        return _browserSummarize(controller, params);
      case 'browser_execute_js':
        return _executeJs(controller, params);
      case 'browser_click':
        return _click(controller, params);
      case 'browser_type':
        return _type(controller, params);
      case 'browser_screenshot':
        return _screenshot(controller);
      case 'browser_scroll':
        return _scroll(controller, params);
      case 'browser_go_back':
        return _goBack(controller);
      case 'browser_go_forward':
        return _goForward(controller);
      case 'browser_wait':
        return _wait(controller, params);
      case 'browser_load_html':
        return _loadHtml(controller, params);
      case 'browser_find':
        return _find(controller, params);
      case 'browser_get_elements':
        return _getElements(controller);
      case 'browser_screenshot_element':
        return _screenshotElement(controller, params);
      case 'browser_detect_captcha':
        return _detectCaptcha(controller);
      case 'browser_save_cookies':
        return _saveCookies(controller);
      case 'browser_restore_cookies':
        return _restoreCookies(controller, params);
      case 'browser_detect_form_result':
        return _detectFormResult(controller);
      case 'browser_select_dropdown':
        return _selectDropdown(controller, params);
      case 'browser_get_dropdown_options':
        return _getDropdownOptions(controller, params);
      case 'browser_scroll_and_collect':
        return _scrollAndCollect(controller, params);
      case 'browser_check_errors':
        return _checkPageErrors(controller);
      case 'browser_clipboard_copy':
        return _clipboardCopy(controller, params);
      case 'browser_clipboard_paste':
        return _clipboardPaste(controller, params);
      case 'browser_wait_for':
        return _waitFor(controller, params);
      case 'browser_hover':
        return _hover(controller, params);
      case 'browser_press_key':
        return _pressKey(controller, params);
      case 'browser_drag':
        return _drag(controller, params);
      case 'browser_get_iframe':
        return _getIframe(controller, params);
      case 'browser_upload_file':
        return _uploadFile(controller, params);
      case 'browser_save_as_pdf':
        return _saveAsPdf(controller, params);
      case 'browser_search_page':
        return _searchPage(controller, params);
      case 'browser_find_elements':
        return _findElements(controller, params);
      case 'browser_extract_design':
        return _extractDesign(controller, params);

      // Page control
      case 'browser_reload':
      case 'browser_refresh':
        return _reload(controller);
      case 'browser_stop':
        return _stopLoading(controller);

      // Diagnostics
      case 'browser_get_viewport':
        return _getViewport(controller);
      case 'browser_get_dom':
        return _getDom(controller, params);
      case 'browser_get_cookies':
        return _saveCookies(controller); // alias
      case 'browser_delete_cookies':
        return _deleteCookies(controller);
      case 'browser_clear_cache':
        return _clearCache(controller);

      // Form
      case 'browser_fill_form':
        return _fillForm(controller, params);
      case 'browser_detect_form':
        return _detectFormResult(controller); // alias

      // Injection
      case 'browser_add_script':
        return _executeJs(controller, params);
      case 'browser_add_stylesheet':
        return _addStylesheetJs(controller, params);

      // Network (JS backend: not available)
      case 'browser_get_network_requests':
      case 'browser_get_cdp_logs':
      case 'browser_get_headers':
        return ToolResult(
          toolName: toolName,
          success: false,
          output: '',
          error: 'This tool requires the CDP backend (not available in JS mode).',
        );

      default:
        return ToolResult(
          toolName: toolName,
          success: false,
          output: '',
          error: 'Unknown browser tool: $toolName',
        );
    }
  }

  Future<ToolResult> _navigate(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final rawUrl = params['url'] as String;
    String url = rawUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return ToolResult(
        toolName: 'browser_navigate',
        success: false,
        output: '',
        error: 'Invalid URL: $rawUrl',
      );
    }
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    // Wait for page to finish loading
    try {
      await controller.evaluateJavascript(source: '''
        new Promise(function(resolve) {
          if (document.readyState === 'complete') return resolve('already ready');
          var start = Date.now();
          var timeout = 20000;
          function check() {
            if (document.readyState === 'complete') return resolve('loaded');
            if (Date.now() - start > timeout) return resolve('timeout after ' + timeout + 'ms, readyState=' + document.readyState);
            requestAnimationFrame(check);
          }
          check();
        })
      ''');
      // Extra settling time for SPA frameworks
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (_) {}
    final currentUrl = await controller.getUrl();
    return ToolResult(
      toolName: 'browser_navigate',
      success: true,
      output: 'Navigated to $url (current: $currentUrl)',
    );
  }

  Future<ToolResult> _loadHtml(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final html = params['html'] as String;
    final baseUrl = params['baseUrl'] as String?;
    try {
      await controller.loadData(
        data: html,
        mimeType: 'text/html',
        baseUrl: baseUrl != null ? WebUri(baseUrl) : null,
      );
      final preview =
          html.length > 100 ? '${html.substring(0, 100)}...' : html;
      return ToolResult(
        toolName: 'browser_load_html',
        success: true,
        output: 'HTML loaded and rendered ($preview)',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_load_html',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  Future<ToolResult> _getContent(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final selector = params['selector'] as String?;
    final format = params['format'] as String?;
    final includeHtml = params['includeHtml'] == true;
    final useMarkdown = format == 'markdown';

    // Markdown format: get full HTML, pipe through HtmlPipeline
    if (useMarkdown) {
      try {
        final js = selector != null
            ? "(function(){var el=document.querySelector('${_escapeJs(selector)}'); return el?el.outerHTML||'';})()"
            : 'document.documentElement.outerHTML';
        final result = await controller.evaluateJavascript(source: js);
        final html = result?.toString() ?? '';
        if (html.isEmpty) {
          return const ToolResult(
            toolName: 'browser_get_content',
            success: true,
            output: '(page has no visible text content)',
          );
        }
        final pipeline = HtmlPipeline(html);
        final markdown = pipeline.toMarkdown();
        if (markdown.isEmpty) {
          return const ToolResult(
            toolName: 'browser_get_content',
            success: true,
            output: '(page content could not be extracted — may be a JS-rendered app)',
          );
        }
        final output = markdown.length > BrowserConstants.maxContentSize
            ? '${markdown.substring(0, BrowserConstants.maxContentSize)}\n\n[Content truncated. Total: ${markdown.length} chars]'
            : markdown;
        return ToolResult(
          toolName: 'browser_get_content',
          success: true,
          output: output,
        );
      } catch (e) {
        print('[BrowserTool] error: $e');
        return ToolResult(
          toolName: 'browser_get_content',
          success: false,
          output: '',
          error: 'Markdown extraction failed: $e',
        );
      }
    }

    // Legacy text format
    String js;
    if (selector != null) {
      final escaped = _escapeJs(selector);
      js = includeHtml
          ? "(function(){var el=document.querySelector('$escaped'); return el?el.outerHTML:'Selector not found: $escaped';})()"
          : "(function(){var el=document.querySelector('$escaped'); return el?el.innerText:'Selector not found: $escaped';})()";
    } else {
      js = includeHtml
          ? 'document.documentElement.outerHTML'
          : 'document.body?document.body.innerText:document.documentElement.innerText';
    }
    try {
      final result = await controller.evaluateJavascript(source: js);
      String text = result?.toString() ?? '';
      if (text.length > BrowserConstants.maxContentSize) {
        final total = text.length;
        text =
            '${text.substring(0, BrowserConstants.maxContentSize)}\n\n[Content truncated. Total: $total chars]';
      }
      if (text.isEmpty) text = '(page has no visible text content)';
      return ToolResult(
        toolName: 'browser_get_content',
        success: true,
        output: text,
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_get_content',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  Future<ToolResult> _browserSummarize(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    try {
      const js = 'document.documentElement.outerHTML';
      final result = await controller.evaluateJavascript(source: js);
      final html = result?.toString() ?? '';
      if (html.isEmpty) {
        return const ToolResult(
          toolName: 'browser_summarize',
          success: false,
          output: '',
          error: 'Page has no content',
        );
      }

      final pipeline = HtmlPipeline(html);
      final markdown = pipeline.toMarkdown();
      final meta = pipeline.extractMetadata('');
      final score = scoreContent(markdown, html);

      final buffer = StringBuffer();
      if (meta.title != null) buffer.writeln('# ${meta.title}');
      if (meta.siteName != null) buffer.writeln('**Source:** ${meta.siteName}');
      if (meta.author != null) buffer.writeln('**Author:** ${meta.author}');
      if (meta.publishedDate != null) buffer.writeln('**Published:** ${meta.publishedDate}');
      buffer.writeln('**Reading time:** ~${((markdown.length / 400).ceil())} min');
      buffer.writeln('**Quality score:** ${score.score.toStringAsFixed(0)}/100');
      if (score.reasons.isNotEmpty) {
        buffer.writeln('**Signals:** ${score.reasons.join(", ")}');
      }
      if (meta.description != null) buffer.writeln('\n> ${meta.description}');
      buffer.writeln('\n---\n');
      buffer.write(markdown.isNotEmpty ? markdown : '(No extractable content)');

      return ToolResult(
        toolName: 'browser_summarize',
        success: true,
        output: buffer.toString(),
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_summarize',
        success: false,
        output: '',
        error: 'Summarization failed: $e',
      );
    }
  }

  Future<ToolResult> _executeJs(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final code = params['code'] as String;
    try {
      final result = await controller.evaluateJavascript(source: code);
      return ToolResult(
        toolName: 'browser_execute_js',
        success: true,
        output: result?.toString() ?? 'undefined',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_execute_js',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  Future<ToolResult> _click(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final index = _paramInt(params, 'index');
    final selector = params['selector'] as String?;
    final coordinateX = _paramNum(params, 'coordinate_x');
    final coordinateY = _paramNum(params, 'coordinate_y');
    if (index == null && selector == null && (coordinateX == null || coordinateY == null)) {
      return const ToolResult(
        toolName: 'browser_click',
        success: false,
        output: '',
        error: 'Either index, selector, or (coordinate_x + coordinate_y) is required.',
      );
    }

    // Coordinate-based click (no element lookup needed)
    if (coordinateX != null && coordinateY != null) {
      final js = '''
(function() {
  var x = $coordinateX, y = $coordinateY;
  var el = document.elementFromPoint(x, y);
  var tag = el ? el.tagName : 'unknown';
  var opts = {bubbles: true, cancelable: true, view: window, clientX: x, clientY: y, button: 0};
  if (el) {
    el.dispatchEvent(new MouseEvent('mousedown', opts));
    el.dispatchEvent(new MouseEvent('mouseup', opts));
    el.dispatchEvent(new MouseEvent('click', opts));
    try { el.click(); } catch(e) {}
  }
  return JSON.stringify({success: true, tag: tag, coordinate: {x: x, y: y}});
})()
''';
      try {
        final result = await controller.evaluateJavascript(source: js);
        return ToolResult(
          toolName: 'browser_click',
          success: true,
          output: result?.toString() ?? '',
        );
      } catch (e) {
        print('[BrowserTool] error: $e');
        return ToolResult(
          toolName: 'browser_click',
          success: false,
          output: '',
          error: e.toString(),
        );
      }
    }

    final targetExpr = index != null
        ? "document.querySelector('[data-bu-index=\"$index\"]')"
        : "document.querySelector('${_escapeJs(selector!)}')";
    final notFoundMsg = index != null
        ? 'Element with index $index not found. Page may have changed — use browser_get_elements to refresh.'
        : 'Element not found: $selector';

    final js = '''
(function() {
  var el = $targetExpr;
  if (!el) return JSON.stringify({error: '$notFoundMsg'});
  el.scrollIntoView({behavior: 'smooth', block: 'center'});
  var rect = el.getBoundingClientRect();
  var x = rect.left + rect.width / 2;
  var y = rect.top + rect.height / 2;
  var opts = {bubbles: true, cancelable: true, view: window, clientX: x, clientY: y, button: 0};
  el.dispatchEvent(new MouseEvent('mousedown', opts));
  el.dispatchEvent(new MouseEvent('mouseup', opts));
  el.dispatchEvent(new MouseEvent('click', opts));
  try { el.click(); } catch(e) {}
  return JSON.stringify({success: true, tag: el.tagName, text: (el.textContent||'').trim().substring(0, 150)});
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_click',
        success: true,
        output: result?.toString() ?? '',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_click',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  Future<ToolResult> _type(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final index = _paramInt(params, 'index');
    final selector = params['selector'] as String?;
    final text = _escapeJs(params['text'] as String? ?? '');
    final clear = params['clear'] as bool? ?? true;
    if (index == null && selector == null) {
      return const ToolResult(
        toolName: 'browser_type',
        success: false,
        output: '',
        error: 'Either index or selector is required.',
      );
    }
    if (text.isEmpty && !clear) {
      return const ToolResult(
        toolName: 'browser_type',
        success: false,
        output: '',
        error: 'text is required when clear is false, or pass text="" to clear only.',
      );
    }

    final targetExpr = index != null
        ? "document.querySelector('[data-bu-index=\"$index\"]')"
        : "document.querySelector('${_escapeJs(selector!)}')";
    final notFoundMsg = index != null
        ? 'Element with index $index not found. Page may have changed — use browser_get_elements to refresh.'
        : 'Element not found: $selector';

    final js = '''
(function() {
  var el = $targetExpr;
  if (!el) return 'ERROR: $notFoundMsg';
  el.scrollIntoView({behavior: 'smooth', block: 'center'});
  el.focus();
  var clearFirst = $clear;
  var newText = '$text';
  if (clearFirst) {
    el.value = '';
    el.dispatchEvent(new Event('input', {bubbles: true}));
  }
  if (newText) {
    var nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
    if (nativeSetter && nativeSetter.set) {
      nativeSetter.set.call(el, newText);
    } else if (window.HTMLTextAreaElement) {
      var taSetter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value');
      if (taSetter && taSetter.set) taSetter.set.call(el, newText);
      else el.value = newText;
    } else {
      el.value = newText;
    }
  }
  el.dispatchEvent(new Event('input', {bubbles: true}));
  el.dispatchEvent(new Event('change', {bubbles: true}));

  // Check for autocomplete/combobox fields
  var role = el.getAttribute('role') || '';
  var autocomplete = el.getAttribute('aria-autocomplete') || '';
  var isCombobox = role === 'combobox' || (autocomplete && autocomplete !== 'none');
  var hint = isCombobox ? '\\n\\u{1f4a1} This is an autocomplete field. Wait for suggestions to appear, then click the correct suggestion instead of pressing Enter.' : '';

  return 'Typed ' + (clearFirst ? '(cleared) ' : '') + 'into ' + el.tagName + (el.name ? '#' + el.name : '') + (newText ? ': ' + newText : ' - cleared only') + hint;
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_type',
        success: true,
        output: result?.toString() ?? '',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_type',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  Future<ToolResult> _screenshot(InAppWebViewController controller) async {
    try {
      final bytes = await controller.takeScreenshot();
      if (bytes == null) {
        return const ToolResult(
          toolName: 'browser_screenshot',
          success: false,
          output: '',
          error: 'Failed to capture screenshot.',
        );
      }
      final base64Str = base64Encode(bytes);
      return ToolResult(
        toolName: 'browser_screenshot',
        success: true,
        output:
            '[Screenshot captured: ${bytes.length} bytes]',
        data: base64Str,
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_screenshot',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  Future<ToolResult> _scroll(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final direction = params['direction'] as String;
    final amount = _paramDouble(params, 'amount');
    String js;
    switch (direction) {
      case 'up':
        js = 'window.scrollBy(0, ${-(amount ?? 800)})';
        break;
      case 'down':
        js = 'window.scrollBy(0, ${amount ?? 800})';
        break;
      case 'top':
        js = 'window.scrollTo(0, 0)';
        break;
      case 'bottom':
        js = 'window.scrollTo(0, document.body.scrollHeight)';
        break;
      default:
        return ToolResult(
          toolName: 'browser_scroll',
          success: false,
          output: '',
          error: 'Invalid direction: $direction. Use up/down/top/bottom.',
        );
    }
    await controller.evaluateJavascript(source: js);
    return ToolResult(
      toolName: 'browser_scroll',
      success: true,
      output: 'Scrolled $direction',
    );
  }

  Future<ToolResult> _find(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final text = _escapeJs(params['text'] as String);
    final js = '''
(function() {
  if (!window.__browserFindHighlights) window.__browserFindHighlights = [];
  var old = window.__browserFindHighlights;
  for (var i = 0; i < old.length; i++) {
    var el = old[i];
    var parent = el.parentNode;
    if (parent) {
      parent.replaceChild(document.createTextNode(el.textContent), el);
      parent.normalize();
    }
  }
  window.__browserFindHighlights = [];
  if (!('$text')) return JSON.stringify({count: 0, message: 'empty search'});
  var count = 0;
  var first = null;
  function walk(node) {
    if (node.nodeType === 3) {
      var idx = node.textContent.toLowerCase().indexOf('${text.toLowerCase()}');
      if (idx >= 0) {
        if (!first) first = node.parentElement;
        var span = document.createElement('mark');
        span.style.cssText = 'background:#FFEB3B;color:#000;padding:0 2px;border-radius:2px';
        span.textContent = node.textContent.substring(idx, idx + ${text.length});
        var after = node.splitText(idx);
        after.splitText(${text.length});
        after.parentNode.replaceChild(span, after);
        window.__browserFindHighlights.push(span);
        count++;
      }
    } else if (node.nodeType === 1 && !/^(SCRIPT|STYLE|MARK|NOSCRIPT)\$/i.test(node.tagName)) {
      for (var c = node.firstChild; c; c = c.nextSibling) walk(c);
    }
  }
  if (document.body) walk(document.body);
  if (first) first.scrollIntoView({behavior: 'smooth', block: 'center'});
  return JSON.stringify({count: count, message: count > 0 ? 'Found ' + count + ' match(es)' : 'No matches'});
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_find',
        success: true,
        output: result?.toString() ?? '{"count":0}',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_find',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  Future<ToolResult> _goBack(InAppWebViewController controller) async {
    if (await controller.canGoBack()) {
      await controller.goBack();
      return const ToolResult(
        toolName: 'browser_go_back',
        success: true,
        output: 'Went back',
      );
    }
    return const ToolResult(
      toolName: 'browser_go_back',
      success: false,
      output: '',
      error: 'No back history',
    );
  }

  Future<ToolResult> _goForward(InAppWebViewController controller) async {
    if (await controller.canGoForward()) {
      await controller.goForward();
      return const ToolResult(
        toolName: 'browser_go_forward',
        success: true,
        output: 'Went forward',
      );
    }
    return const ToolResult(
      toolName: 'browser_go_forward',
      success: false,
      output: '',
      error: 'No forward history',
    );
  }

  Future<ToolResult> _wait(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final timeoutMs =
        (_paramNum(params, 'timeout')?.toInt() ?? 3000);
    final selector = params['selector'] as String?;
    final effectiveTimeout =
        timeoutMs.clamp(0, BrowserConstants.maxWaitTimeout.inMilliseconds);

    if (selector != null) {
      final escaped = _escapeJs(selector);
      final js = '''
new Promise(function(resolve) {
  var start = Date.now();
  function check() {
    if (document.querySelector('$escaped')) return resolve('found: $escaped');
    if (Date.now() - start > $effectiveTimeout) return resolve('timeout: element not found after ${effectiveTimeout}ms');
    requestAnimationFrame(check);
  }
  check();
})
''';
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_wait',
        success: true,
        output: result?.toString() ?? 'wait completed',
      );
    } else {
      await Future.delayed(Duration(milliseconds: effectiveTimeout));
      return ToolResult(
        toolName: 'browser_wait',
        success: true,
        output: 'Waited ${effectiveTimeout}ms',
      );
    }
  }

  Future<ToolResult> _openTab(Map<String, dynamic> params) async {
    final url = params['url'] as String?;
    widgetRef?.read(browserTabsProvider.notifier).addTab(url: url);
    final newLen = widgetRef?.read(browserTabsProvider).length ?? 0;
    widgetRef?.read(browserActiveTabIndexProvider.notifier).state = newLen - 1;
    widgetRef?.read(browserPanelVisibleProvider.notifier).state = true;
    widgetRef?.read(browserEngineActiveProvider.notifier).state = true;
    final newTab = widgetRef?.read(browserTabsProvider).last;
    return ToolResult(
      toolName: 'browser_open_tab',
      success: true,
      output:
          'Opened new tab (ID: ${newTab?.id ?? 'unknown'}). Browser is now visible.',
    );
  }

  Future<ToolResult> _closeTab(Map<String, dynamic> params) async {
    final tabId = params['tabId'] as String?;
    final tabs = widgetRef?.read(browserTabsProvider) ?? [];
    int idx = -1;
    if (tabId != null) {
      idx = tabs.indexWhere((t) => t.id == tabId);
    } else {
      idx = widgetRef?.read(browserActiveTabIndexProvider) ?? 0;
    }
    if (idx < 0 || tabs.length <= 1) {
      return const ToolResult(
        toolName: 'browser_close_tab',
        success: false,
        output: '',
        error: 'Cannot close: tab not found or it is the only tab.',
      );
    }
    widgetRef?.read(browserTabsProvider.notifier).closeTab(idx);
    _cleanupStaleControllers();
    final newLen = widgetRef?.read(browserTabsProvider).length ?? 1;
    final currentIdx = widgetRef?.read(browserActiveTabIndexProvider) ?? 0;
    if (currentIdx >= newLen) {
      widgetRef?.read(browserActiveTabIndexProvider.notifier).state = newLen - 1;
    }
    return const ToolResult(
      toolName: 'browser_close_tab',
      success: true,
      output: 'Closed tab',
    );
  }

  Future<ToolResult> _switchTab(Map<String, dynamic> params) async {
    final tabIdx = _paramInt(params, 'tabIndex');
    final tabId = params['tabId'] as String?;
    final tabs = widgetRef?.read(browserTabsProvider) ?? [];
    if (tabs.length <= 1) {
      return const ToolResult(
        toolName: 'browser_switch_tab',
        success: false,
        output: '',
        error: 'Only one tab open. Use browser_open_tab to create more tabs.',
      );
    }
    if (tabIdx != null && tabIdx >= 0 && tabIdx < tabs.length) {
      widgetRef?.read(browserActiveTabIndexProvider.notifier).state = tabIdx;
      return ToolResult(
        toolName: 'browser_switch_tab',
        success: true,
        output: 'Switched to tab $tabIdx: ${tabs[tabIdx].title}',
      );
    }
    if (tabId != null) {
      for (int i = 0; i < tabs.length; i++) {
        if (tabs[i].id == tabId) {
          widgetRef?.read(browserActiveTabIndexProvider.notifier).state = i;
          return ToolResult(
            toolName: 'browser_switch_tab',
            success: true,
            output: 'Switched to tab $i: ${tabs[i].title}',
          );
        }
      }
    }
    // List all tabs if no valid target specified
    final sb = StringBuffer();
    for (int i = 0; i < tabs.length; i++) {
      sb.writeln('  [$i] ${tabs[i].title.isNotEmpty ? tabs[i].title : '(empty)'} — ${tabs[i].url}');
    }
    return ToolResult(
      toolName: 'browser_switch_tab',
      success: true,
      output: 'Available tabs:\n$sb\nUse tabIndex=N to switch.',
    );
  }

  Future<ToolResult> _getUrlFromState(String? tabId) async {
    final tabs = widgetRef?.read(browserTabsProvider) ?? [];
    final tab = tabId != null
        ? tabs.where((t) => t.id == tabId).firstOrNull
        : widgetRef?.read(browserActiveTabProvider);
    final url = tab?.url ?? '';
    if (url.isEmpty) {
      return const ToolResult(
        toolName: 'browser_get_url',
        success: true,
        output: '(about:blank)',
      );
    }
    return ToolResult(
      toolName: 'browser_get_url',
      success: true,
      output: url,
    );
  }

  Future<ToolResult> _getTitleFromState(String? tabId) {
    final tabs = widgetRef?.read(browserTabsProvider) ?? [];
    final tab = tabId != null
        ? tabs.where((t) => t.id == tabId).firstOrNull
        : widgetRef?.read(browserActiveTabProvider);
    return Future.value(ToolResult(
      toolName: 'browser_get_title',
      success: true,
      output: tab?.title ?? '(no page loaded)',
    ));
  }

  Future<ToolResult> _getElements(InAppWebViewController controller) async {
    const js = r'''
(function() {
  document.querySelectorAll('[data-bu-index]').forEach(function(el) {
    el.removeAttribute('data-bu-index');
  });

  var seen = [];
  var results = [];
  var index = 1;
  var MAX = 80;
  var vh = window.innerHeight;

  function isVisible(el) {
    var r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) return false;
    var s = window.getComputedStyle(el);
    if (s.display === 'none' || s.visibility === 'hidden' || s.opacity === '0') return false;
    if (r.bottom < -vh * 2 || r.top > vh * 3) return false;
    return true;
  }

  function getText(el) {
    var tag = el.tagName.toLowerCase();
    if (tag === 'input' || tag === 'textarea') {
      return el.placeholder || el.value || el.name || el.getAttribute('aria-label') || '';
    }
    if (tag === 'img') return el.alt || '';
    if (tag === 'select') {
      var opt = el.options[el.selectedIndex];
      return (opt ? opt.text : '') || el.name || '';
    }
    if (tag === 'a') {
      var t = (el.textContent || '').trim().substring(0, 80);
      if (!t && el.getAttribute('aria-label')) t = el.getAttribute('aria-label');
      return t;
    }
    if (tag === 'button') {
      var t = (el.textContent || el.value || '').trim().substring(0, 80);
      if (!t) t = el.getAttribute('aria-label') || el.name || el.type || '';
      return t;
    }
    if (tag === 'iframe' || tag === 'frame') {
      var src = el.src || el.name || '';
      try {
        if (el.contentDocument) {
          var cnt = el.contentDocument.querySelectorAll('a[href],button,input,select,textarea').length;
          src += ' [same-origin, ' + cnt + ' interactive]';
        }
      } catch(e) { src += ' [cross-origin]'; }
      return src.substring(0, 120);
    }
    return (el.textContent || '').trim().substring(0, 80);
  }

  function isInteractive(el) {
    var tag = el.tagName.toLowerCase();
    if (['a', 'button', 'input', 'select', 'textarea', 'details', 'summary', 'iframe', 'frame'].indexOf(tag) >= 0) return true;
    if (tag === 'a' && !el.href) return false;
    if (tag === 'input' && el.type === 'hidden') return false;
    if (el.hasAttribute('onclick')) return true;
    if (el.hasAttribute('tabindex') && el.getAttribute('tabindex') !== '-1') return true;
    if (el.isContentEditable) return true;
    var role = el.getAttribute('role');
    if (role && /button|link|checkbox|menuitem|tab|switch|option|combobox|listbox|textbox|radio|slider|spinbutton/i.test(role)) return true;
    if (el.hasAttribute('data-action') || el.hasAttribute('data-click') || el.hasAttribute('data-ng-click') || el.hasAttribute('@click') || el.hasAttribute('v-on:click') || el.hasAttribute(':onclick')) return true;
    var s = window.getComputedStyle(el);
    if (s.cursor === 'pointer') return true;
    return false;
  }

  function getDepth(el) {
    var d = 0, p = el.parentElement;
    while (p) { d++; p = p.parentElement; }
    return d;
  }
  function isScrollable(el) {
    var s = window.getComputedStyle(el);
    var overflowY = s.overflowY || s.overflow || '';
    if (overflowY === 'hidden' || overflowY === 'visible') return false;
    return el.scrollHeight > el.clientHeight + 5;
  }
  function getScrollInfo(el) {
    var sh = el.scrollHeight, ch = el.clientHeight, st = el.scrollTop;
    var pct = ch > 0 ? Math.round(st / (sh - ch) * 100) : 0;
    return '|SCROLL| ' + pct + '% (' + Math.round(st) + '/' + Math.round(sh) + ')';
  }

  function addElement(el, depthOverride) {
    if (!isVisible(el)) return;
    if (!isInteractive(el)) return;
    // Deduplicate
    if (seen.indexOf(el) >= 0) return;
    if (seen.length >= MAX) return;
    seen.push(el);
    el.setAttribute('data-bu-index', index);

    var tag = el.tagName.toLowerCase();
    var disabled = el.disabled || el.getAttribute('aria-disabled') === 'true';
    var text = getText(el);
    if (disabled) text = '(DISABLED) ' + text;
    var depth = depthOverride != null ? depthOverride : getDepth(el);
    var scrollable = isScrollable(el);
    var scrollInfo = scrollable ? getScrollInfo(el) : '';

    results.push({
      _el: el,
      index: index,
      tag: tag,
      text: text.substring(0, 80),
      type: (el.type || '').substring(0, 30),
      id: (el.id || '').substring(0, 50),
      placeholder: (el.placeholder || '').substring(0, 50),
      name: (el.name || '').substring(0, 50),
      href: (el.href || '').substring(0, 120),
      ariaLabel: (el.getAttribute('aria-label') || '').substring(0, 80),
      role: (el.getAttribute('role') || '').substring(0, 30),
      disabled: disabled,
      depth: depth,
      scrollable: scrollable,
      scrollInfo: scrollInfo
    });
    index++;
  }

  // Phase 1: explicit interactive elements
  var phase1;
  try {
    phase1 = document.querySelectorAll(
      'a[href], button, input:not([type="hidden"]), select, textarea, ' +
      '[role="button"], [role="link"], [role="checkbox"], [role="menuitem"], ' +
      '[role="tab"], [role="textbox"], [role="combobox"], [role="listbox"], ' +
      '[role="radio"], [role="switch"], [role="option"], [role="slider"], ' +
      '[role="spinbutton"], [role="searchbox"], ' +
      '[onclick], [contenteditable="true"], details, summary, iframe, frame, ' +
      '[tabindex]:not([tabindex="-1"]), ' +
      '[data-action], [data-click], [data-ng-click], [@click], [v-on\\:click]'
    );
  } catch(e) {
    phase1 = document.querySelectorAll('a[href], button, input, select, textarea, [role="button"], [onclick]');
  }
  for (var i = 0; i < phase1.length; i++) addElement(phase1[i]);

  // Phase 2: cursor:pointer elements not yet captured (catches div-buttons, custom controls)
  // Only scan reasonable container tags, skip script/style/head/meta
  var phase2tags = ['div', 'span', 'li', 'ul', 'ol', 'td', 'th', 'tr', 'article', 'section', 'nav', 'header', 'footer', 'label', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'dl', 'dt', 'dd', 'figure', 'figcaption', 'main', 'aside', 'strong', 'em', 'b', 'i', 'u', 'small', 'mark'];
  if (seen.length < MAX) {
    var phase2 = document.querySelectorAll(phase2tags.join(','));
    for (var i = 0; i < phase2.length && i < 500 && seen.length < MAX; i++) {
      if (seen.indexOf(phase2[i]) >= 0) continue;
      if (!isVisible(phase2[i])) continue;
      var s = window.getComputedStyle(phase2[i]);
      if (s.cursor === 'pointer') addElement(phase2[i]);
    }
  }

  // Phase 3: label elements that wrap controls
  if (seen.length < MAX) {
    var labels = document.querySelectorAll('label');
    for (var i = 0; i < labels.length && i < 200 && seen.length < MAX; i++) {
      var lbl = labels[i];
      if (seen.indexOf(lbl) >= 0) continue;
      // Check if this label wraps an input
      var child = lbl.querySelector('input, select, textarea');
      if (child && seen.indexOf(child) >= 0) {
        // Propagate label text to the input
        var childEntry = results.find(function(r) {
          var el = document.querySelector('[data-bu-index="' + r.index + '"]');
          return el === child;
        });
        if (childEntry && !childEntry.text) {
          childEntry.text = (lbl.textContent || '').trim().substring(0, 80);
        }
      }
    }
  }

  // Phase 4: same-origin iframe element expansion (up to 10 per iframe)
  if (seen.length < MAX) {
    var allFrames = document.querySelectorAll('iframe, frame');
    for (var fi = 0; fi < allFrames.length && seen.length < MAX; fi++) {
      var frame = allFrames[fi];
      if (seen.indexOf(frame) < 0) continue; // wasn't added as interactive, skip
      var fd = 0;
      try {
        if (frame.contentDocument) fd = frame.contentDocument.querySelectorAll('a[href],button,input,select,textarea,[role="button"],[onclick]').length;
      } catch(e) {}
      if (fd === 0) continue;
      try {
        var fdoc = frame.contentDocument;
        var fPhase = fdoc.querySelectorAll('a[href], button, input:not([type="hidden"]), select, textarea, [role="button"], [role="link"], [role="textbox"], [onclick]');
        for (var j = 0; j < fPhase.length && seen.length < MAX && j < 10; j++) {
          if (!isVisible(fPhase[j])) continue;
          if (!isInteractive(fPhase[j])) continue;
          if (seen.indexOf(fPhase[j]) >= 0) continue;
          seen.push(fPhase[j]);
          fPhase[j].setAttribute('data-bu-index', index);
          var ftag = fPhase[j].tagName.toLowerCase();
          var ftext = getText(fPhase[j]);
          var fdisabled = fPhase[j].disabled || fPhase[j].getAttribute('aria-disabled') === 'true';
          if (fdisabled) ftext = '(DISABLED) ' + ftext;
          results.push({
            _el: fPhase[j],
            index: index,
            tag: ftag,
            text: ('[iframe] ' + ftext).substring(0, 80),
            type: (fPhase[j].type || '').substring(0, 30),
            id: (fPhase[j].id || '').substring(0, 50),
            placeholder: (fPhase[j].placeholder || '').substring(0, 50),
            name: (fPhase[j].name || '').substring(0, 50),
            href: (fPhase[j].href || '').substring(0, 120),
            ariaLabel: (fPhase[j].getAttribute('aria-label') || '').substring(0, 80),
            role: (fPhase[j].getAttribute('role') || '').substring(0, 30),
            disabled: fdisabled,
            depth: getDepth(frame) + 1,
            scrollable: false,
            scrollInfo: ''
          });
          index++;
        }
      } catch(e) {}
    }
  }

  // Sort: form elements first for visibility, then links/buttons, then others
  var priorityTag = {'input':1, 'select':1, 'textarea':1, 'button':2, 'a':3};
  results.sort(function(a, b) { return (priorityTag[a.tag] || 4) - (priorityTag[b.tag] || 4); });
  // Re-number and re-assign DOM attributes in sorted order
  document.querySelectorAll('[data-bu-index]').forEach(function(el) { el.removeAttribute('data-bu-index'); });
  for (var i = 0; i < results.length; i++) {
    results[i].index = i + 1;
    if (results[i]._el) results[i]._el.setAttribute('data-bu-index', i + 1);
    delete results[i]._el; // clean up internal ref, don't send to dart
  }

  var hitLimit = seen.length >= MAX;
  var extra = hitLimit ? ' (more elements exist - scroll or use browser_search_page to find specific content)' : '';

  // Captcha scan (merged — saves one evaluateJavascript call per step)
  var captcha = {found: false};
  if (document.querySelector('.g-recaptcha, iframe[src*="recaptcha"], iframe[src*="google.com/recaptcha"], .h-captcha, iframe[src*="hcaptcha"], div.cf-turnstile, iframe[src*="turnstile"]')) {
    captcha = {found: true, type: 'reCAPTCHA/hCaptcha/Turnstile iframe', hint: '需要用户点击验证'};
  } else {
    var body = (document.body ? document.body.innerText.toLowerCase() : '');
    var patterns = ['验证码', '人机验证', '滑块验证', '拼图验证', '点击验证', 'captcha', 'security check'];
    for (var i = 0; i < patterns.length; i++) {
      if (body.indexOf(patterns[i]) >= 0) { captcha = {found: true, type: 'text_match', text: patterns[i], hint: '页面包含验证码相关文字'}; break; }
    }
    if (!captcha.found) {
      var imgs = document.querySelectorAll('img[src*="captcha"], img[src*="Captcha"], img[src*="code"], img[src*="verify"]');
      for (var j = 0; j < imgs.length; j++) {
        if (imgs[j].width > 30 && imgs[j].width < 400) { captcha = {found: true, type: 'captcha_image', src: imgs[j].src, hint: '疑似验证码图片'}; break; }
      }
    }
  }

  return JSON.stringify({elements: results, total: results.length, hint: 'Use index numbers for browser_click / browser_type' + extra, captcha: captcha});
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_get_elements',
        success: true,
        output: result?.toString() ?? '{"elements":[],"total":0}',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_get_elements',
        success: false,
        output: '{"elements":[],"total":0}',
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // Human-in-the-loop
  // ============================================================

  Future<ToolResult> _humanAssist(Map<String, dynamic> params) async {
    final reason = params['reason'] as String? ?? 'needs human help';
    final prompt = params['prompt'] as String?;
    if (onHumanAssist == null) {
      return const ToolResult(
        toolName: 'browser_human_assist',
        success: false,
        output: '',
        error: 'Human assist not available (no callback registered).',
      );
    }
    try {
      final response = await onHumanAssist!(reason, prompt);
      if (response == null || response.isEmpty) {
        return const ToolResult(
          toolName: 'browser_human_assist',
          success: false,
          output: 'User cancelled or did not respond.',
        );
      }
      return ToolResult(
        toolName: 'browser_human_assist',
        success: true,
        output: 'User responded: $response',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_human_assist',
        success: false,
        output: '',
        error: 'Human assist failed: $e',
      );
    }
  }

  // ============================================================
  // Web search (DuckDuckGo / Google / Bing)
  // ============================================================

  Future<ToolResult> _searchWeb(Map<String, dynamic> params) async {
    final query = params['query'] as String? ?? '';
    final engine = params['engine'] as String? ?? 'duckduckgo';
    if (query.isEmpty) {
      return const ToolResult(
        toolName: 'browser_search',
        success: false,
        output: '',
        error: 'query is required.',
      );
    }
    final encoded = Uri.encodeQueryComponent(query);
    String url;
    switch (engine.toLowerCase()) {
      case 'google':
        url = 'https://www.google.com/search?q=$encoded';
        break;
      case 'bing':
        url = 'https://www.bing.com/search?q=$encoded';
        break;
      case 'duckduckgo':
      default:
        url = 'https://duckduckgo.com/?q=$encoded';
        break;
    }
    // Open search in a new tab
    return _openTab({'url': url});
  }

  // ============================================================
  // Download tracking
  // ============================================================

  Future<ToolResult> _listDownloads() async {
    if (_downloads.isEmpty) {
      return const ToolResult(
        toolName: 'browser_list_downloads',
        success: true,
        output: '{"downloads":[],"total":0}',
      );
    }
    return ToolResult(
      toolName: 'browser_list_downloads',
      success: true,
      output: jsonEncode({'downloads': _downloads, 'total': _downloads.length}),
    );
  }

  // ============================================================
  // Element screenshot
  // ============================================================

  Future<ToolResult> _screenshotElement(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final index = _paramInt(params, 'index');
    if (index == null) {
      return const ToolResult(
        toolName: 'browser_screenshot_element',
        success: false,
        output: '',
        error: 'index is required.',
      );
    }
    try {
      // Get element rect then take screenshot
      final rectJs = '''
(function() {
  var el = document.querySelector('[data-bu-index="$index"]');
  if (!el) return JSON.stringify({error: 'Element $index not found'});
  el.scrollIntoView({behavior: 'instant', block: 'center'});
  var r = el.getBoundingClientRect();
  return JSON.stringify({x: r.left, y: r.top, w: r.width, h: r.height, tag: el.tagName});
})()
''';
      final rectResult = await controller.evaluateJavascript(source: rectJs);
      final rectStr = rectResult?.toString() ?? '{}';
      final rect = jsonDecode(rectStr) as Map<String, dynamic>;
      if (rect.containsKey('error')) {
        return ToolResult(
          toolName: 'browser_screenshot_element',
          success: false,
          output: '',
          error: rect['error'] as String? ?? 'Element not found',
        );
      }

      final bytes = await controller.takeScreenshot();
      if (bytes == null) {
        return const ToolResult(
          toolName: 'browser_screenshot_element',
          success: false,
          output: '',
          error: 'Failed to capture screenshot.',
        );
      }

      final base64Str = base64Encode(bytes);
      final elX = (rect['x'] as num).toDouble();
      final elY = (rect['y'] as num).toDouble();
      final elW = (rect['w'] as num).toDouble();
      final elH = (rect['h'] as num).toDouble();

      return ToolResult(
        toolName: 'browser_screenshot_element',
        success: true,
        output: '[Element screenshot: <${rect['tag']}> at ($elX,$elY ${elW}x$elH)]',
        data: base64Str,
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_screenshot_element',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // Captcha detection
  // ============================================================

  Future<ToolResult> _detectCaptcha(InAppWebViewController controller) async {
    const js = r'''
(function() {
  // reCAPTCHA
  if (document.querySelector('.g-recaptcha, iframe[src*="recaptcha"], iframe[src*="google.com/recaptcha"], .h-captcha, iframe[src*="hcaptcha"]')) {
    return JSON.stringify({found: true, type: 'reCAPTCHA/hCaptcha iframe', hint: '需要用户点击验证'});
  }
  // Cloudflare Turnstile
  if (document.querySelector('div.cf-turnstile, iframe[src*="turnstile"]')) {
    return JSON.stringify({found: true, type: 'Cloudflare Turnstile', hint: '需要用户验证'});
  }
  // Chinese captcha patterns
  var body = document.body ? document.body.innerText : '';
  var patterns = ['验证码', '人机验证', '滑块验证', '拼图验证', '点击验证', 'captcha', 'security check'];
  for (var i = 0; i < patterns.length; i++) {
    if (body.toLowerCase().indexOf(patterns[i].toLowerCase()) >= 0) {
      return JSON.stringify({found: true, type: 'text_match', text: patterns[i], hint: '页面包含验证码相关文字'});
    }
  }
  // Image captcha: img with small dimensions and src containing captcha
  var imgs = document.querySelectorAll('img[src*="captcha"], img[src*="Captcha"], img[src*="code"], img[src*="verify"], img[src*="auth"]');
  for (var j = 0; j < imgs.length; j++) {
    if (imgs[j].width > 30 && imgs[j].width < 400) {
      return JSON.stringify({found: true, type: 'captcha_image', src: imgs[j].src, hint: '疑似验证码图片'});
    }
  }
  return JSON.stringify({found: false});
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_detect_captcha',
        success: true,
        output: result?.toString() ?? '{"found":false}',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_detect_captcha',
        success: false,
        output: '{"found":false}',
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // Cookie persistence
  // ============================================================

  Future<ToolResult> _saveCookies(InAppWebViewController controller) async {
    try {
      final url = await controller.getUrl();
      if (url == null) {
        return const ToolResult(
          toolName: 'browser_save_cookies',
          success: false,
          output: '',
          error: 'No page loaded.',
        );
      }
      final cookieManager = CookieManager.instance();
      final cookies = await cookieManager.getCookies(url: url);
      final cookieList = cookies.map((c) => {
        'name': c.name,
        'value': c.value,
        'domain': c.domain ?? '',
        'path': c.path ?? '/',
        'expiresDate': c.expiresDate,
        'isSecure': c.isSecure ?? false,
        'isHttpOnly': c.isHttpOnly ?? false,
      }).toList();

      return ToolResult(
        toolName: 'browser_save_cookies',
        success: true,
        output: jsonEncode({'saved': cookieList.length, 'cookies': cookieList}),
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_save_cookies',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  Future<ToolResult> _restoreCookies(InAppWebViewController controller, Map<String, dynamic> params) async {
    final cookiesJson = params['cookies'] as List?;
    if (cookiesJson == null || cookiesJson.isEmpty) {
      return const ToolResult(
        toolName: 'browser_restore_cookies',
        success: false,
        output: '',
        error: 'No cookies data provided. Use browser_save_cookies first to capture cookies.',
      );
    }
    try {
      final url = await controller.getUrl();
      final cookieManager = CookieManager.instance();
      int restored = 0;
      for (final c in cookiesJson) {
        if (c is! Map) continue;
        await cookieManager.setCookie(
          url: url ?? WebUri('https://${c['domain'] ?? ''}'),
          name: c['name'] as String? ?? '',
          value: c['value'] as String? ?? '',
          domain: c['domain'] as String? ?? '',
          path: c['path'] as String? ?? '/',
          isSecure: c['isSecure'] as bool? ?? false,
          isHttpOnly: c['isHttpOnly'] as bool? ?? false,
          expiresDate: c['expiresDate'] as int?,
        );
        restored++;
      }
      return ToolResult(
        toolName: 'browser_restore_cookies',
        success: true,
        output: 'Restored $restored cookies.',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_restore_cookies',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // Form result detection
  // ============================================================

  Future<ToolResult> _detectFormResult(InAppWebViewController controller) async {
    const js = r'''
(function() {
  var result = {success: null, messages: [], type: 'unknown'};

  // Check for common error patterns
  var errorSelectors = [
    '.error', '.alert-error', '.alert-danger', '.text-danger', '.field-error',
    '[role="alert"]', '.form-error', '.validation-error', '.input-error',
    '.error-message', '.err-msg', '.toast-error', '.notification-error',
    '.message-error', 'div.error', 'span.error', 'p.error'
  ];
  for (var i = 0; i < errorSelectors.length; i++) {
    var els = document.querySelectorAll(errorSelectors[i]);
    for (var j = 0; j < els.length; j++) {
      var text = (els[j].textContent || '').trim();
      if (text && text.length > 1 && text.length < 500) {
        result.messages.push({type: 'error', text: text, selector: errorSelectors[i]});
        result.type = 'error';
      }
    }
  }

  // Check for success patterns
  var successSelectors = [
    '.success', '.alert-success', '.text-success', '.message-success',
    '.toast-success', '.notification-success', '.form-success'
  ];
  for (var i = 0; i < successSelectors.length; i++) {
    var els = document.querySelectorAll(successSelectors[i]);
    for (var j = 0; j < els.length; j++) {
      var text = (els[j].textContent || '').trim();
      if (text && text.length > 1 && text.length < 500) {
        result.messages.push({type: 'success', text: text, selector: successSelectors[i]});
        if (result.type === 'unknown') result.type = 'success';
      }
    }
  }

  // Check URL/title for error indicators
  var title = document.title || '';
  if (/404|not found|500|error|forbidden|unauthorized/i.test(title)) {
    result.messages.push({type: 'error', text: 'Page title indicates error: ' + title});
    result.type = 'error';
  }

  // Check for "password wrong" / "incorrect" / "invalid" pattern in body text
  if (result.messages.length === 0) {
    var body = (document.body ? document.body.innerText : '').substring(0, 3000).toLowerCase();
    var errorKeywords = ['密码错误', '用户名不存在', '账号不存在', '验证码错误', '登录失败',
                         'incorrect password', 'wrong password', 'invalid credentials',
                         'login failed', 'account not found', 'please try again'];
    var successKeywords = ['登录成功', '注册成功', '提交成功', '保存成功', '操作成功',
                           'successfully', 'welcome back', 'logged in', 'registered'];

    for (var k = 0; k < errorKeywords.length; k++) {
      if (body.indexOf(errorKeywords[k]) >= 0) {
        result.messages.push({type: 'error', text: 'Found: "' + errorKeywords[k] + '"'});
        result.type = 'error';
        break;
      }
    }
    if (result.type === 'unknown') {
      for (var k = 0; k < successKeywords.length; k++) {
        if (body.indexOf(successKeywords[k]) >= 0) {
          result.messages.push({type: 'success', text: 'Found: "' + successKeywords[k] + '"'});
          result.type = 'success';
          break;
        }
      }
    }
  }

  result.success = result.type !== 'error';
  return JSON.stringify(result);
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_detect_form_result',
        success: true,
        output: result?.toString() ?? '{"type":"unknown","messages":[]}',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_detect_form_result',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // Dropdown — get options and select
  // ============================================================

  Future<ToolResult> _getDropdownOptions(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final index = _paramInt(params, 'index');
    if (index == null) {
      return const ToolResult(
        toolName: 'browser_get_dropdown_options',
        success: false,
        output: '',
        error: 'index is required.',
      );
    }
    final js = '''
(function() {
  var el = document.querySelector('[data-bu-index="$index"]');
  if (!el) return JSON.stringify({error: 'Element with index $index not found.'});
  var tag = el.tagName.toLowerCase();
  var options = [];
  if (tag === 'select') {
    for (var i = 0; i < el.options.length; i++) {
      var opt = el.options[i];
      if (!opt.disabled) {
        options.push({
          index: i + 1,
          text: (opt.textContent || opt.label || '').trim().substring(0, 100),
          value: opt.value || '',
          selected: opt.selected
        });
      }
    }
  } else if (el.getAttribute('role') === 'listbox' || el.getAttribute('role') === 'combobox') {
    var items = el.querySelectorAll('[role="option"], [role="menuitem"], li, .option, .item');
    for (var i = 0; i < items.length; i++) {
      var item = items[i];
      if (item.offsetHeight === 0) continue;
      options.push({
        index: i + 1,
        text: (item.textContent || '').trim().substring(0, 100),
        value: item.getAttribute('data-value') || '',
        selected: item.getAttribute('aria-selected') === 'true'
      });
    }
  } else {
    return JSON.stringify({error: 'Element at index $index is not a dropdown (tag=' + tag + ', role=' + (el.getAttribute('role') || 'none') + ').'});
  }
  return JSON.stringify({tag: tag, total: options.length, options: options});
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_get_dropdown_options',
        success: true,
        output: result?.toString() ?? '{"options":[]}',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_get_dropdown_options',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  Future<ToolResult> _selectDropdown(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final index = _paramInt(params, 'index');
    final text = params['text'] as String?;
    if (index == null || text == null || text.isEmpty) {
      return const ToolResult(
        toolName: 'browser_select_dropdown',
        success: false,
        output: '',
        error: 'index and text are required.',
      );
    }
    final escapedText = _escapeJs(text);
    final js = '''
(function() {
  var el = document.querySelector('[data-bu-index="$index"]');
  if (!el) return JSON.stringify({success: false, error: 'Element with index $index not found.'});
  var tag = el.tagName.toLowerCase();
  var targetText = '$escapedText';

  if (tag === 'select') {
    el.scrollIntoView({behavior: 'smooth', block: 'center'});
    el.focus();
    var bestIdx = -1, bestScore = 999;
    for (var i = 0; i < el.options.length; i++) {
      var optText = (el.options[i].textContent || el.options[i].label || '').trim().toLowerCase();
      if (optText === targetText.toLowerCase()) { bestIdx = i; break; }
      if (optText.indexOf(targetText.toLowerCase()) >= 0) { bestIdx = i; bestScore = 1; }
      else if (targetText.toLowerCase().indexOf(optText) >= 0 && optText.length > bestScore) { bestIdx = i; bestScore = 3; }
    }
    if (bestIdx >= 0) {
      el.selectedIndex = bestIdx;
      el.dispatchEvent(new Event('change', {bubbles: true}));
      el.dispatchEvent(new Event('input', {bubbles: true}));
      return JSON.stringify({success: true, selected: el.options[bestIdx].textContent.trim(), index: bestIdx + 1, total: el.options.length});
    }
    return JSON.stringify({success: false, error: 'Option "' + targetText + '" not found in dropdown. Call browser_get_dropdown_options to see available options.'});
  }

  if (el.getAttribute('role') === 'listbox' || el.getAttribute('role') === 'combobox') {
    // ARIA dropdown: click items
    var items = el.querySelectorAll('[role="option"], [role="menuitem"], li, .option, .item');
    el.scrollIntoView({behavior: 'smooth', block: 'center'});
    el.focus();
    // First click to open (for combobox)
    el.dispatchEvent(new MouseEvent('mousedown', {bubbles: true}));
    el.dispatchEvent(new MouseEvent('mouseup', {bubbles: true}));
    el.dispatchEvent(new MouseEvent('click', {bubbles: true}));

    // Wait a tick for dropdown to appear, then find and click option
    setTimeout(function() {
      for (var i = 0; i < items.length; i++) {
        var itemText = (items[i].textContent || '').trim();
        if (itemText.toLowerCase().indexOf(targetText.toLowerCase()) >= 0) {
          items[i].scrollIntoView({behavior: 'smooth', block: 'center'});
          items[i].dispatchEvent(new MouseEvent('mousedown', {bubbles: true}));
          items[i].dispatchEvent(new MouseEvent('mouseup', {bubbles: true}));
          items[i].dispatchEvent(new MouseEvent('click', {bubbles: true}));
          return;
        }
      }
    }, 50);
    return JSON.stringify({success: true, selected: targetText, note: 'attempted ARIA menu selection'});
  }

  return JSON.stringify({success: false, error: 'Element is not a dropdown (tag=' + tag + ', role=' + (el.getAttribute('role') || 'none') + ').'});
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      final parsed = result?.toString() ?? '{}';
      // Give ARIA dropdowns a moment to settle
      if (parsed.contains('ARIA menu')) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
      return ToolResult(
        toolName: 'browser_select_dropdown',
        success: !parsed.contains('"success":false'),
        output: parsed,
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_select_dropdown',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // Scroll and collect
  // ============================================================

  Future<ToolResult> _scrollAndCollect(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final maxScreens = _paramInt(params, 'maxScreens') ?? 10;
    final waitMs = _paramInt(params, 'waitMs') ?? 800;
    final js = '''
new Promise(async function(resolve) {
  var allText = [];
  var vh = window.innerHeight;
  var seen = new Set();
  var lastHeight = 0;

  for (var i = 0; i < $maxScreens; i++) {
    var body = document.body ? document.body.innerText : '';
    var hash = body.length + '|' + body.substring(0, 200);

    if (seen.has(hash)) break;
    seen.add(hash);

    allText.push(body.substring(0, 8000));
    var currentTop = window.scrollY;
    window.scrollBy(0, vh * 0.8);
    await new Promise(function(r) { setTimeout(r, $waitMs); });

    var newTop = window.scrollY;
    if (newTop === currentTop) break;
    var newHeight = document.body.scrollHeight;
    if (newHeight === lastHeight && i > 1) break;
    lastHeight = newHeight;
  }

  window.scrollTo(0, 0);
  var combined = allText.join('\\n--- [next screen] ---\\n');
  resolve(combined.substring(0, 80000));
})
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      final text = result?.toString() ?? '';
      return ToolResult(
        toolName: 'browser_scroll_and_collect',
        success: true,
        output: text.isNotEmpty ? text : '(no content collected)',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_scroll_and_collect',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // Page error detection
  // ============================================================

  Future<ToolResult> _checkPageErrors(InAppWebViewController controller) async {
    const js = r'''
(function() {
  var result = {hasError: false, errors: []};
  var title = document.title || '';
  var body = document.body ? document.body.innerText.substring(0, 2000) : '';

  // HTTP error pages
  if (/404|not found/i.test(title)) result.errors.push('HTTP 404 - Page not found');
  if (/500|internal server error/i.test(title)) result.errors.push('HTTP 500 - Server error');
  if (/403|forbidden/i.test(title)) result.errors.push('HTTP 403 - Forbidden');
  if (/502|bad gateway/i.test(title)) result.errors.push('HTTP 502 - Bad gateway');
  if (/503|service unavailable/i.test(title)) result.errors.push('HTTP 503 - Service unavailable');

  // SSL / connection errors
  if (/ssl|secure connection|certificate|不安全|证书/i.test(body)) result.errors.push('SSL/Certificate error');
  if (/connection refused|connection reset|unreachable|无法连接|连接被拒绝/i.test(body)) result.errors.push('Connection error');
  if (/dns|domain|host.*not.*found|无法访问|找不到服务器/i.test(body)) result.errors.push('DNS/Host resolution error');
  if (/timeout|timed out|超时/i.test(body)) result.errors.push('Request timeout');

  // Blank page
  if (body.trim().length < 10 && title.length < 5) result.errors.push('Page appears blank or empty');

  result.hasError = result.errors.length > 0;
  return JSON.stringify(result);
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_check_errors',
        success: true,
        output: result?.toString() ?? '{"hasError":false,"errors":[]}',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_check_errors',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // Clipboard integration
  // ============================================================

  Future<ToolResult> _clipboardCopy(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final index = _paramInt(params, 'index');
    final js = index != null
        ? '''
(function() {
  var el = document.querySelector('[data-bu-index="$index"]');
  if (!el) return JSON.stringify({error: 'Element $index not found'});
  var text = el.value || el.textContent || '';
  navigator.clipboard.writeText(text).catch(function(e) { return JSON.stringify({error: e.toString()}); });
  return JSON.stringify({copied: true, length: text.length, preview: text.substring(0, 100)});
})()
'''
        : '''
(function() {
  var text = window.getSelection().toString();
  if (!text) {
    // try to get the active element's value
    var active = document.activeElement;
    if (active && (active.tagName === 'INPUT' || active.tagName === 'TEXTAREA')) {
      text = active.value.substring(active.selectionStart || 0, active.selectionEnd || active.value.length);
    }
  }
  if (!text) return JSON.stringify({error: 'No text selected and no element index provided'});
  navigator.clipboard.writeText(text).catch(function(e) { return JSON.stringify({error: e.toString()}); });
  return JSON.stringify({copied: true, length: text.length, preview: text.substring(0, 100)});
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_clipboard_copy',
        success: true,
        output: result?.toString() ?? '{"copied":false}',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_clipboard_copy',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  Future<ToolResult> _clipboardPaste(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final index = _paramInt(params, 'index');
    final js = '''
(async function() {
  try {
    var text = await navigator.clipboard.readText();
    if (!text) return JSON.stringify({pasted: false, error: 'Clipboard empty'});
    var el = ${index != null ? "document.querySelector('[data-bu-index=\"$index\"]')" : 'document.activeElement'};
    if (!el) return JSON.stringify({pasted: false, error: 'Target element not found'});
    if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
      el.focus();
      var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
      if (setter && setter.set) setter.set.call(el, text);
      else el.value = text;
      el.dispatchEvent(new Event('input', {bubbles: true}));
    } else if (el.isContentEditable) {
      el.focus();
      document.execCommand('insertText', false, text);
    } else {
      return JSON.stringify({pasted: false, error: 'Target is not an input field'});
    }
    return JSON.stringify({pasted: true, length: text.length, preview: text.substring(0, 100)});
  } catch(e) {
    return JSON.stringify({pasted: false, error: 'Clipboard access denied or empty'});
  }
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_clipboard_paste',
        success: true,
        output: result?.toString() ?? '{"pasted":false}',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_clipboard_paste',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // DOM mutation observer wait
  // ============================================================

  Future<ToolResult> _waitFor(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final text = _escapeJs(params['text'] as String? ?? '');
    final selector = params['selector'] as String?;
    final disappear = params['disappear'] == true;
    final timeoutMs = _paramInt(params, 'timeout') ?? 10000;

    if (text.isEmpty && selector == null) {
      return const ToolResult(
        toolName: 'browser_wait_for',
        success: false,
        output: '',
        error: 'text or selector is required.',
      );
    }

    final checkExpr = selector != null
        ? "document.querySelector('${_escapeJs(selector)}')"
        : "document.body && document.body.innerText.indexOf('$text') >= 0";

    final condition = disappear ? '!($checkExpr)' : checkExpr;

    final js = '''
new Promise(function(resolve) {
  if ($condition) return resolve('found immediately');
  var start = Date.now();
  var timeout = $timeoutMs;
  var observer = new MutationObserver(function() {
    if ($condition) { observer.disconnect(); resolve('found after ' + (Date.now() - start) + 'ms'); }
  });
  observer.observe(document.body || document.documentElement, {
    childList: true, subtree: true, attributes: true, characterData: true
  });
  setTimeout(function() {
    observer.disconnect();
    resolve('timeout after ' + timeout + 'ms');
  }, timeout);
})
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_wait_for',
        success: true,
        output: result?.toString() ?? 'wait completed',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_wait_for',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // Hover simulation
  // ============================================================

  Future<ToolResult> _hover(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final index = _paramInt(params, 'index');
    if (index == null) {
      return const ToolResult(
        toolName: 'browser_hover',
        success: false,
        output: '',
        error: 'index is required.',
      );
    }
    final js = '''
(function() {
  var el = document.querySelector('[data-bu-index="$index"]');
  if (!el) return JSON.stringify({error: 'Element $index not found'});
  el.scrollIntoView({behavior: 'instant', block: 'center'});
  var r = el.getBoundingClientRect();
  var x = r.left + r.width / 2;
  var y = r.top + r.height / 2;
  var opts = {bubbles: true, cancelable: true, view: window, clientX: x, clientY: y};
  el.dispatchEvent(new MouseEvent('mouseenter', opts));
  el.dispatchEvent(new MouseEvent('mouseover', opts));
  el.dispatchEvent(new MouseEvent('focus', opts));
  // Also trigger parent mouseover chain for CSS :hover
  var parent = el.parentElement;
  while (parent) {
    parent.dispatchEvent(new MouseEvent('mouseover', {bubbles: false, cancelable: true, view: window, clientX: x, clientY: y}));
    parent = parent.parentElement;
  }
  return JSON.stringify({success: true, tag: el.tagName, text: (el.textContent||'').trim().substring(0, 100)});
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_hover',
        success: true,
        output: result?.toString() ?? '',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_hover',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // Keyboard simulation
  // ============================================================

  Future<ToolResult> _pressKey(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final key = params['key'] as String?;
    final index = _paramInt(params, 'index');
    if (key == null) {
      return const ToolResult(
        toolName: 'browser_press_key',
        success: false,
        output: '',
        error: 'key is required (e.g. "Enter", "Tab", "Escape", "ArrowDown").',
      );
    }

    final keyOpts = _keyboardOpts(key);

    final js = '''
(function() {
  var el = ${index != null ? "document.querySelector('[data-bu-index=\"$index\"]')" : 'document.activeElement || document.body'};
  if (!el) el = document.body;
  el.focus();
  var opts = ${jsonEncode(keyOpts)};
  el.dispatchEvent(new KeyboardEvent('keydown', opts));
  el.dispatchEvent(new KeyboardEvent('keypress', opts));
  el.dispatchEvent(new KeyboardEvent('keyup', opts));
  // For Enter: also trigger form submit if inside a form
  if ('$key' === 'Enter') {
    var form = el.closest('form');
    if (form) form.dispatchEvent(new Event('submit', {bubbles: true, cancelable: true}));
  }
  // For Tab: try to focus next element
  if ('$key' === 'Tab') {
    var focusable = 'a[href],button,input,select,textarea,[tabindex]:not([tabindex="-1"])';
    var els = Array.from(document.querySelectorAll(focusable)).filter(function(e) {
      return e.offsetParent !== null && !e.disabled;
    });
    var idx = els.indexOf(el);
    var next = els[idx + 1];
    if (next) next.focus();
  }
  return JSON.stringify({success: true, key: '$key', target: el.tagName + (el.name ? '#' + el.name : '')});
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_press_key',
        success: true,
        output: result?.toString() ?? '',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_press_key',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  Map<String, dynamic> _keyboardOpts(String key) {
    final map = <String, dynamic>{
      'key': key, 'bubbles': true, 'cancelable': true,
      'code': key, 'keyCode': 0, 'which': 0,
    };
    switch (key) {
      case 'Enter': map['code'] = 'Enter'; map['keyCode'] = 13; break;
      case 'Tab': map['code'] = 'Tab'; map['keyCode'] = 9; break;
      case 'Escape': map['code'] = 'Escape'; map['keyCode'] = 27; break;
      case 'Backspace': map['code'] = 'Backspace'; map['keyCode'] = 8; break;
      case 'Delete': map['code'] = 'Delete'; map['keyCode'] = 46; break;
      case 'ArrowUp': map['code'] = 'ArrowUp'; map['keyCode'] = 38; break;
      case 'ArrowDown': map['code'] = 'ArrowDown'; map['keyCode'] = 40; break;
      case 'ArrowLeft': map['code'] = 'ArrowLeft'; map['keyCode'] = 37; break;
      case 'ArrowRight': map['code'] = 'ArrowRight'; map['keyCode'] = 39; break;
      case 'Space': map['code'] = 'Space'; map['keyCode'] = 32; break;
      default: break;
    }
    return map;
  }

  // ============================================================
  // Drag simulation
  // ============================================================

  Future<ToolResult> _drag(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final fromIndex = _paramInt(params, 'fromIndex');
    final toIndex = _paramInt(params, 'toIndex');
    final dx = _paramDouble(params, 'dx');
    final dy = _paramDouble(params, 'dy');

    if (fromIndex == null) {
      return const ToolResult(
        toolName: 'browser_drag',
        success: false,
        output: '',
        error: 'fromIndex is required.',
      );
    }

    final js = '''
(function() {
  var el = document.querySelector('[data-bu-index="$fromIndex"]');
  if (!el) return JSON.stringify({error: 'Source element $fromIndex not found'});
  el.scrollIntoView({behavior: 'instant', block: 'center'});
  var r = el.getBoundingClientRect();
  var sx = r.left + r.width / 2;
  var sy = r.top + r.height / 2;
  var ex, ey;

  ${toIndex != null ? '''
  var toEl = document.querySelector('[data-bu-index="$toIndex"]');
  if (!toEl) return JSON.stringify({error: 'Target element $toIndex not found'});
  var tr = toEl.getBoundingClientRect();
  ex = tr.left + tr.width / 2;
  ey = tr.top + tr.height / 2;
  ''' : '''
  ex = sx + ${dx ?? 0};
  ey = sy + ${dy ?? 0};
  '''}

  var steps = 20;
  var opts = {bubbles: true, cancelable: true, view: window, button: 0};

  el.dispatchEvent(new MouseEvent('mousedown', {...opts, clientX: sx, clientY: sy}));

  for (var i = 1; i <= steps; i++) {
    var cx = sx + (ex - sx) * i / steps;
    var cy = sy + (ey - sy) * i / steps;
    document.dispatchEvent(new MouseEvent('mousemove', {...opts, clientX: cx, clientY: cy}));
    el.dispatchEvent(new MouseEvent('mousemove', {...opts, clientX: cx, clientY: cy}));
  }

  if (${toIndex != null ? 'true' : 'false'}) {
    var toEl = ${toIndex != null ? "document.querySelector('[data-bu-index=\"$toIndex\"]')" : 'null'};
    if (toEl) toEl.dispatchEvent(new MouseEvent('drop', {...opts, clientX: ex, clientY: ey}));
  }

  el.dispatchEvent(new MouseEvent('mouseup', {...opts, clientX: ex, clientY: ey}));
  document.dispatchEvent(new MouseEvent('mouseup', {...opts, clientX: ex, clientY: ey}));

  return JSON.stringify({success: true, from: '$fromIndex', to: ${toIndex != null ? "'$toIndex'" : 'null'}, dx: ex - sx, dy: ey - sy});
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_drag',
        success: true,
        output: result?.toString() ?? '',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_drag',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // iframe content awareness
  // ============================================================

  Future<ToolResult> _getIframe(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final index = _paramInt(params, 'index');
    final js = index != null
        ? '''
(function() {
  var el = document.querySelector('[data-bu-index="$index"]');
  if (!el) return JSON.stringify({error: 'iframe element $index not found'});
  if (el.tagName !== 'IFRAME' && el.tagName !== 'FRAME') return JSON.stringify({error: 'Element $index is not an iframe'});
  try {
    var doc = el.contentDocument || el.contentWindow.document;
    if (!doc) return JSON.stringify({error: 'Cross-origin iframe — cannot access content', crossOrigin: true, src: el.src});
    var text = (doc.body ? doc.body.innerText : doc.documentElement.innerText) || '';
    return JSON.stringify({tag: 'IFRAME', src: el.src, sameOrigin: true, text: text.substring(0, 5000),
      interactiveCount: doc.querySelectorAll('a[href],button,input,select,textarea').length});
  } catch(e) {
    return JSON.stringify({error: 'Cross-origin iframe — blocked by browser', crossOrigin: true, src: el.src});
  }
})()
'''
        : '''
(function() {
  var iframes = document.querySelectorAll('iframe');
  var result = [];
  for (var i = 0; i < iframes.length; i++) {
    var f = iframes[i];
    var info = {src: f.src, id: f.id || '', name: f.name || ''};
    try {
      info.sameOrigin = !!f.contentDocument;
      if (info.sameOrigin) {
        var doc = f.contentDocument;
        info.interactiveCount = doc.querySelectorAll('a[href],button,input,select,textarea').length;
      }
    } catch(e) { info.sameOrigin = false; info.error = 'cross-origin'; }
    result.push(info);
  }
  return JSON.stringify({iframes: result, total: result.length});
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_get_iframe',
        success: true,
        output: result?.toString() ?? '{"iframes":[],"total":0}',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_get_iframe',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // search_page — free instant text search
  // ============================================================

  Future<ToolResult> _searchPage(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final text = params['text'] as String? ?? '';
    final regex = params['regex'] as bool? ?? false;
    final caseSensitive = params['case_sensitive'] as bool? ?? false;
    if (text.isEmpty) {
      return const ToolResult(
        toolName: 'browser_search_page',
        success: false,
        output: '',
        error: 'text is required.',
      );
    }
    final escapedText = _escapeJs(text);
    final maxResults = _paramInt(params, 'max_results') ?? 50;
    final contextChars = _paramInt(params, 'context_chars') ?? 80;
    final js = '''
(function() {
  var text = '$escapedText';
  var useRegex = $regex;
  var caseSensitive = $caseSensitive;
  var maxResults = $maxResults;
  var contextChars = $contextChars;
  var pattern;
  if (useRegex) {
    try {
      pattern = new RegExp(text, caseSensitive ? 'g' : 'gi');
    } catch(e) { return JSON.stringify({error: 'Invalid regex: ' + e.message}); }
  }
  var results = [];
  function walk(node) {
    if (results.length >= maxResults) return;
    if (node.nodeType === 3) {
      var txt = node.textContent;
      var match;
      if (useRegex) {
        pattern.lastIndex = 0;
        while ((match = pattern.exec(txt)) !== null && results.length < maxResults) {
          var start = Math.max(0, match.index - contextChars);
          var end = Math.min(txt.length, match.index + match[0].length + contextChars);
          results.push({match: match[0], context: txt.substring(start, end), position: match.index});
        }
      } else {
        var search = caseSensitive ? txt : txt.toLowerCase();
        var find = caseSensitive ? text : text.toLowerCase();
        var pos = 0;
        while ((pos = search.indexOf(find, pos)) !== -1 && results.length < maxResults) {
          var start = Math.max(0, pos - contextChars);
          var end = Math.min(txt.length, pos + text.length + contextChars);
          results.push({match: txt.substring(pos, pos + text.length), context: txt.substring(start, end), position: pos});
          pos += find.length;
        }
      }
    } else if (node.nodeType === 1 && !/^(SCRIPT|STYLE|NOSCRIPT)\$/i.test(node.tagName)) {
      for (var c = node.firstChild; c; c = c.nextSibling) walk(c);
    }
  }
  if (document.body) walk(document.body);
  return JSON.stringify({
    found: results.length > 0,
    count: results.length,
    maxResults: maxResults,
    results: results
  });
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_search_page',
        success: true,
        output: result?.toString() ?? '{"found":false}',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_search_page',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // find_elements — CSS selector query, free and instant
  // ============================================================

  Future<ToolResult> _findElements(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final selector = _escapeJs(params['selector'] as String? ?? '');
    if (selector.isEmpty) {
      return const ToolResult(
        toolName: 'browser_find_elements',
        success: false,
        output: '',
        error: 'selector is required.',
      );
    }
    final js = '''
(function() {
  try {
    var els = document.querySelectorAll('$selector');
    var result = {count: els.length, selector: '$selector', elements: []};
    for (var i = 0; i < Math.min(els.length, 20); i++) {
      var el = els[i];
      var info = {tag: el.tagName.toLowerCase()};
      if (el.id) info.id = el.id;
      if (el.className && typeof el.className === 'string') info.class = el.className.substring(0, 80);
      if (el.href) info.href = el.href.substring(0, 120);
      if (el.textContent) info.text = (el.textContent || '').trim().substring(0, 100);
      if (el.src) info.src = el.src;
      if (el.getAttribute('aria-label')) info.ariaLabel = el.getAttribute('aria-label').substring(0, 80);
      result.elements.push(info);
    }
    return JSON.stringify(result);
  } catch(e) { return JSON.stringify({error: e.toString(), selector: '$selector'}); }
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_find_elements',
        success: true,
        output: result?.toString() ?? '{"count":0}',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_find_elements',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // Upload file
  // ============================================================

  Future<ToolResult> _uploadFile(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final index = _paramInt(params, 'index');
    if (index == null) {
      return const ToolResult(
        toolName: 'browser_upload_file',
        success: false,
        output: '',
        error: 'index is required — the file input element index.',
      );
    }
    // Attempt to trigger file input click and native picker
    final js = '''
(function() {
  var el = document.querySelector('[data-bu-index="$index"]');
  if (!el) return JSON.stringify({error: 'Element with index $index not found.'});
  if (el.tagName.toLowerCase() !== 'input' || el.type !== 'file') {
    // Find nearest file input
    var fileInputs = el.querySelectorAll('input[type="file"]');
    if (fileInputs.length > 0) el = fileInputs[0];
    else return JSON.stringify({error: 'Element is not a file input. Tag=' + el.tagName + ' type=' + (el.type || '')});
  }
  el.scrollIntoView({behavior: 'smooth', block: 'center'});
  el.click();
  return JSON.stringify({success: true, message: 'Opened file picker for element ' + $index + '. The native OS file dialog should appear.'});
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_upload_file',
        success: true,
        output: result?.toString() ?? '{"success":true}',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_upload_file',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // Save as PDF
  // ============================================================

  Future<ToolResult> _saveAsPdf(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    // Flutter InAppWebView does not have a direct print-to-PDF API.
    // Use JavaScript to attempt window.print() with print CSS.
    // The user's system print dialog may appear; cancellation is safe.
    final landscape = params['landscape'] as bool? ?? false;
    final js = '''
(function() {
  var style = document.createElement('style');
  style.textContent = '@media print { @page { size: ${landscape ? 'landscape' : 'A4'}; margin: 1cm; } }';
  document.head.appendChild(style);
  window.print();
  return 'Print dialog opened. ' + ($landscape ? 'Landscape' : 'Portrait') + ' A4 format.';
})()
''';
    try {
      final result = await controller.evaluateJavascript(source: js);
      return ToolResult(
        toolName: 'browser_save_as_pdf',
        success: true,
        output: result?.toString() ?? 'Print dialog opened.',
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_save_as_pdf',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  Future<ToolResult> _extractDesign(
      InAppWebViewController controller, Map<String, dynamic> params) async {
    final selector = params['selector'] as String?;
    var js = BrowserConstants.designExtractionScript;
    // If a scope selector is provided, inject it into the JS
    if (selector != null && selector.isNotEmpty) {
      // Replace the QS-based extraction with the provided selector
      final escaped = _escapeJs(selector);
      js = js.replaceFirst(
        "var q = new URLSearchParams(location.search).get('extract');",
        "var q = '$escaped';",
      );
    }
    try {
      final result = await controller.evaluateJavascript(source: js);
      final output = result?.toString() ?? '{}';
      return ToolResult(
        toolName: 'browser_extract_design',
        success: true,
        output: output,
      );
    } catch (e) {
      print('[BrowserTool] error: $e');
      return ToolResult(
        toolName: 'browser_extract_design',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  static int? _paramInt(Map<String, dynamic> params, String key) {
    final v = params[key];
    if (v == null) return null;
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    if (v is num) return v.toInt();
    return null;
  }

  static num? _paramNum(Map<String, dynamic> params, String key) {
    final v = params[key];
    if (v == null) return null;
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  static double? _paramDouble(Map<String, dynamic> params, String key) {
    final v = params[key];
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  // ── Page control ──────────────────────────────────────────────

  Future<ToolResult> _reload(InAppWebViewController controller) async {
    try {
      await controller.reload();
      return const ToolResult(
          toolName: 'browser_reload', success: true, output: 'Page reloaded');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_reload', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _stopLoading(InAppWebViewController controller) async {
    try {
      await controller.stopLoading();
      return const ToolResult(
          toolName: 'browser_stop', success: true, output: 'Page loading stopped');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_stop', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _getViewport(InAppWebViewController controller) async {
    try {
      final result = await controller.evaluateJavascript(source:
          'JSON.stringify({width:window.innerWidth,height:window.innerHeight,devicePixelRatio:window.devicePixelRatio,scrollX:window.scrollX,scrollY:window.scrollY})');
      return ToolResult(toolName: 'browser_get_viewport', success: true,
          output: result?.toString() ?? '{"width":0,"height":0}');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_get_viewport', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _getDom(InAppWebViewController controller, Map<String, dynamic> params) async {
    final selector = params['selector'] as String?;
    final js = selector != null
        ? "(function(){var el=document.querySelector('${_escapeJs(selector!)}');return el?el.outerHTML:'Selector not found';})()"
        : 'document.documentElement.outerHTML';
    try {
      final result = await controller.evaluateJavascript(source: js);
      final html = result?.toString() ?? '';
      final output = html.length > 20000 ? '${html.substring(0, 20000)}\n...[truncated ${html.length} chars]' : html;
      return ToolResult(toolName: 'browser_get_dom', success: true, output: output);
    } catch (e) {
      return ToolResult(
          toolName: 'browser_get_dom', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _deleteCookies(InAppWebViewController controller) async {
    try {
      final cookieManager = CookieManager.instance();
      await cookieManager.deleteAllCookies();
      return const ToolResult(
          toolName: 'browser_delete_cookies', success: true, output: 'All cookies deleted');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_delete_cookies', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _clearCache(InAppWebViewController controller) async {
    try {
      await InAppWebViewController.clearAllCache();
      return const ToolResult(
          toolName: 'browser_clear_cache', success: true, output: 'Browser cache cleared');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_clear_cache', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _fillForm(InAppWebViewController controller, Map<String, dynamic> params) async {
    final fields = params['fields'] as List?;
    if (fields == null || fields.isEmpty) {
      return const ToolResult(
          toolName: 'browser_fill_form', success: false, output: '', error: 'fields array is required');
    }
    final buf = StringBuffer();
    for (final f in fields) {
      if (f is! Map) continue;
      final index = _paramInt(Map<String, dynamic>.from(f), 'index');
      final text = f['text'] as String? ?? '';
      if (index == null) continue;
      final typeResult = await _type(controller, {'index': index, 'text': text, 'clear': true});
      buf.writeln(typeResult.success ? typeResult.output : 'ERR: ${typeResult.error}');
    }
    return ToolResult(toolName: 'browser_fill_form', success: true, output: buf.toString());
  }

  Future<ToolResult> _addStylesheetJs(InAppWebViewController controller, Map<String, dynamic> params) async {
    final css = _escapeJs(params['css'] as String? ?? '');
    if (css.isEmpty) {
      return const ToolResult(
          toolName: 'browser_add_stylesheet', success: false, output: '', error: 'css is required');
    }
    try {
      await controller.evaluateJavascript(source:
          "(function(){var s=document.createElement('style');s.textContent='$css';document.head.appendChild(s);return'ok';})()");
      return const ToolResult(
          toolName: 'browser_add_stylesheet', success: true, output: 'Stylesheet injected');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_add_stylesheet', success: false, output: '', error: e.toString());
    }
  }

  static String _escapeJs(String s) {
    final encoded = jsonEncode(s);
    return encoded
        .substring(1, encoded.length - 1)
        .replaceAll("'", r"\'");
  }
}
