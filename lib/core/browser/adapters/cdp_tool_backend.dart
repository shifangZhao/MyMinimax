// ignore_for_file: avoid_dynamic_calls

import 'dart:async';
import 'dart:convert';
import 'package:meta/meta.dart';
import '../../../features/tools/domain/tool.dart';
import 'browser_tool_adapter.dart';
import '../browser_constants.dart';
import '../cdp/cdp_connection.dart';
import '../cdp/cdp_command_executor.dart';
import '../cdp/cdp_session_manager.dart';
import '../cdp/dom/cdp_element_tree.dart';

/// CDP-based browser backend for Android.
///
/// Connects to an embedded Chromium instance via WebSocket and uses
/// Chrome DevTools Protocol for all browser interactions:
/// - Real DOM capture (4 parallel CDP calls)
/// - Trusted mouse/keyboard events (CDP Input domain)
/// - Network monitoring (CDP Network domain)
/// - Cross-origin iframe support (multi-target sessions)
class CdpToolBackend implements IBrowserBackend { // backendNodeId → index

  CdpToolBackend({required CdpConnection connection})
      : _connection = connection;
  final CdpConnection _connection;
  late final CdpCommandExecutor _executor;
  late final CdpSessionManager _sessionManager;
  late final CdpElementTreeBuilder _treeBuilder;

  @override
  Future<String?> Function(String reason, String? prompt)? onHumanAssist;

  /// Fallback screenshot provider set by the browser WebView.
  /// When CDP Page.captureScreenshot fails (common on Android WebView),
  /// this callback is tried. Should return a base64-encoded PNG string.
  Future<String?> Function()? onTakeScreenshot;

  // Event streams
  final StreamController<String> _networkRequestController =
      StreamController<String>.broadcast();
  final StreamController<String> _consoleMessageController =
      StreamController<String>.broadcast();
  final StreamController<String> _downloadEventController =
      StreamController<String>.broadcast();

  // Captured state from last snapshot
  CdpElementTreeResult? _lastTree;
  Map<int, int> _previousElementKeys = {};

  /// Execute a page-level CDP command through the session manager,
  /// returning null on any error (equivalent to executeOrNull).
  Future<Map<String, dynamic>?> _executeOrNull(
    String method, {
    Map<String, dynamic>? params,
  }) async {
    try {
      return await _sessionManager.execute(method,
          params: params, frameId: null);
    } catch (_) {
      return null;
    }
  }

  // ── IBrowserBackend: lifecycle ─────────────────────────────────

  @override
  BrowserCapability get capability => BrowserCapability.cdp;

  @override
  Stream<String>? get networkRequestStream => _networkRequestController.stream;

  @override
  Stream<String>? get consoleMessageStream => _consoleMessageController.stream;

  @override
  Stream<String>? get downloadEventStream => _downloadEventController.stream;

  @override
  Future<void> initialize() async {
    if (!_connection.isConnected) {
      await _connection.connect();
    }
    _executor = CdpCommandExecutor(_connection);
    _sessionManager = CdpSessionManager(
      connection: _connection,
      executor: _executor,
    );
    await _sessionManager.initialize();

    _treeBuilder = CdpElementTreeBuilder(
      executor: _executor,
      sessionManager: _sessionManager,
    );

    // Enable required CDP domains
    await Future.wait([
      _executeOrNull('Page.enable'),
      _executeOrNull('Network.enable'),
      _executeOrNull('Runtime.enable'),
      _executeOrNull('DOM.enable'),
      _executeOrNull('Accessibility.enable'),
      _executeOrNull('Log.enable'),
    ]);

    // Subscribe to network events
    _connection.on('Network', (event) {
      if (event.eventName == 'requestWillBeSent' ||
          event.eventName == 'responseReceived' ||
          event.eventName == 'loadingFailed') {
        final entry = '${event.eventName}|${jsonEncode(event.params)}';
        _networkRequestController.add(entry);
        _networkEventBuffer.add(entry);
        if (_networkEventBuffer.length > 200) _networkEventBuffer.removeAt(0);
      }
    });

    // Subscribe to console/log events
    _connection.on('Log', (event) {
      if (event.eventName == 'entryAdded') {
        final entry = event.params?['entry']?['text'] ?? '';
        _consoleMessageController.add(entry);
        _consoleEventBuffer.add(entry);
        if (_consoleEventBuffer.length > 200) _consoleEventBuffer.removeAt(0);
      }
    });
    _connection.on('Runtime', (event) {
      if (event.eventName == 'consoleAPICalled' ||
          event.eventName == 'exceptionThrown') {
        final entry = '${event.eventName}|${jsonEncode(event.params)}';
        _consoleMessageController.add(entry);
        _consoleEventBuffer.add(entry);
        if (_consoleEventBuffer.length > 200) _consoleEventBuffer.removeAt(0);
      }
    });
  }

  @override
  Future<void> dispose() async {
    await _sessionManager.dispose();
    await _networkRequestController.close();
    await _consoleMessageController.close();
    await _downloadEventController.close();
    await _connection.close();
  }

  // ── IBrowserBackend: tool execution ────────────────────────────

  @override
  Future<ToolResult> execute(String toolName, Map<String, dynamic> params) async {
    switch (toolName) {
      // Navigation
      case 'browser_navigate':
        return _cdpNavigate(params);
      case 'browser_go_back':
        return _cdpGoBack();
      case 'browser_go_forward':
        return _cdpGoForward();
      case 'browser_open_tab':
        return _cdpOpenTab(params);
      case 'browser_close_tab':
        return _cdpCloseTab(params);

      // State capture
      case 'browser_get_elements':
        return _cdpGetElements();
      case 'browser_get_url':
        return _cdpGetUrl();
      case 'browser_get_title':
        return _cdpGetTitle();
      case 'browser_get_content':
        return _cdpGetContent(params);

      // Interaction — CDP Input domain (trusted events)
      case 'browser_click':
        return _cdpClick(params);
      case 'browser_type':
        return _cdpType(params);
      case 'browser_hover':
        return _cdpHover(params);
      case 'browser_press_key':
        return _cdpPressKey(params);
      case 'browser_scroll':
        return _cdpScroll(params);
      case 'browser_wait':
        return _cdpWait(params);
      case 'browser_select_dropdown':
        return _cdpSelectDropdown(params);
      case 'browser_get_dropdown_options':
        return _cdpGetDropdownOptions(params);

      // Content
      case 'browser_screenshot':
        return _cdpScreenshot();
      case 'browser_screenshot_element':
        return _cdpScreenshotElement(params);

      // Diagnostics
      case 'browser_detect_captcha':
        return _cdpDetectCaptcha();
      case 'browser_check_errors':
        return _cdpCheckErrors();
      case 'browser_get_iframe':
        return _cdpGetIframe(params);

      // Session
      case 'browser_save_cookies':
        return _cdpSaveCookies();
      case 'browser_restore_cookies':
        return _cdpRestoreCookies(params);
      case 'browser_list_downloads':
        return _cdpListDownloads();

      // Utility
      case 'browser_execute_js':
        return _cdpExecuteJs(params);
      case 'browser_wait_for':
        return _cdpWaitFor(params);

      // Content / Search (CDP via Runtime.evaluate)
      case 'browser_find':
        return _cdpFind(params);
      case 'browser_search_page':
        return _cdpSearchPage(params);
      case 'browser_find_elements':
        return _cdpFindElements(params);
      case 'browser_detect_form_result':
        return _cdpDetectFormResult();
      case 'browser_human_assist':
        return _cdpHumanAssist(params);
      case 'browser_load_html':
        return _cdpLoadHtml(params);
      case 'browser_scroll_and_collect':
        return _cdpScrollAndCollect(params);
      case 'browser_drag':
        return _cdpDrag(params);
      case 'browser_clipboard_copy':
        return _cdpClipboardCopy(params);
      case 'browser_clipboard_paste':
        return _cdpClipboardPaste(params);

      // Page control
      case 'browser_reload':
      case 'browser_refresh':
        return _cdpReload();
      case 'browser_stop':
        return _cdpStop();

      // Diagnostics
      case 'browser_get_viewport':
        return _cdpGetViewport();
      case 'browser_get_dom':
        return _cdpGetDom(params);
      case 'browser_get_cookies':
        return _cdpSaveCookies(); // alias
      case 'browser_delete_cookies':
        return _cdpDeleteCookies();
      case 'browser_clear_cache':
        return _cdpClearCache();

      // Form
      case 'browser_fill_form':
        return _cdpFillForm(params);
      case 'browser_detect_form':
        return _cdpDetectFormResult(); // alias

      // Injection
      case 'browser_add_script':
        return _cdpAddScript(params);
      case 'browser_add_stylesheet':
        return _cdpAddStylesheet(params);

      // Network / Console event collectors
      case 'browser_get_network_requests':
        return _cdpGetNetworkRequests();
      case 'browser_get_cdp_logs':
        return _cdpGetCdpLogs();
      case 'browser_get_headers':
        return _cdpGetNetworkRequests(); // alias — same data

      // Design extraction
      case 'browser_extract_design':
        return _cdpExtractDesign(params);

      default:
        return ToolResult(
          toolName: toolName,
          success: false,
          output: '',
          error: 'Tool "$toolName" not yet implemented for CDP backend.',
        );
    }
  }

  // ── IBrowserBackend: state capture ─────────────────────────────

  @override
  Future<BrowserPageState> capturePageState({
    Set<String>? previousElementKeys,
  }) async {
    final treeResult = await _treeBuilder.capture(
      previousElementKeys: _previousElementKeys,
    );

    if (treeResult.isSuccess) {
      _lastTree = treeResult;
    } else {
      // CDP tree capture failed — try JS fallback
      try {
        await _jsGetElementsFallback();
      } catch (_) {}
    }

    if (_lastTree == null) {
      return BrowserPageState(
        url: '',
        pageText: treeResult.errorMessage ?? 'Unknown error capturing page state',
      );
    }

    // Use _lastTree (set by either CDP capture or JS fallback)
    final effectiveTree = _lastTree!;

    // Update previous element keys for next step's new-element detection
    _previousElementKeys = {};
    for (final el in effectiveTree.elements) {
      if (el.backendNodeId != null) {
        _previousElementKeys[el.backendNodeId!] = el.index;
      }
    }

    // Get URL and title
    String url = '';
    String title = '';
    try {
      final urlResult = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': 'window.location.href',
        'returnByValue': true,
      });
      url = (urlResult['result']?['value'] as String?) ?? '';
    } catch (_) {}
    try {
      final titleResult = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': 'document.title',
        'returnByValue': true,
      });
      title = (titleResult['result']?['value'] as String?) ?? '';
    } catch (_) {}

    // Get page text (markdown via JS since CDP doesn't do markdown)
    String pageText = '';
    try {
      final textResult = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': 'document.body ? document.body.innerText : ""',
        'returnByValue': true,
      });
      pageText = (textResult['result']?['value'] as String?) ?? '';
      if (pageText.length > 4000) pageText = '${pageText.substring(0, 4000)}...[truncated]';
    } catch (_) {}

    // Fingerprint
    final fp = '$url|${effectiveTree.elements.length}|${pageText.hashCode}';

    return BrowserPageState(
      url: url,
      pageText: pageText,
      elements: effectiveTree.elements,
      pageFingerprint: fp,
    );
  }

  // ── IBrowserBackend: CDP-native methods ────────────────────────

  @override
  Future<List<Map<String, dynamic>>> getEventListeners(int backendNodeId) async {
    try {
      final result = await _sessionManager.execute('DOMDebugger.getEventListeners', params: {
        'objectId': await _resolveObjectId(backendNodeId),
      });
      final listeners = (result['listeners'] as List?) ?? [];
      return listeners
          .map((l) => {
                'type': (l as Map<String, dynamic>)['type'],
                'useCapture': l['useCapture'] ?? false,
              })
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<CdpCookie>> getCookies(String url) async {
    try {
      final result = await _sessionManager.execute('Network.getCookies', params: {
        'urls': [url],
      });
      final cookies = (result['cookies'] as List?) ?? [];
      return cookies.map((c) {
        final m = c as Map<String, dynamic>;
        return CdpCookie(
          name: m['name'] as String? ?? '',
          value: m['value'] as String? ?? '',
          domain: m['domain'] as String? ?? '',
          path: m['path'] as String? ?? '/',
          httpOnly: m['httpOnly'] as bool? ?? false,
          secure: m['secure'] as bool? ?? false,
          session: m['session'] as bool? ?? true,
          expires: (m['expires'] as num?)?.toDouble(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<CdpLayoutMetrics?> getLayoutMetrics() async {
    try {
      final result = await _sessionManager.execute('Page.getLayoutMetrics');
      final cssViewport = result['cssLayoutViewport'] as Map<String, dynamic>?;
      final contentSize = result['cssContentSize'] as Map<String, dynamic>?;
      final visualViewport = result['visualViewport'] as Map<String, dynamic>?;
      if (cssViewport == null) return null;
      return CdpLayoutMetrics(
        devicePixelRatio:
            (cssViewport['devicePixelRatio'] as num?)?.toDouble() ?? 1.0,
        viewportWidth: (cssViewport['clientWidth'] as num?)?.toDouble() ?? 0,
        viewportHeight: (cssViewport['clientHeight'] as num?)?.toDouble() ?? 0,
        contentWidth: (contentSize?['width'] as num?)?.toDouble() ?? 0,
        contentHeight: (contentSize?['height'] as num?)?.toDouble() ?? 0,
        scrollX: (visualViewport?['pageX'] as num?)?.toDouble() ?? 0,
        scrollY: (visualViewport?['pageY'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispatchMouseEvent(CdpMouseEvent event) async {
    await _executeOrNull('Input.dispatchMouseEvent', params: {
      'type': event.type,
      'x': event.x,
      'y': event.y,
      'button': event.button,
      'clickCount': event.clickCount,
      'modifiers': event.modifiers,
    });
  }

  @override
  Future<void> dispatchKeyEvent(CdpKeyEvent event) async {
    await _executeOrNull('Input.dispatchKeyEvent', params: {
      'type': event.type,
      'key': event.key,
      'code': event.code,
      'modifiers': event.modifiers,
      'text': event.text,
      'isKeypad': event.isKeypad,
    });
  }

  @override
  Future<String?> captureScreenshot() async {
    // Try CDP Page.captureScreenshot first (works on desktop Chrome)
    try {
      final result = await _sessionManager.execute('Page.captureScreenshot', params: {
        'format': 'png',
      });
      final data = result['data'] as String?;
      if (data != null) return data;
    } on CdpCommandException catch (_) {
      // WebView often rejects this command
    } catch (_) {
      // Connection may be down
    }

    // Try with viewport clip
    try {
      final metrics = await getLayoutMetrics();
      final params = <String, dynamic>{'format': 'png'};
      if (metrics != null && metrics.viewportWidth > 0) {
        params['clip'] = {
          'x': 0, 'y': 0,
          'width': metrics.viewportWidth,
          'height': metrics.viewportHeight,
          'scale': 1,
        };
      }
      final result = await _sessionManager.execute('Page.captureScreenshot', params: params);
      final data = result['data'] as String?;
      if (data != null) return data;
    } catch (_) {}

    // Fall back to platform-native screenshot (InAppWebViewController.takeScreenshot)
    if (onTakeScreenshot != null) {
      try {
        final data = await onTakeScreenshot!();
        if (data != null) return data;
      } catch (_) {}
    }

    return null;
  }

  // ── Tool Implementations (CDP-based) ───────────────────────────

  Future<ToolResult> _cdpNavigate(Map<String, dynamic> params) async {
    final url = params['url'] as String? ?? '';
    try {
      await _sessionManager.execute('Page.navigate', params: {'url': url});
      return ToolResult(
        toolName: 'browser_navigate',
        success: true,
        output: 'Navigated to $url (CDP)',
      );
    } catch (e) {
      print('[CdpBackend] error: $e');
      return ToolResult(
        toolName: 'browser_navigate',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  Future<ToolResult> _cdpGoBack() async {
    try {
      final history = await _sessionManager.execute('Page.getNavigationHistory');
      final currentIndex = history['currentIndex'] as int? ?? -1;
      final entries = (history['entries'] as List?) ?? [];
      if (currentIndex > 0 && currentIndex - 1 < entries.length) {
        final entryId = (entries[currentIndex - 1] as Map<String, dynamic>)['id'] as int;
        await _sessionManager.execute('Page.navigateToHistoryEntry', params: {'entryId': entryId});
        return const ToolResult(
            toolName: 'browser_go_back', success: true, output: 'Went back (CDP)');
      }
      return const ToolResult(
          toolName: 'browser_go_back', success: false, output: '', error: 'No back history');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_go_back', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpGoForward() async {
    try {
      final history = await _sessionManager.execute('Page.getNavigationHistory');
      final currentIndex = history['currentIndex'] as int? ?? -1;
      final entries = (history['entries'] as List?) ?? [];
      if (currentIndex >= 0 && currentIndex + 1 < entries.length) {
        final entryId = (entries[currentIndex + 1] as Map<String, dynamic>)['id'] as int;
        await _sessionManager.execute('Page.navigateToHistoryEntry', params: {'entryId': entryId});
        return const ToolResult(
            toolName: 'browser_go_forward', success: true, output: 'Went forward (CDP)');
      }
      return const ToolResult(
          toolName: 'browser_go_forward', success: false, output: '', error: 'No forward history');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_go_forward', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpOpenTab(Map<String, dynamic> params) async {
    final url = params['url'] as String? ?? 'about:blank';
    // Try CDP Target.createTarget first (works on desktop Chrome)
    try {
      await _sessionManager.execute('Target.createTarget', params: {'url': url});
      return ToolResult(
          toolName: 'browser_open_tab', success: true, output: 'Opened tab: $url (CDP)');
    } catch (_) {
      // WebView doesn't support Target.createTarget — fall back to window.open
      try {
        await _sessionManager.execute('Runtime.evaluate', params: {
          'expression': "window.open('${esc(url)}', '_blank')",
        });
        return ToolResult(
            toolName: 'browser_open_tab', success: true,
            output: 'Opened new window: $url (JS fallback — WebView handles via onCreateWindow)');
      } catch (e) {
        return ToolResult(
            toolName: 'browser_open_tab', success: false, output: '', error: e.toString());
      }
    }
  }

  Future<ToolResult> _cdpCloseTab(Map<String, dynamic> params) async {
    try {
      final targetId = _sessionManager.focusedTarget?.targetId;
      if (targetId != null) {
        await _sessionManager.execute('Target.closeTarget', params: {'targetId': targetId});
      }
      return const ToolResult(
          toolName: 'browser_close_tab', success: true, output: 'Closed tab (CDP)');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_close_tab', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpGetElements() async {
    if (_lastTree == null) {
      // Auto-capture on first call — direct tool usage doesn't go through capturePageState()
      try {
        await capturePageState();
      } catch (_) {}
    }
    // CDP tree capture failed (common on Android WebView) — fall back to JS injection
    if (_lastTree == null) {
      try {
        await _jsGetElementsFallback();
      } catch (_) {}
    }
    if (_lastTree == null) {
      return const ToolResult(
          toolName: 'browser_get_elements', success: true, output: '{"elements":[],"total":0}');
    }
    final list = _lastTree!.elements
        .map((e) => {
              'index': e.index,
              'tag': e.tag,
              'text': e.text,
              'type': e.type,
              'id': e.id,
              'placeholder': e.placeholder,
              'name': '',
              'href': e.href,
              'ariaLabel': e.ariaLabel,
              'role': e.role,
              'disabled': e.disabled,
              'depth': e.depth,
              'scrollable': e.scrollable,
              'scrollInfo': e.scrollInfo,
            })
        .toList();
    final src = _lastTree!.elements.isNotEmpty &&
            _lastTree!.elements.first.backendNodeId != null
        ? 'CDP DOMSnapshot'
        : 'JS fallback';
    return ToolResult(
      toolName: 'browser_get_elements',
      success: true,
      output: jsonEncode({
        'elements': list,
        'total': list.length,
        'hint': 'Elements captured via $src',
      }),
    );
  }

  /// JS-based element discovery fallback when CDP DOMSnapshot is unavailable
  /// (common on Android WebView). Runs via Runtime.evaluate and populates
  /// _lastTree with InteractiveElement objects that include layout data for
  /// subsequent click/type/hover operations.
  Future<void> _jsGetElementsFallback() async {
    // Compact JS element discovery — runs via Runtime.evaluate when CDP
    // DOMSnapshot is unavailable on Android WebView.
    // Sets data-bu-index attributes on found elements and returns layout data
    // so subsequent CDP Input dispatch (click/type/hover) can use the coords.
    const js = r'''
(function(){
var R=[],I=1,M=80,vh=window.innerHeight;
function V(e){
  var r=e.getBoundingClientRect();
  if(r.width===0||r.height===0)return false;
  var s=window.getComputedStyle(e);
  if(s.display==='none'||s.visibility==='hidden'||s.opacity==='0')return false;
  if(r.bottom<-vh*2||r.top>vh*3)return false;
  return true;
}
function T(e){
  var t=e.tagName.toLowerCase();
  if(t==='input'||t==='textarea')return e.placeholder||e.value||e.name||'';
  if(t==='img')return e.alt||'';
  if(t==='select'){var o=e.options[e.selectedIndex];return(o?o.text:'')||e.name||'';}
  return(e.textContent||'').trim().substring(0,80);
}
function A(e){
  if(!V(e))return;
  if(R.length>=M)return;
  var t=e.tagName.toLowerCase();
  if(t==='script'||t==='style'||t==='meta'||t==='link'||t==='head'||t==='html'||t==='body')return;
  if(t==='input'&&e.type==='hidden')return;
  for(var i=0;i<R.length;i++){if(R[i]._el===e)return;}
  var r=e.getBoundingClientRect();
  e.setAttribute('data-bu-index',String(I));
  R.push({_el:e,index:I,tag:t,type:(e.type||'').substring(0,30),
    id:(e.id||'').substring(0,50),placeholder:(e.placeholder||'').substring(0,50),
    href:(e.href||e.getAttribute('href')||'').substring(0,120),
    ariaLabel:(e.getAttribute('aria-label')||'').substring(0,80),
    role:(e.getAttribute('role')||'').substring(0,30),
    text:T(e).substring(0,80),
    disabled:!!(e.disabled||e.getAttribute('aria-disabled')==='true'),
    depth:0,x:r.left,y:r.top,w:r.width,h:r.height});
  I++;
}
try{
  var q=document.querySelectorAll('a[href],button,input:not([type="hidden"]),select,textarea,[role="button"],[role="link"],[role="checkbox"],[role="menuitem"],[role="tab"],[role="textbox"],[role="combobox"],[role="listbox"],[role="radio"],[role="switch"],[role="option"],[onclick],[contenteditable="true"],details,summary,iframe,frame,[tabindex]:not([tabindex="-1"])');
  for(var i=0;i<q.length;i++)A(q[i]);
}catch(e){}
if(R.length<M){
  var t2=['div','span','li','td','th','tr','article','section','nav','header','footer','label','p'];
  for(var ti=0;ti<t2.length&&R.length<M;ti++){
    var els=document.querySelectorAll(t2[ti]);
    for(var i=0;i<els.length&&i<300&&R.length<M;i++){
      if(!V(els[i]))continue;
      try{if(window.getComputedStyle(els[i]).cursor==='pointer')A(els[i]);}catch(e){}
    }
  }
}
for(var i=0;i<R.length;i++)delete R[i]._el;
return JSON.stringify({elements:R,total:R.length});
})()
''';
    try {
      final result = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': js, 'returnByValue': true,
      });
      final raw = result['result']?['value'];
      // Handle both String and Map returns from CDP
      final parsed;
      if (raw is String) {
        parsed = jsonDecode(raw) as Map<String, dynamic>;
      } else if (raw is Map) {
        parsed = raw as Map<String, dynamic>;
      } else {
        _lastTree = null;
        return;
      }
      final list = (parsed['elements'] as List?) ?? [];

      final elements = <InteractiveElement>[];
      int idx = 1;
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        elements.add(InteractiveElement(
          index: idx++,
          tag: m['tag'] as String? ?? '',
          text: m['text'] as String? ?? '',
          type: m['type'] as String? ?? '',
          id: m['id'] as String? ?? '',
          placeholder: m['placeholder'] as String? ?? '',
          href: m['href'] as String? ?? '',
          ariaLabel: m['ariaLabel'] as String? ?? '',
          role: m['role'] as String? ?? '',
          disabled: m['disabled'] as bool? ?? false,
          depth: m['depth'] as int? ?? 0,
          x: (m['x'] as num?)?.toDouble() ?? 0,
          y: (m['y'] as num?)?.toDouble() ?? 0,
          width: (m['w'] as num?)?.toDouble() ?? 0,
          height: (m['h'] as num?)?.toDouble() ?? 0,
        ));
      }

      _lastTree = CdpElementTreeResult(
        elements: elements,
        totalFound: elements.length,
      );
    } catch (_) {
      _lastTree = null;
    }
  }

  Future<ToolResult> _cdpGetUrl() async {
    try {
      final result = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': 'window.location.href',
        'returnByValue': true,
      });
      final url = (result['result']?['value'] as String?) ?? 'about:blank';
      return ToolResult(toolName: 'browser_get_url', success: true, output: url);
    } catch (e) {
      return ToolResult(toolName: 'browser_get_url', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpGetTitle() async {
    try {
      final result = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': 'document.title',
        'returnByValue': true,
      });
      return ToolResult(
          toolName: 'browser_get_title', success: true, output: (result['result']?['value'] as String?) ?? '');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_get_title', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpGetContent(Map<String, dynamic> params) async {
    try {
      final result = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': params['format'] == 'markdown'
            ? 'document.body ? document.body.innerText : ""'
            : 'document.body ? document.body.innerText : ""',
        'returnByValue': true,
      });
      final text = (result['result']?['value'] as String?) ?? '';
      return ToolResult(toolName: 'browser_get_content', success: true, output: text);
    } catch (e) {
      return ToolResult(
          toolName: 'browser_get_content', success: false, output: '', error: e.toString());
    }
  }

  // ── Interaction ─────────────────────────────────────────────────

  Future<ToolResult> _cdpClick(Map<String, dynamic> params) async {
    final index = _paramInt(params, 'index');
    if (index == null) {
      return const ToolResult(
          toolName: 'browser_click', success: false, output: '', error: 'index required');
    }
    if (_lastTree == null) {
      try { await capturePageState(); } catch (_) {}
      if (_lastTree == null) {
        return const ToolResult(
            toolName: 'browser_click', success: false, output: '',
            error: 'No elements captured yet. Call browser_get_elements first.');
      }
    }
    final el = _lastTree!.elements
        .where((e) => e.index == index)
        .firstOrNull;
    if (el == null) {
      return ToolResult(
          toolName: 'browser_click', success: false, output: '',
          error: 'Element index $index not found in CDP element tree. Call browser_get_elements to refresh.');
    }
    // Use layout data directly from CdpElementTree — zero JS
    final x = el.centerX;
    final y = el.centerY;
    if (x <= 0 && y <= 0) {
      return ToolResult(
          toolName: 'browser_click', success: false, output: '',
          error: 'Element $index has zero position — may be off-screen or not rendered.');
    }
    try {
      // Full click sequence: move → press → release
      await dispatchMouseEvent(CdpMouseEvent(type: 'mouseMoved', x: x, y: y));
      await Future.delayed(const Duration(milliseconds: 20));
      await dispatchMouseEvent(CdpMouseEvent(type: 'mousePressed', x: x, y: y, clickCount: 1));
      await Future.delayed(const Duration(milliseconds: 50));
      await dispatchMouseEvent(CdpMouseEvent(type: 'mouseReleased', x: x, y: y, clickCount: 1));
      return ToolResult(
          toolName: 'browser_click',
          success: true,
          output: 'Clicked <${el.tag}> at ($x, $y) via CDP Input (layout data)');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_click', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpType(Map<String, dynamic> params) async {
    final index = _paramInt(params, 'index');
    final text = params['text'] as String? ?? '';
    final clear = params['clear'] as bool? ?? true;
    if (index == null) {
      return const ToolResult(
          toolName: 'browser_type', success: false, output: '', error: 'index required');
    }
    if (_lastTree == null) {
      try { await capturePageState(); } catch (_) {}
      if (_lastTree == null) {
        return const ToolResult(
            toolName: 'browser_type', success: false, output: '',
            error: 'No elements captured yet. Call browser_get_elements first.');
      }
    }
    final el = _lastTree!.elements.where((e) => e.index == index).firstOrNull;
    if (el == null) {
      return ToolResult(
          toolName: 'browser_type', success: false, output: '',
          error: 'Element index $index not found in CDP tree.');
    }
    try {
      // Focus element by clicking its center via CDP Input (trusted event)
      await dispatchMouseEvent(CdpMouseEvent(type: 'mouseMoved', x: el.centerX, y: el.centerY));
      await dispatchMouseEvent(CdpMouseEvent(type: 'mousePressed', x: el.centerX, y: el.centerY, clickCount: 1));
      await dispatchMouseEvent(CdpMouseEvent(type: 'mouseReleased', x: el.centerX, y: el.centerY, clickCount: 1));

      // Give the element time to receive focus
      await Future.delayed(const Duration(milliseconds: 80));

      if (clear) {
        // Select all (Ctrl+A on Windows/Linux, Cmd+A on Mac)
        await dispatchKeyEvent(const CdpKeyEvent(type: 'rawKeyDown', key: 'a', code: 'KeyA', modifiers: 2));
        await dispatchKeyEvent(const CdpKeyEvent(type: 'keyUp', key: 'a', code: 'KeyA', modifiers: 2));
        // Delete selected content
        await dispatchKeyEvent(const CdpKeyEvent(type: 'rawKeyDown', key: 'Delete', code: 'Delete'));
        await dispatchKeyEvent(const CdpKeyEvent(type: 'keyUp', key: 'Delete', code: 'Delete'));
        await Future.delayed(const Duration(milliseconds: 30));
      }

      // Type each character
      for (int i = 0; i < text.length; i++) {
        final char = text[i];
        await dispatchKeyEvent(CdpKeyEvent(type: 'char', key: char, text: char));
        if (i % 10 == 0 && i > 0) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }

      return ToolResult(
          toolName: 'browser_type',
          success: true,
          output: 'Typed ${text.length} chars into <${el.tag}> via CDP Input (layout data)${clear ? ' (cleared first)' : ''}');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_type', success: false, output: '', error: e.toString());
    }
  }

  // ── Stub CDP methods (to be fully implemented) ──────────────────

  Future<ToolResult> _cdpHover(Map<String, dynamic> params) async {
    final index = _paramInt(params, 'index');
    if (index == null) {
      return const ToolResult(
          toolName: 'browser_hover', success: false, output: '', error: 'index required');
    }
    if (_lastTree == null) {
      try { await capturePageState(); } catch (_) {}
      if (_lastTree == null) {
        return const ToolResult(
            toolName: 'browser_hover', success: false, output: '',
            error: 'No elements captured yet. Call browser_get_elements first.');
      }
    }
    final el = _lastTree!.elements.where((e) => e.index == index).firstOrNull;
    if (el == null) {
      return ToolResult(
          toolName: 'browser_hover', success: false, output: '',
          error: 'Element index $index not found in CDP tree.');
    }
    try {
      await dispatchMouseEvent(CdpMouseEvent(type: 'mouseMoved', x: el.centerX, y: el.centerY));
      return ToolResult(
          toolName: 'browser_hover',
          success: true,
          output: 'Hovered <${el.tag}> at (${el.centerX}, ${el.centerY}) via CDP Input');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_hover', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpPressKey(Map<String, dynamic> params) async {
    final key = params['key'] as String? ?? '';
    try {
      await dispatchKeyEvent(CdpKeyEvent(type: 'rawKeyDown', key: key));
      await dispatchKeyEvent(CdpKeyEvent(type: 'keyUp', key: key));
      return ToolResult(
          toolName: 'browser_press_key', success: true, output: 'Pressed $key (CDP)');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_press_key', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpScroll(Map<String, dynamic> params) async {
    final direction = params['direction'] as String? ?? 'down';
    final amount = _paramNum(params, 'amount') ?? 800;
    final sign = direction == 'up' || direction == 'top' ? -1 : 1;
    try {
      await _sessionManager.execute('Input.dispatchMouseEvent', params: {
        'type': 'mouseWheel', 'x': 100, 'y': 100, 'deltaX': 0, 'deltaY': sign * amount,
      });
      return ToolResult(
          toolName: 'browser_scroll', success: true, output: 'Scrolled $direction $amount px (CDP)');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_scroll', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpWait(Map<String, dynamic> params) async {
    final timeout = _paramNum(params, 'timeout') ?? 3000;
    final ms = timeout.toInt().clamp(0, 30000);
    await Future.delayed(Duration(milliseconds: ms));
    return ToolResult(
        toolName: 'browser_wait', success: true, output: 'Waited $ms ms (CDP)');
  }

  Future<ToolResult> _cdpSelectDropdown(Map<String, dynamic> params) async {
    final index = _paramInt(params, 'index');
    final text = params['text'] as String?;
    if (index == null || text == null || text.isEmpty) {
      return const ToolResult(
          toolName: 'browser_select_dropdown', success: false, output: '',
          error: 'index and text are required');
    }
    try {
      final result = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': '''
(function() {
  var it = document.evaluate('//*[@*]', document, null,
    XPathResult.ORDERED_NODE_ITERATOR_TYPE, null);
  var node, n = 0;
  while (node = it.iterateNext()) { n++; if (n === $index) break; }
  if (!node) return JSON.stringify({success: false, error: 'Element not found'});
  var tag = node.tagName.toLowerCase();
  var target = '${esc(text)}';
  if (tag === 'select') {
    node.scrollIntoView({behavior: 'smooth', block: 'center'});
    node.focus();
    for (var i = 0; i < node.options.length; i++) {
      var opt = node.options[i];
      var optText = (opt.textContent || opt.label || '').trim().toLowerCase();
      if (optText === target.toLowerCase() || optText.indexOf(target.toLowerCase()) >= 0) {
        node.selectedIndex = i;
        node.dispatchEvent(new Event('change', {bubbles: true}));
        return JSON.stringify({success: true, selected: opt.textContent.trim(), index: i+1, total: node.options.length});
      }
    }
    return JSON.stringify({success: false, error: 'Option not found: ' + target});
  }
  var role = node.getAttribute('role') || '';
  if (role === 'listbox' || role === 'combobox') {
    node.dispatchEvent(new MouseEvent('mousedown', {bubbles: true}));
    var items = node.querySelectorAll('[role="option"], [role="menuitem"], li, .option, .item');
    for (var i = 0; i < items.length; i++) {
      var itemText = (items[i].textContent || '').trim();
      if (itemText.toLowerCase().indexOf(target.toLowerCase()) >= 0) {
        items[i].dispatchEvent(new MouseEvent('mousedown', {bubbles: true}));
        items[i].dispatchEvent(new MouseEvent('mouseup', {bubbles: true}));
        items[i].dispatchEvent(new MouseEvent('click', {bubbles: true}));
        try { items[i].click(); } catch(e) {}
        return JSON.stringify({success: true, selected: itemText});
      }
    }
  }
  return JSON.stringify({success: false, error: 'Not a dropdown (tag=' + tag + ' role=' + role + ')'});
})()
''',
        'returnByValue': true,
      });
      final output = (result['result']?['value'] as String?) ?? '{}';
      return ToolResult(
          toolName: 'browser_select_dropdown', success: !output.contains('"success":false'), output: output);
    } catch (e) {
      return ToolResult(
          toolName: 'browser_select_dropdown', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpGetDropdownOptions(Map<String, dynamic> params) async {
    final index = _paramInt(params, 'index');
    if (index == null) {
      return const ToolResult(
          toolName: 'browser_get_dropdown_options', success: false, output: '', error: 'index required');
    }
    try {
      final result = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': '''
(function() {
  var it = document.evaluate('//*[@*]', document, null,
    XPathResult.ORDERED_NODE_ITERATOR_TYPE, null);
  var node, n = 0;
  while (node = it.iterateNext()) { n++; if (n === $index) break; }
  if (!node) return JSON.stringify({error: 'Element not found'});
  var tag = node.tagName.toLowerCase();
  var options = [];
  if (tag === 'select') {
    for (var i = 0; i < node.options.length; i++) {
      var opt = node.options[i];
      if (!opt.disabled) options.push({index: i+1, text: (opt.textContent||'').trim().substring(0,100), value: opt.value||'', selected: opt.selected});
    }
  } else {
    var items = node.querySelectorAll('[role="option"], [role="menuitem"], li, .option');
    for (var i = 0; i < items.length; i++) {
      if (items[i].offsetHeight === 0) continue;
      options.push({index: i+1, text: (items[i].textContent||'').trim().substring(0,100)});
    }
  }
  return JSON.stringify({tag: tag, total: options.length, options: options});
})()
''',
        'returnByValue': true,
      });
      return ToolResult(
          toolName: 'browser_get_dropdown_options', success: true,
          output: (result['result']?['value'] as String?) ?? '{"options":[]}');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_get_dropdown_options', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpScreenshot() async {
    try {
      final data = await captureScreenshot();
      if (data != null) {
        return ToolResult(
            toolName: 'browser_screenshot', success: true, output: 'Screenshot (CDP)', data: data);
      }
      return const ToolResult(
          toolName: 'browser_screenshot', success: false, output: '', error: 'Screenshot failed');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_screenshot', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpScreenshotElement(Map<String, dynamic> params) async {
    final index = _paramInt(params, 'index');
    if (index == null) {
      return const ToolResult(
          toolName: 'browser_screenshot_element', success: false, output: '', error: 'index required');
    }
    if (_lastTree == null) {
      try { await capturePageState(); } catch (_) {}
      if (_lastTree == null) {
        return const ToolResult(
            toolName: 'browser_screenshot_element', success: false, output: '',
            error: 'No elements captured yet. Call browser_get_elements first.');
      }
    }
    final el = _lastTree!.elements.where((e) => e.index == index).firstOrNull;
    if (el == null) {
      return ToolResult(
          toolName: 'browser_screenshot_element', success: false, output: '',
          error: 'Element index $index not found in CDP tree. Call browser_get_elements first.');
    }
    // Use layout data from the element tree (same source as click/hover)
    final x = el.x;
    final y = el.y;
    final w = el.width;
    final h = el.height;
    if (w <= 0 || h <= 0) {
      return ToolResult(
          toolName: 'browser_screenshot_element', success: false, output: '',
          error: 'Element $index has zero dimensions — may be off-screen.');
    }
    try {
      // Add padding for context
      const pad = 8.0;
      final result = await _sessionManager.execute('Page.captureScreenshot', params: {
        'format': 'png',
        'clip': {
          'x': (x - pad).clamp(0, 10000).toDouble(),
          'y': (y - pad).clamp(0, 10000).toDouble(),
          'width': (w + pad * 2).toDouble(),
          'height': (h + pad * 2).toDouble(),
          'scale': 1,
        },
      });
      final data = result['data'] as String?;
      return ToolResult(
          toolName: 'browser_screenshot_element',
          success: data != null,
          output: 'Screenshot of <${el.tag}> element $index (CDP layout data)',
          data: data);
    } catch (e) {
      return ToolResult(
          toolName: 'browser_screenshot_element', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpDetectCaptcha() async {
    try {
      final result = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': '''
(function() {
  if (document.querySelector('.g-recaptcha, iframe[src*="recaptcha"], iframe[src*="hcaptcha"], .h-captcha, div.cf-turnstile, iframe[src*="turnstile"]')) {
    return JSON.stringify({found: true, type: 'reCAPTCHA/hCaptcha/Turnstile', hint: 'Captcha iframe detected'});
  }
  var body = (document.body ? document.body.innerText : '').toLowerCase();
  var patterns = ['captcha', '验证码', '人机验证', '滑块验证', 'security check'];
  for (var i = 0; i < patterns.length; i++) {
    if (body.indexOf(patterns[i]) >= 0) return JSON.stringify({found: true, type: 'text_match', text: patterns[i]});
  }
  var imgs = document.querySelectorAll('img[src*="captcha"], img[src*="Captcha"], img[src*="code"], img[src*="verify"]');
  for (var j = 0; j < imgs.length; j++) {
    if (imgs[j].width > 30 && imgs[j].width < 400) return JSON.stringify({found: true, type: 'captcha_image', src: imgs[j].src});
  }
  return JSON.stringify({found: false});
})()
''',
        'returnByValue': true,
      });
      return ToolResult(
          toolName: 'browser_detect_captcha', success: true,
          output: (result['result']?['value'] as String?) ?? '{"found":false}');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_detect_captcha', success: false, output: '{"found":false}', error: e.toString());
    }
  }

  Future<ToolResult> _cdpCheckErrors() async {
    try {
      // Check for page error indicators via Runtime.evaluate + console errors
      final result = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': '''
(function() {
  var errors = [];
  var title = document.title || '';
  if (/404|not found|500|error|forbidden/i.test(title)) errors.push('Page title: ' + title);
  // Check for error status in body text
  var body = (document.body ? document.body.innerText.substring(0, 2000) : '').toLowerCase();
  var indicators = ['404', '403', '500', '502', '503', 'not found', 'access denied', 'page not found', 'server error', 'forbidden'];
  for (var i = 0; i < indicators.length; i++) {
    if (body.indexOf(indicators[i]) >= 0) { errors.push('Body contains: ' + indicators[i]); break; }
  }
  return JSON.stringify({errors: errors, count: errors.length, ok: errors.length === 0});
})()
''',
        'returnByValue': true,
      });
      return ToolResult(
          toolName: 'browser_check_errors', success: true,
          output: (result['result']?['value'] as String?) ?? '{"errors":[],"count":0,"ok":true}');
    } catch (e) {
      return const ToolResult(
          toolName: 'browser_check_errors', success: true, output: '{"errors":[],"count":0,"ok":true}');
    }
  }

  Future<ToolResult> _cdpGetIframe(Map<String, dynamic> params) async {
    try {
      final result = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': '''
(function() {
  var frames = document.querySelectorAll('iframe, frame');
  var list = [];
  for (var i = 0; i < frames.length && i < 30; i++) {
    var f = frames[i];
    var info = {tag: f.tagName.toLowerCase(), src: f.src || '', name: f.name || '', id: f.id || ''};
    try {
      if (f.contentDocument) {
        var cnt = f.contentDocument.querySelectorAll('a[href],button,input,select,textarea').length;
        info.sameOrigin = true;
        info.interactiveCount = cnt;
      }
    } catch(e) { info.sameOrigin = false; info.crossOrigin = true; }
    list.push(info);
  }
  return JSON.stringify({total: list.length, iframes: list});
})()
''',
        'returnByValue': true,
      });
      return ToolResult(
          toolName: 'browser_get_iframe', success: true,
          output: (result['result']?['value'] as String?) ?? '{"total":0,"iframes":[]}');
    } catch (e) {
      return ToolResult(toolName: 'browser_get_iframe', success: false, output: '[]', error: e.toString());
    }
  }

  Future<ToolResult> _cdpSaveCookies() async {
    try {
      final result = await _sessionManager.execute('Network.getAllCookies');
      return ToolResult(
          toolName: 'browser_save_cookies', success: true, output: jsonEncode(result['cookies'] ?? []));
    } catch (e) {
      return ToolResult(
          toolName: 'browser_save_cookies', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpRestoreCookies(Map<String, dynamic> params) async {
    final cookies = params['cookies'] as List? ?? [];
    for (final c in cookies) {
      if (c is Map<String, dynamic>) {
        await _executeOrNull('Network.setCookie', params: c);
      }
    }
    return ToolResult(
        toolName: 'browser_restore_cookies', success: true, output: 'Restored ${cookies.length} cookies (CDP)');
  }

  Future<ToolResult> _cdpListDownloads() async {
    return const ToolResult(toolName: 'browser_list_downloads', success: true, output: '{"downloads":[],"total":0}');
  }

  Future<ToolResult> _cdpExecuteJs(Map<String, dynamic> params) async {
    final code = params['code'] as String? ?? '';
    try {
      final result = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': code,
        'returnByValue': true,
      });
      final resultObj = result['result'] as Map<String, dynamic>?;
      final type = resultObj?['type'] as String? ?? 'unknown';
      final value = resultObj?['value'];
      final exceptionDetails = result['exceptionDetails'] as Map<String, dynamic>?;

      if (exceptionDetails != null) {
        final excText = exceptionDetails['text'] as String? ?? jsonEncode(exceptionDetails);
        return ToolResult(
            toolName: 'browser_execute_js',
            success: true,
            output: 'Exception: $excText');
      }

      String output;
      if (type == 'undefined') {
        output = 'undefined';
      } else if (value == null && type == 'object') {
        output = 'null';
      } else {
        output = value?.toString() ?? jsonEncode(value);
      }
      return ToolResult(
          toolName: 'browser_execute_js',
          success: true,
          output: output);
    } catch (e) {
      return ToolResult(
          toolName: 'browser_execute_js', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpExtractDesign(Map<String, dynamic> params) async {
    final selector = params['selector'] as String?;
    var js = BrowserConstants.designExtractionScript;
    if (selector != null && selector.isNotEmpty) {
      final escaped = selector
          .replaceAll('\\', '\\\\')
          .replaceAll("'", "\\'")
          .replaceAll('\n', '\\n');
      js = js.replaceFirst(
        "var q = new URLSearchParams(location.search).get('extract');",
        "var q = '$escaped';",
      );
    }
    try {
      final result = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': js,
        'returnByValue': true,
      });
      final resultObj = result['result'] as Map<String, dynamic>?;
      final exceptionDetails = result['exceptionDetails'] as Map<String, dynamic>?;
      if (exceptionDetails != null) {
        final excText = exceptionDetails['text'] as String? ?? jsonEncode(exceptionDetails);
        return ToolResult(
          toolName: 'browser_extract_design',
          success: false,
          output: '',
          error: 'JS exception: $excText',
        );
      }
      final value = resultObj?['value'];
      final output = value is String ? value : jsonEncode(value);
      return ToolResult(
        toolName: 'browser_extract_design',
        success: true,
        output: output,
      );
    } catch (e) {
      print('[CdpBackend] error: $e');
      return ToolResult(
        toolName: 'browser_extract_design',
        success: false,
        output: '',
        error: e.toString(),
      );
    }
  }

  Future<ToolResult> _cdpWaitFor(Map<String, dynamic> params) async {
    final text = params['text'] as String?;
    final selector = params['selector'] as String?;
    final disappear = params['disappear'] as bool? ?? false;
    final timeout = _paramNum(params, 'timeout') ?? 10000;
    final maxWait = timeout.toInt().clamp(500, 30000);
    if (text == null && selector == null) {
      return const ToolResult(
          toolName: 'browser_wait_for', success: false, output: '',
          error: 'text or selector is required.');
    }
    final start = DateTime.now();
    final checkExpr = text != null
        ? "document.body && document.body.innerText.indexOf('${esc(text)}') >= 0"
        : "document.querySelector('${esc(selector!)}') !== null";
    final expression = disappear ? '!($checkExpr)' : checkExpr;

    while (DateTime.now().difference(start).inMilliseconds < maxWait) {
      try {
        final result = await _sessionManager.execute('Runtime.evaluate', params: {
          'expression': expression,
          'returnByValue': true,
        });
        final value = result['result']?['value'] as bool? ?? false;
        if (value) {
          return ToolResult(
              toolName: 'browser_wait_for',
              success: true,
              output: 'Condition met after ${DateTime.now().difference(start).inMilliseconds}ms');
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return ToolResult(
        toolName: 'browser_wait_for',
        success: false,
        output: '',
        error: 'Timed out after ${maxWait}ms waiting for ${disappear ? "disappearance of" : ""}: ${text ?? selector ?? "condition"}');
  }

  // ── Search / Content (CDP via Runtime.evaluate) ────────────────

  Future<ToolResult> _cdpFind(Map<String, dynamic> params) async {
    final text = params['text'] as String? ?? '';
    if (text.isEmpty) {
      return const ToolResult(
          toolName: 'browser_find', success: false, output: '', error: 'text is required');
    }
    try {
      await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': '''
(function() {
  var t='${esc(text)}';
  if(!t) return;
  if(!window.__bfH) window.__bfH=[];
  var old=window.__bfH;
  for(var i=0;i<old.length;i++){
    var el=old[i],p=el.parentNode;
    if(p){p.replaceChild(document.createTextNode(el.textContent),el);p.normalize();}
  }
  window.__bfH=[];
  var c=0,f=null;
  (function w(n){
    if(n.nodeType===3){
      var i=n.textContent.toLowerCase().indexOf(t.toLowerCase());
      if(i>=0){
        if(!f)f=n.parentElement;
        var s=document.createElement('mark');
        s.style.cssText='background:#FFEB3B;color:#000;padding:0 2px;border-radius:2px';
        s.textContent=n.textContent.substring(i,i+t.length);
        var a=n.splitText(i);
        a.splitText(t.length);
        a.parentNode.replaceChild(s,a);
        window.__bfH.push(s);
        c++;
      }
    }else if(n.nodeType===1&&!/^(SCRIPT|STYLE|MARK)\$/i.test(n.tagName)){
      for(var ch=n.firstChild;ch;ch=ch.nextSibling) w(ch);
    }
  })(document.body||document.documentElement);
  if(f) f.scrollIntoView({behavior:'smooth',block:'center'});
  return JSON.stringify({count:c,highlighted:c>0});
})()''',
        'returnByValue': true,
      });
      return const ToolResult(
          toolName: 'browser_find', success: true, output: 'Search complete');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_find', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpSearchPage(Map<String, dynamic> params) async {
    final text = params['text'] as String? ?? '';
    final useRegex = params['regex'] as bool? ?? false;
    final caseSensitive = params['case_sensitive'] as bool? ?? false;
    final maxResults = _paramInt(params, 'max_results') ?? 50;
    final contextChars = _paramInt(params, 'context_chars') ?? 80;
    if (text.isEmpty) {
      return const ToolResult(
          toolName: 'browser_search_page', success: false, output: '', error: 'text is required');
    }
    try {
      final result = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': '''
(function() {
  var t='${esc(text)}',re=$useRegex,cs=$caseSensitive,max=$maxResults,ctx=$contextChars;
  var p,results=[];
  if(re){try{p=new RegExp(t,cs?'g':'gi');}catch(e){return JSON.stringify({error:'Invalid regex: '+e.message});}}
  function w(n){
    if(results.length>=max)return;
    if(n.nodeType===3){
      var txt=n.textContent,m;
      if(re){
        p.lastIndex=0;
        while((m=p.exec(txt))!==null&&results.length<max){
          var s=Math.max(0,m.index-ctx),e=Math.min(txt.length,m.index+m[0].length+ctx);
          results.push({match:m[0],context:txt.substring(s,e),position:m.index});
        }
      }else{
        var sr=cs?txt:txt.toLowerCase(),fi=cs?t:t.toLowerCase(),pos=0;
        while((pos=sr.indexOf(fi,pos))!==-1&&results.length<max){
          var s=Math.max(0,pos-ctx),e=Math.min(txt.length,pos+t.length+ctx);
          results.push({match:txt.substring(pos,pos+t.length),context:txt.substring(s,e),position:pos});
          pos+=fi.length;
        }
      }
    }else if(n.nodeType===1&&!/^(SCRIPT|STYLE)\$/i.test(n.tagName)){
      for(var c=n.firstChild;c;c=c.nextSibling) w(c);
    }
  }
  if(document.body)w(document.body);
  return JSON.stringify({query:t,regex:re,caseSensitive:cs,total:results.length,results:results});
})()''',
        'returnByValue': true,
      });
      return ToolResult(
          toolName: 'browser_search_page', success: true,
          output: (result['result']?['value'] as String?) ?? '{"total":0,"results":[]}');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_search_page', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpFindElements(Map<String, dynamic> params) async {
    final selector = params['selector'] as String? ?? '';
    if (selector.isEmpty) {
      return const ToolResult(
          toolName: 'browser_find_elements', success: false, output: '', error: 'selector is required');
    }
    try {
      final result = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': '''
(function() {
  var sel='${esc(selector)}';
  var els=document.querySelectorAll(sel);
  var list=[];
  for(var i=0;i<els.length&&i<100;i++){
    var e=els[i];
    var r=e.getBoundingClientRect();
    list.push({index:i,tag:e.tagName.toLowerCase(),id:e.id||'',text:(e.textContent||'').trim().substring(0,100),x:r.left,y:r.top,w:r.width,h:r.height,visible:r.width>0&&r.height>0});
  }
  return JSON.stringify({total:list.length,elements:list});
})()''',
        'returnByValue': true,
      });
      return ToolResult(
          toolName: 'browser_find_elements', success: true,
          output: (result['result']?['value'] as String?) ?? '{"total":0,"elements":[]}');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_find_elements', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpDetectFormResult() async {
    try {
      final result = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': '''
(function() {
  var hints=[];
  var body=(document.body?document.body.innerText:'').toLowerCase();
  var patterns={success:['success','成功','完成','thank you','thankyou','submitted','已提交','已保存','saved','confirmed','已确认','sent','已发送'],error:['error','错误','failed','失败','invalid','无效','required','必填','try again','重试','incorrect','不正确'],redirect:['redirecting','跳转','please wait','请稍候','loading','加载中']};
  for(var cat in patterns){
    for(var i=0;i<patterns[cat].length;i++){
      if(body.indexOf(patterns[cat][i])>=0){hints.push(cat+':'+patterns[cat][i]);break;}
    }
  }
  var alerts=document.querySelectorAll('[role="alert"],.alert,.error,.success,.message,.toast,.notification');
  for(var j=0;j<alerts.length&&j<5;j++){
    var t=(alerts[j].textContent||'').trim().substring(0,200);
    if(t) hints.push('alert:'+t);
  }
  var urlChanged=false;
  try{urlChanged=window.location.href!==(window.__bfLastUrl||window.location.href);window.__bfLastUrl=window.location.href;}catch(e){}
  return JSON.stringify({hints:hints,urlChanged:urlChanged,verdict:hints.length>0?'likely_submitted':'uncertain'});
})()''',
        'returnByValue': true,
      });
      return ToolResult(
          toolName: 'browser_detect_form_result', success: true,
          output: (result['result']?['value'] as String?) ?? '{"verdict":"uncertain"}');
    } catch (e) {
      return const ToolResult(
          toolName: 'browser_detect_form_result', success: true, output: '{"verdict":"uncertain"}');
    }
  }

  Future<ToolResult> _cdpHumanAssist(Map<String, dynamic> params) async {
    final reason = params['reason'] as String? ?? 'Human assistance needed';
    final prompt = params['prompt'] as String?;
    try {
      final response = await onHumanAssist?.call(reason, prompt);
      if (response != null && response.isNotEmpty) {
        return ToolResult(
            toolName: 'browser_human_assist', success: true, output: response);
      }
      return ToolResult(
          toolName: 'browser_human_assist', success: true,
          output: 'Human assist requested: $reason (no response)');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_human_assist', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpLoadHtml(Map<String, dynamic> params) async {
    final html = params['html'] as String? ?? '';
    if (html.isEmpty) {
      return const ToolResult(
          toolName: 'browser_load_html', success: false, output: '', error: 'html is required');
    }
    try {
      await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': "document.documentElement.innerHTML='${esc(html)}';void(0)",
      });
      return const ToolResult(
          toolName: 'browser_load_html', success: true, output: 'HTML loaded (CDP)');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_load_html', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpScrollAndCollect(Map<String, dynamic> params) async {
    final maxScreens = _paramInt(params, 'maxScreens') ?? 3;
    try {
      final result = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': '''
(function() {
  var ms=$maxScreens;
  var all='';
  var vh=window.innerHeight;
  for(var i=0;i<ms;i++){
    var t=document.body?document.body.innerText:'';
    if(t) all+=t+'\\n---page '+(i+1)+'---\\n';
    window.scrollBy(0,vh*0.8);
  }
  return JSON.stringify({screens:ms,chars:all.length,text:all.substring(0,12000)});
})()''',
        'returnByValue': true,
      });
      final output = (result['result']?['value'] as String?) ?? '{}';
      return ToolResult(
          toolName: 'browser_scroll_and_collect', success: true, output: output);
    } catch (e) {
      return ToolResult(
          toolName: 'browser_scroll_and_collect', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpDrag(Map<String, dynamic> params) async {
    final fromIndex = _paramInt(params, 'fromIndex');
    final toIndex = _paramInt(params, 'toIndex');
    final dx = _paramDouble(params, 'dx');
    final dy = _paramDouble(params, 'dy');
    if (fromIndex == null) {
      return const ToolResult(
          toolName: 'browser_drag', success: false, output: '', error: 'fromIndex required');
    }
    if (_lastTree == null) {
      try { await capturePageState(); } catch (_) {}
      if (_lastTree == null) {
        return const ToolResult(
            toolName: 'browser_drag', success: false, output: '',
            error: 'No elements captured yet. Call browser_get_elements first.');
      }
    }
    final fromEl = _lastTree!.elements.where((e) => e.index == fromIndex).firstOrNull;
    if (fromEl == null) {
      return ToolResult(
          toolName: 'browser_drag', success: false, output: '',
          error: 'Element $fromIndex not found. Call browser_get_elements first.');
    }
    try {
      double endX, endY;
      if (dx != null && dy != null) {
        endX = fromEl.centerX + dx;
        endY = fromEl.centerY + dy;
      } else if (toIndex != null) {
        final toEl = _lastTree!.elements.where((e) => e.index == toIndex).firstOrNull;
        if (toEl == null) {
          return ToolResult(
              toolName: 'browser_drag', success: false, output: '',
              error: 'Target element $toIndex not found.');
        }
        endX = toEl.centerX;
        endY = toEl.centerY;
      } else {
        return const ToolResult(
            toolName: 'browser_drag', success: false, output: '',
            error: 'Provide toIndex or both dx+dy');
      }
      // Drag sequence: press → move (multiple) → release
      await dispatchMouseEvent(CdpMouseEvent(type: 'mousePressed', x: fromEl.centerX, y: fromEl.centerY));
      // Move in steps for smooth drag
      const steps = 5;
      for (int i = 1; i <= steps; i++) {
        final t = i / steps;
        final mx = fromEl.centerX + (endX - fromEl.centerX) * t;
        final my = fromEl.centerY + (endY - fromEl.centerY) * t;
        await dispatchMouseEvent(CdpMouseEvent(type: 'mouseMoved', x: mx, y: my));
        await Future.delayed(const Duration(milliseconds: 20));
      }
      await dispatchMouseEvent(CdpMouseEvent(type: 'mouseReleased', x: endX, y: endY));
      return ToolResult(
          toolName: 'browser_drag', success: true,
          output: 'Dragged from [$fromIndex] to (${endX.toStringAsFixed(0)}, ${endY.toStringAsFixed(0)}) (CDP)');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_drag', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpClipboardCopy(Map<String, dynamic> params) async {
    final index = _paramInt(params, 'index');
    try {
      if (index != null && _lastTree != null) {
        // Copy specific element text via CDP Input + JS clipboard
        final el = _lastTree!.elements.where((e) => e.index == index).firstOrNull;
        if (el == null) {
          return ToolResult(
              toolName: 'browser_clipboard_copy', success: false, output: '',
              error: 'Element $index not found. Call browser_get_elements first.');
        }
        // Click to focus, then select text via Ctrl+A, copy via Ctrl+C
        await dispatchMouseEvent(CdpMouseEvent(type: 'mouseMoved', x: el.centerX, y: el.centerY));
        await dispatchMouseEvent(CdpMouseEvent(type: 'mousePressed', x: el.centerX, y: el.centerY, clickCount: 1));
        await dispatchMouseEvent(CdpMouseEvent(type: 'mouseReleased', x: el.centerX, y: el.centerY, clickCount: 1));
        await Future.delayed(const Duration(milliseconds: 80));
        await dispatchKeyEvent(const CdpKeyEvent(type: 'rawKeyDown', key: 'a', code: 'KeyA', modifiers: 2));
        await dispatchKeyEvent(const CdpKeyEvent(type: 'keyUp', key: 'a', code: 'KeyA', modifiers: 2));
        await Future.delayed(const Duration(milliseconds: 30));
        await dispatchKeyEvent(const CdpKeyEvent(type: 'rawKeyDown', key: 'c', code: 'KeyC', modifiers: 2));
        await dispatchKeyEvent(const CdpKeyEvent(type: 'keyUp', key: 'c', code: 'KeyC', modifiers: 2));
        return ToolResult(
            toolName: 'browser_clipboard_copy', success: true,
            output: 'Copied <${el.tag}> text to clipboard (Ctrl+C via CDP Input)');
      }
      // No index: copy current selection or all text via JS
      final result = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': '''
(function() {
  var sel=window.getSelection();
  var text=sel?sel.toString():'';
  if(!text)text=(document.body?document.body.innerText:'').substring(0,500);
  try{navigator.clipboard.writeText(text);return JSON.stringify({copied:true,length:text.length});}
  catch(e){return JSON.stringify({copied:false,error:e.toString(),text:text.substring(0,200)});}
})()''',
        'returnByValue': true,
      });
      return ToolResult(
          toolName: 'browser_clipboard_copy', success: true,
          output: (result['result']?['value'] as String?) ?? '{"copied":false}');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_clipboard_copy', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpClipboardPaste(Map<String, dynamic> params) async {
    final index = _paramInt(params, 'index');
    try {
      // Focus the target element via CDP click (trusted event)
      if (index != null && _lastTree != null) {
        final el = _lastTree!.elements.where((e) => e.index == index).firstOrNull;
        if (el == null) {
          return ToolResult(
              toolName: 'browser_clipboard_paste', success: false, output: '',
              error: 'Element $index not found. Call browser_get_elements first.');
        }
        // Click to focus + establish user gesture
        await dispatchMouseEvent(CdpMouseEvent(type: 'mouseMoved', x: el.centerX, y: el.centerY));
        await dispatchMouseEvent(CdpMouseEvent(type: 'mousePressed', x: el.centerX, y: el.centerY, clickCount: 1));
        await dispatchMouseEvent(CdpMouseEvent(type: 'mouseReleased', x: el.centerX, y: el.centerY, clickCount: 1));
        await Future.delayed(const Duration(milliseconds: 80));

        // Use CDP key events for paste (Ctrl+V / Meta+V) — trusted, bypasses clipboard API restrictions
        await dispatchKeyEvent(const CdpKeyEvent(type: 'rawKeyDown', key: 'Control', code: 'ControlLeft', modifiers: 2));
        await dispatchKeyEvent(const CdpKeyEvent(type: 'rawKeyDown', key: 'v', code: 'KeyV', modifiers: 2));
        await dispatchKeyEvent(const CdpKeyEvent(type: 'keyUp', key: 'v', code: 'KeyV', modifiers: 2));
        await dispatchKeyEvent(const CdpKeyEvent(type: 'keyUp', key: 'Control', code: 'ControlLeft'));
        return ToolResult(
            toolName: 'browser_clipboard_paste', success: true,
            output: 'Pasted (Ctrl+V via CDP Input) into <${el.tag}> at index $index');
      }
      // No index: paste into focused element
      await dispatchKeyEvent(const CdpKeyEvent(type: 'rawKeyDown', key: 'Control', code: 'ControlLeft', modifiers: 2));
      await dispatchKeyEvent(const CdpKeyEvent(type: 'rawKeyDown', key: 'v', code: 'KeyV', modifiers: 2));
      await dispatchKeyEvent(const CdpKeyEvent(type: 'keyUp', key: 'v', code: 'KeyV', modifiers: 2));
      await dispatchKeyEvent(const CdpKeyEvent(type: 'keyUp', key: 'Control', code: 'ControlLeft'));
      return const ToolResult(
          toolName: 'browser_clipboard_paste', success: true,
          output: 'Pasted (Ctrl+V via CDP Input)');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_clipboard_paste', success: false, output: '', error: e.toString());
    }
  }

  /// Coerce a params value to int, accepting both int and String (LLMs often
  /// pass numbers as strings like `"1"` instead of `1`).
  static int? _paramInt(Map<String, dynamic> params, String key) {
    final v = params[key];
    if (v == null) return null;
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    if (v is num) return v.toInt();
    return null;
  }

  /// Coerce a params value to num, accepting both num and String.
  static num? _paramNum(Map<String, dynamic> params, String key) {
    final v = params[key];
    if (v == null) return null;
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  /// Coerce a params value to double, accepting num and String.
  static double? _paramDouble(Map<String, dynamic> params, String key) {
    final v = params[key];
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Escape string for safe interpolation into JS single-quoted string.
  @visibleForTesting
  // ── Page control ──────────────────────────────────────────────

  Future<ToolResult> _cdpReload() async {
    try {
      await _sessionManager.execute('Page.reload');
      return const ToolResult(
          toolName: 'browser_reload', success: true, output: 'Page reloaded (CDP)');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_reload', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpStop() async {
    try {
      await _sessionManager.execute('Page.stopLoading');
      return const ToolResult(
          toolName: 'browser_stop', success: true, output: 'Page loading stopped (CDP)');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_stop', success: false, output: '', error: e.toString());
    }
  }

  // ── Diagnostics ────────────────────────────────────────────────

  Future<ToolResult> _cdpGetViewport() async {
    try {
      final result = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': 'JSON.stringify({width: window.innerWidth, height: window.innerHeight, devicePixelRatio: window.devicePixelRatio, scrollX: window.scrollX, scrollY: window.scrollY})',
        'returnByValue': true,
      });
      return ToolResult(
          toolName: 'browser_get_viewport', success: true,
          output: (result['result']?['value'] as String?) ?? '{"width":0,"height":0}');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_get_viewport', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpGetDom(Map<String, dynamic> params) async {
    final selector = params['selector'] as String?;
    final expr = selector != null
        ? "(function(){var el=document.querySelector('${esc(selector!)}'); return el?el.outerHTML:'Selector not found: ${esc(selector!)}';})()"
        : 'document.documentElement.outerHTML';
    try {
      final result = await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': expr, 'returnByValue': true,
      });
      final html = (result['result']?['value'] as String?) ?? '';
      final output = html.length > 20000 ? '${html.substring(0, 20000)}\n...[truncated ${html.length} chars]' : html;
      return ToolResult(toolName: 'browser_get_dom', success: true, output: output);
    } catch (e) {
      return ToolResult(
          toolName: 'browser_get_dom', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpDeleteCookies() async {
    try {
      await _sessionManager.execute('Network.clearBrowserCookies');
      return const ToolResult(
          toolName: 'browser_delete_cookies', success: true, output: 'All cookies cleared (CDP)');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_delete_cookies', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpClearCache() async {
    try {
      await _sessionManager.execute('Network.clearBrowserCache');
      return const ToolResult(
          toolName: 'browser_clear_cache', success: true, output: 'Browser cache cleared (CDP)');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_clear_cache', success: false, output: '', error: e.toString());
    }
  }

  Future<ToolResult> _cdpFillForm(Map<String, dynamic> params) async {
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
      final typeResult = await _cdpType({'index': index, 'text': text, 'clear': true});
      buf.writeln(typeResult.success ? typeResult.output : 'ERR: ${typeResult.error}');
    }
    return ToolResult(toolName: 'browser_fill_form', success: true, output: buf.toString());
  }

  Future<ToolResult> _cdpAddScript(Map<String, dynamic> params) async {
    final code = params['code'] as String? ?? '';
    if (code.isEmpty) {
      return const ToolResult(
          toolName: 'browser_add_script', success: false, output: '', error: 'code is required');
    }
    try {
      await _sessionManager.execute('Page.addScriptToEvaluateOnNewDocument', params: {'source': code});
      return const ToolResult(
          toolName: 'browser_add_script', success: true, output: 'Script injected (CDP)');
    } catch (e) {
      // Fall back to Runtime.evaluate for immediate execution
      return _cdpExecuteJs(params);
    }
  }

  Future<ToolResult> _cdpAddStylesheet(Map<String, dynamic> params) async {
    final css = params['css'] as String? ?? '';
    if (css.isEmpty) {
      return const ToolResult(
          toolName: 'browser_add_stylesheet', success: false, output: '', error: 'css is required');
    }
    try {
      // Inject via Runtime.evaluate — Page.addStyleSheet is less reliable in WebView
      await _sessionManager.execute('Runtime.evaluate', params: {
        'expression': "(function(){var s=document.createElement('style');s.textContent='${esc(css)}';document.head.appendChild(s);return'ok';})()",
        'returnByValue': true,
      });
      return const ToolResult(
          toolName: 'browser_add_stylesheet', success: true, output: 'Stylesheet injected (CDP)');
    } catch (e) {
      return ToolResult(
          toolName: 'browser_add_stylesheet', success: false, output: '', error: e.toString());
    }
  }

  // ── Network/CDP event collectors ───────────────────────────────

  final List<String> _networkEventBuffer = [];
  final List<String> _consoleEventBuffer = [];

  Future<ToolResult> _cdpGetNetworkRequests() async {
    // Return buffered network events (populated by subscriptions in initialize())
    if (_networkEventBuffer.isEmpty) {
      return const ToolResult(
          toolName: 'browser_get_network_requests', success: true,
          output: '{"requests":[],"total":0}');
    }
    final buf = StringBuffer();
    final recent = _networkEventBuffer.take(100);
    for (final evt in recent) {
      buf.writeln(evt.length > 300 ? '${evt.substring(0, 300)}...' : evt);
    }
    return ToolResult(toolName: 'browser_get_network_requests', success: true,
        output: '{"total":${_networkEventBuffer.length},"recent":[\n${buf.toString()}\n]}');
  }

  Future<ToolResult> _cdpGetCdpLogs() async {
    if (_consoleEventBuffer.isEmpty) {
      return const ToolResult(
          toolName: 'browser_get_cdp_logs', success: true,
          output: '{"logs":[],"total":0}');
    }
    final buf = StringBuffer();
    for (final evt in _consoleEventBuffer.take(100)) {
      buf.writeln(evt);
    }
    return ToolResult(toolName: 'browser_get_cdp_logs', success: true,
        output: '{"total":${_consoleEventBuffer.length},"logs":[\n${buf.toString()}\n]}');
  }

  static String esc(String s) {
    return s
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
  }

  // ── Internal helpers ────────────────────────────────────────────

  Future<String?> _resolveObjectId(int backendNodeId) async {
    try {
      final result = await _sessionManager.execute('DOM.resolveNode', params: {
        'backendNodeId': backendNodeId,
      });
      return result['object']?['objectId'] as String?;
    } catch (_) {
      return null;
    }
  }
}
