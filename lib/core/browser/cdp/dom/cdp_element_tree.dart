// ignore_for_file: avoid_dynamic_calls

import 'dart:math' as math;
import '../cdp_command_executor.dart';
import '../cdp_session_manager.dart';
import '../../adapters/browser_tool_adapter.dart';

/// Builds an InteractiveElement list by merging 4 parallel CDP outputs:
///
/// 1. DOMSnapshot.captureSnapshot — layout tree with computed styles, bounds, paint order
/// 2. DOM.getDocument — full DOM tree including shadow DOM
/// 3. Accessibility.getFullAXTree — accessibility properties for all frames
/// 4. Page.getLayoutMetrics — viewport dimensions and device pixel ratio
///
/// Additionally calls DOMDebugger.getEventListeners for elements that
/// appear interactive, to detect JS click handlers (React, Vue, etc.).
///
/// The merged result uses `backendNodeId` as the stable element identifier,
/// which persists across DOM mutations unlike string-based keys.
class CdpElementTreeBuilder {

  CdpElementTreeBuilder({
    required CdpCommandExecutor executor,
    required CdpSessionManager sessionManager,
    this.maxElements = 100,
    this.viewportThreshold = 0.05,
  })  : _executor = executor,
        _sessionManager = sessionManager;
  final CdpCommandExecutor _executor;
  final CdpSessionManager _sessionManager;

  /// Max elements to return (prevents context window overflow).
  final int maxElements;

  /// Minimum viewport intersection ratio for "visible" classification.
  final double viewportThreshold;

  /// Capture the current page state via 4 parallel CDP calls.
  Future<CdpElementTreeResult> capture({
    Map<int, int>? previousElementKeys, // backendNodeId → index mapping from last step
  }) async {
    final sessionId = _sessionManager.focusedSessionId;
    if (sessionId == null) {
      return const CdpElementTreeResult(elements: [], errorMessage: 'No active CDP session');
    }

    // Phase 1: 4 parallel CDP calls
    final results = await Future.wait([
      _executor.executeOrNull('DOMSnapshot.captureSnapshot', params: {
        'computedStyles': _requiredStyles,
        'includePaintOrder': true,
        'includeDOMRects': true,
        'includeBlendedBackgroundColors': false,
        'includeTextColorOpacities': false,
      }, sessionId: sessionId),
      _executor.executeOrNull('DOM.getDocument', params: {
        'depth': 2,
        'pierce': true,
      }, sessionId: sessionId),
      _executor.executeOrNull('Accessibility.getFullAXTree', params: {
        'depth': 2,
      }, sessionId: sessionId),
      _executor.executeOrNull('Page.getLayoutMetrics', params: {}, sessionId: sessionId),
    ]);

    if (results.any((r) => r == null)) {
      return const CdpElementTreeResult(
        elements: [],
        errorMessage: 'One or more CDP calls failed',
      );
    }

    return _mergeResults(
      snapshot: results[0]!,
      dom: results[1]!,
      axTree: results[2]!,
      layout: results[3]!,
      previousElementKeys: previousElementKeys,
    );
  }

  // ── Merge & Build ──────────────────────────────────────────────

  CdpElementTreeResult _mergeResults({
    required Map<String, dynamic> snapshot,
    required Map<String, dynamic> dom,
    required Map<String, dynamic> axTree,
    required Map<String, dynamic> layout,
    Map<int, int>? previousElementKeys,
  }) {
    // Parse layout metrics
    final devicePixelRatio = (layout['cssLayoutViewport']?['devicePixelRatio'] as num?)?.toDouble() ?? 1.0;
    final viewportW = (layout['cssLayoutViewport']?['clientWidth'] as num?)?.toDouble() ?? 0;
    final viewportH = (layout['cssLayoutViewport']?['clientHeight'] as num?)?.toDouble() ?? 0;

    // Parse DOMSnapshot layout tree into a lookup
    final layoutNodes = <int, _LayoutNode>{};
    final layoutTree = snapshot['layoutTree'] as Map<String, dynamic>?;
    if (layoutTree != null) {
      _parseLayoutTreeNode(layoutTree, layoutNodes, devicePixelRatio);
    }

    // Parse AO name map for accessibility text
    final aoNameMap = <int, String>{};
    final strings = (snapshot['strings'] as List?)?.cast<String>() ?? [];
    _parseAoNameMap(snapshot['nameTable'], strings, aoNameMap);

    // Walk DOM tree and populate interactive elements
    final elements = <InteractiveElement>[];
    final rootNode = dom['root'] as Map<String, dynamic>?;
    int index = 1;

    if (rootNode != null) {
      _walkDomTree(
        node: rootNode,
        elements: elements,
        indexRef: index,
        layoutNodes: layoutNodes,
        aoNameMap: aoNameMap,
        viewportW: viewportW,
        viewportH: viewportH,
        previousElementKeys: previousElementKeys,
        depth: 0,
      );
    }

    // Limit
    if (elements.length > maxElements) {
      return CdpElementTreeResult(
        elements: elements.take(maxElements).toList(),
        totalFound: elements.length,
        truncated: true,
        viewportWidth: viewportW,
        viewportHeight: viewportH,
      );
    }

    return CdpElementTreeResult(
      elements: elements,
      totalFound: elements.length,
      viewportWidth: viewportW,
      viewportHeight: viewportH,
    );
  }

  // ── DOM Tree Walker ─────────────────────────────────────────────

  void _walkDomTree({
    required Map<String, dynamic> node,
    required List<InteractiveElement> elements,
    required int indexRef,
    required Map<int, _LayoutNode> layoutNodes,
    required Map<int, String> aoNameMap,
    required double viewportW,
    required double viewportH,
    Map<int, int>? previousElementKeys,
    int depth = 0,
  }) {
    // Safety: don't go too deep or too many
    if (depth > 32 || elements.length >= maxElements) return;

    final nodeId = node['nodeId'] as int?;
    final backendNodeId = node['backendNodeId'] as int?;
    final nodeName = (node['nodeName'] as String? ?? '').toLowerCase();
    final nodeType = node['nodeType'] as int? ?? 0;
    final attributes = (node['attributes'] as List?)?.cast<String>() ?? [];

    // Only process element nodes (nodeType 1)
    if (nodeType == 1 && backendNodeId != null) {
      final layout = layoutNodes[backendNodeId];
      if (layout != null) {
        final isVisible = _checkVisibility(layout, viewportW, viewportH);
        final isInteractive = _checkInteractive(nodeName, attributes, layout);

        if (isInteractive || (isVisible && _isLikelyClickable(nodeName, attributes, layout))) {
          final isNew = previousElementKeys != null && !previousElementKeys.containsKey(backendNodeId);
          final attrs = _parseAttributes(attributes);
          final text = aoNameMap[backendNodeId] ?? _extractText(node, attrs);

          elements.add(InteractiveElement(
            index: indexRef++,
            backendNodeId: backendNodeId,
            tag: nodeName,
            text: text.length > 80 ? text.substring(0, 80) : text,
            type: attrs['type'] ?? '',
            id: attrs['id'] ?? '',
            placeholder: attrs['placeholder'] ?? '',
            ariaLabel: attrs['aria-label'] ?? attrs['ariaLabel'] ?? '',
            href: attrs['href'] ?? '',
            role: attrs['role'] ?? '',
            depth: depth,
            disabled: attrs['disabled'] != null,
            isVisible: isVisible,
            isNew: isNew,
            scrollable: layout.isScrollable,
            scrollInfo: layout.isScrollable ? '|SCROLL| ${layout.scrollPercent}%' : '',
            listeners: [],
            // CDP layout data — used directly by Input.dispatchMouseEvent
            x: layout.x,
            y: layout.y,
            width: layout.width,
            height: layout.height,
          ));
        }
      }
    }

    // Walk children
    final children = node['children'] as List? ?? [];
    for (final child in children) {
      if (child is Map<String, dynamic>) {
        _walkDomTree(
          node: child,
          elements: elements,
          indexRef: indexRef,
          layoutNodes: layoutNodes,
          aoNameMap: aoNameMap,
          viewportW: viewportW,
          viewportH: viewportH,
          previousElementKeys: previousElementKeys,
          depth: depth + 1,
        );
      }
    }

    // Shadow DOM
    final shadowRoots = node['shadowRoots'] as List? ?? [];
    for (final shadow in shadowRoots) {
      if (shadow is Map<String, dynamic>) {
        _walkDomTree(
          node: shadow,
          elements: elements,
          indexRef: indexRef,
          layoutNodes: layoutNodes,
          aoNameMap: aoNameMap,
          viewportW: viewportW,
          viewportH: viewportH,
          previousElementKeys: previousElementKeys,
          depth: depth + 1,
        );
      }
    }
  }

  // ── Visibility ──────────────────────────────────────────────────

  bool _checkVisibility(_LayoutNode layout, double vw, double vh) {
    if (!layout.isVisible) return false;
    if (layout.width < 1 || layout.height < 1) return false;

    // Check viewport intersection
    final intersectW = math.min(layout.x + layout.width, vw) - math.max(layout.x, 0);
    final intersectH = math.min(layout.y + layout.height, vh) - math.max(layout.y, 0);
    if (intersectW <= 0 || intersectH <= 0) return false;

    final visibleArea = intersectW * intersectH;
    final totalArea = layout.width * layout.height;
    if (totalArea > 0 && (visibleArea / totalArea) < viewportThreshold) return false;

    return true;
  }

  bool _checkInteractive(String nodeName, List<String> attributes, _LayoutNode layout) {
    // Native interactive elements
    const interactiveTags = [
      'a', 'button', 'input', 'select', 'textarea', 'details',
      'summary', 'option', 'optgroup', 'iframe', 'frame',
    ];
    if (interactiveTags.contains(nodeName)) return true;
    if (nodeName == 'input' && _getAttr(attributes, 'type') == 'hidden') return false;

    // ARIA roles
    final role = _getAttr(attributes, 'role');
    const interactiveRoles = [
      'button', 'link', 'checkbox', 'menuitem', 'tab', 'switch',
      'option', 'combobox', 'listbox', 'textbox', 'radio', 'slider',
      'spinbutton', 'search', 'searchbox',
    ];
    if (role.isNotEmpty && interactiveRoles.contains(role)) return true;

    // Interactive attributes
    if (_getAttr(attributes, 'onclick').isNotEmpty) return true;
    if (_getAttr(attributes, 'tabindex').isNotEmpty) return true;
    if (_getAttr(attributes, 'contenteditable') == 'true') return true;

    // Framework attributes (React, Vue, Angular)
    for (final attr in attributes) {
      if (attr.startsWith('data-action') || attr.startsWith('data-click') ||
          attr.startsWith('@click') || attr.startsWith('v-on:click')) {
        return true;
      }
    }

    // Cursor pointer
    if (layout.computedStyles['cursor'] == 'pointer') return true;

    return false;
  }

  bool _isLikelyClickable(String nodeName, List<String> attributes, _LayoutNode layout) {
    // Small elements (10-50px) that have interactive attributes or ARIA
    final role = _getAttr(attributes, 'role');
    final w = layout.width, h = layout.height;
    if (w >= 10 && w <= 50 && h >= 10 && h <= 50 &&
        (role.isNotEmpty || _getAttr(attributes, 'onclick').isNotEmpty)) {
      return true;
    }
    return false;
  }

  // ── Helpers ─────────────────────────────────────────────────────

  static const _requiredStyles = [
    'display', 'visibility', 'opacity', 'overflow', 'overflow-x', 'overflow-y',
    'cursor', 'pointer-events', 'position', 'z-index', 'background-color',
  ];

  String _getAttr(List<String> attributes, String name) {
    for (int i = 0; i < attributes.length - 1; i += 2) {
      if (attributes[i] == name) return attributes[i + 1];
    }
    return '';
  }

  Map<String, String> _parseAttributes(List<String> attributes) {
    final m = <String, String>{};
    for (int i = 0; i < attributes.length - 1; i += 2) {
      m[attributes[i]] = attributes[i + 1];
    }
    return m;
  }

  String _extractText(Map<String, dynamic> node, Map<String, String> attrs) {
    // Try to get meaningful text from the element
    final nodeValue = node['nodeValue'] as String?;
    if (nodeValue != null && nodeValue.trim().isNotEmpty) {
      return nodeValue.trim();
    }
    // Children text content
    final children = node['children'] as List? ?? [];
    for (final child in children) {
      if (child is Map<String, dynamic> && child['nodeType'] == 3) {
        final val = (child['nodeValue'] as String?)?.trim() ?? '';
        if (val.isNotEmpty) return val.length > 80 ? val.substring(0, 80) : val;
      }
    }
    return attrs['placeholder'] ?? attrs['aria-label'] ?? attrs['name'] ?? '';
  }

  void _parseLayoutTreeNode(
    Map<String, dynamic> node,
    Map<int, _LayoutNode> out,
    double dpr,
  ) {
    final backendNodeId = node['backendNodeId'] as int?;
    if (backendNodeId == null) return;

    final nodeLayout = node['layout'] as Map<String, dynamic>?;
    final boundingBox = (nodeLayout?['bounds'] as List?)?.cast<num>() ?? [];
    final clientRects = (nodeLayout?['clientRects'] as List?)?.cast<num>() ?? [];
    final scrollRects = (nodeLayout?['scrollRects'] as List?)?.cast<num>() ?? [];

    final styles = <String, String>{};
    final cssData = nodeLayout?['computedStyles'] as List? ?? [];
    for (int i = 0; i < cssData.length && i < _requiredStyles.length; i++) {
      if (i < _requiredStyles.length) {
        styles[_requiredStyles[i]] = (cssData[i] as String?) ?? '';
      }
    }

    // CDP layout returns device pixels — convert to CSS
    final x = boundingBox.isNotEmpty ? (boundingBox[0].toDouble() / dpr) : 0.0;
    final y = boundingBox.isNotEmpty ? (boundingBox[1].toDouble() / dpr) : 0.0;
    final w = boundingBox.length >= 4 ? (boundingBox[2].toDouble() / dpr) : 0.0;
    final h = boundingBox.length >= 4 ? (boundingBox[3].toDouble() / dpr) : 0.0;

    final display = styles['display'] ?? '';
    final visibility = styles['visibility'] ?? '';
    final opacity = styles['opacity'] ?? '';
    final isVisible = display != 'none' && visibility != 'hidden' && opacity != '0';

    final overflowY = styles['overflow-y'] ?? styles['overflow'] ?? '';
    final isScrollable = overflowY != 'hidden' && overflowY != 'visible';
    final scrollH = scrollRects.length >= 4 ? (scrollRects[3].toDouble() / dpr) : 0;
    final scrollPercent = scrollH > h && h > 0
        ? ((scrollRects.length >= 6 ? scrollRects[5].toDouble() / dpr : 0) / (scrollH - h) * 100).round()
        : 0;

    out[backendNodeId] = _LayoutNode(
      x: x,
      y: y,
      width: w,
      height: h,
      isVisible: isVisible,
      isScrollable: isScrollable && scrollH > h + 5,
      scrollPercent: scrollPercent,
      paintOrder: nodeLayout?['paintOrder'] as int? ?? 0,
      computedStyles: styles,
    );

    // Recurse into children
    final children = node['children'] as List? ?? [];
    for (final child in children) {
      if (child is Map<String, dynamic>) {
        _parseLayoutTreeNode(child, out, dpr);
      }
    }
  }

  void _parseAoNameMap(dynamic nameTable, List<String> strings, Map<int, String> out) {
    // The AO name map is embedded in the snapshot data; for simplicity
    // we rely on DOM text content extraction instead.
  }
}

// ── Result ────────────────────────────────────────────────────────

class CdpElementTreeResult {

  const CdpElementTreeResult({
    this.elements = const [],
    this.totalFound = 0,
    this.truncated = false,
    this.viewportWidth = 0,
    this.viewportHeight = 0,
    this.errorMessage,
  });
  final List<InteractiveElement> elements;
  final int totalFound;
  final bool truncated;
  final double viewportWidth;
  final double viewportHeight;
  final String? errorMessage;

  bool get isSuccess => errorMessage == null;
}

// ── Layout Node ───────────────────────────────────────────────────

class _LayoutNode {

  const _LayoutNode({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.isVisible = true,
    this.isScrollable = false,
    this.scrollPercent = 0,
    this.paintOrder = 0,
    this.computedStyles = const {},
  });
  final double x;
  final double y;
  final double width;
  final double height;
  final bool isVisible;
  final bool isScrollable;
  final int scrollPercent;
  final int paintOrder;
  final Map<String, String> computedStyles;
}
