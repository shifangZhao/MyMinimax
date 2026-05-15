import 'cdp_connection.dart';
import 'cdp_command_executor.dart';
import 'cdp_message.dart';

/// Tracks browser targets (pages, iframes) and their CDP sessions.
///
/// CDP multiplexes all communication over a single WebSocket connection.
/// Each target (page, iframe, worker) gets a unique `sessionId` that is
/// passed with every command to route it to the correct renderer process.
///
/// This manager:
/// - Discovers all targets via `Target.getTargets`
/// - Listens for Target.attachedToTarget / detachedFromTarget events
/// - Maintains a Target tree (page → iframe → child iframe)
/// - Routes commands to the correct sessionId
class CdpSessionManager {

  CdpSessionManager({
    required CdpConnection connection,
    required CdpCommandExecutor executor,
  })  : _connection = connection,
        _executor = executor;
  final CdpConnection _connection;
  final CdpCommandExecutor _executor;

  /// All known browser targets, keyed by targetId.
  final Map<String, _CdpTarget> _targets = {};

  /// Current page targets only (type == 'page').
  final List<_CdpTarget> _pages = [];

  /// The agent's focused target (active tab).
  _CdpTarget? _focusedTarget;

  /// Maps frameId to targetId for iframe routing.
  final Map<String, String> _frameToTarget = {};

  _CdpTarget? get focusedTarget => _focusedTarget;
  String? get focusedSessionId => _focusedTarget?.sessionId;
  List<_CdpTarget> get pages => List.unmodifiable(_pages);

  /// Initialize: enable Target domain, discover existing targets, start monitoring.
  Future<void> initialize() async {
    // Enable target discovery
    await _executor.execute('Target.setDiscoverTargets', params: {
      'discover': true,
      'filter': [
        {'type': 'page'},
        {'type': 'iframe'},
      ],
    });

    // Subscribe to target lifecycle events
    _connection.on('Target', _onTargetEvent);

    // Discover already-existing targets
    final result = await _executor.execute('Target.getTargets', params: {
      'filter': [
        {'type': 'page'},
        {'type': 'iframe'},
      ],
    });

    final targetInfos = result['targetInfos'] as List? ?? [];
    for (final info in targetInfos) {
      final t = info as Map<String, dynamic>;
      final targetId = t['targetId'] as String;
      final type = t['type'] as String? ?? 'page';
      await _attachToTarget(targetId, type: type, url: t['url'] as String?);
    }

    // Set initial focus to first page
    if (_pages.isNotEmpty) {
      _focusedTarget = _pages.first;
    }
  }

  /// Route a CDP command through the correct session.
  /// If [frameId] is provided, commands are routed to that iframe's session.
  Future<Map<String, dynamic>> execute(
    String method, {
    Map<String, dynamic>? params,
    String? frameId,
  }) async {
    final sessionId = _resolveSessionId(frameId);
    return _executor.execute(method, params: params, sessionId: sessionId);
  }

  /// Execute a command in all page sessions (broadcast).
  Future<List<Map<String, dynamic>?>> broadcast(
    String method, {
    Map<String, dynamic>? params,
  }) async {
    final futures = <Future<Map<String, dynamic>?>>[];
    for (final page in _pages) {
      futures.add(_executor.executeOrNull(method,
          params: params, sessionId: page.sessionId));
    }
    return Future.wait(futures);
  }

  // ── Internals ───────────────────────────────────────────────────

  void _onTargetEvent(CdpEvent event) {
    switch (event.eventName) {
      case 'attachedToTarget':
        final t = event.params?['targetInfo'] as Map<String, dynamic>?;
        if (t != null) {
          final targetId = t['targetId'] as String;
          final sessionId = event.params?['sessionId'] as String?;
          final type = t['type'] as String? ?? 'page';
          _addTarget(targetId, type: type, url: t['url'] as String?, sessionId: sessionId);
        }
        break;
      case 'detachedFromTarget':
        final sessionId = event.params?['sessionId'] as String?;
        if (sessionId != null) {
          _removeTargetBySession(sessionId);
        }
        break;
      case 'targetInfoChanged':
        final t = event.params?['targetInfo'] as Map<String, dynamic>?;
        if (t != null) {
          final targetId = t['targetId'] as String;
          final existing = _targets[targetId];
          if (existing != null) {
            existing.url = t['url'] as String? ?? existing.url;
          }
        }
        break;
    }
  }

  Future<void> _attachToTarget(String targetId, {String type = 'page', String? url}) async {
    try {
      final result = await _executor.execute('Target.attachToTarget', params: {
        'targetId': targetId,
        'flatten': true,
      });
      final sessionId = result['sessionId'] as String?;
      _addTarget(targetId, type: type, url: url, sessionId: sessionId);
    } catch (e) {
      print('[cdp] error: \$e');
      // Target may have been closed between discovery and attach — ignore
    }
  }

  void _addTarget(String targetId, {String type = 'page', String? url, String? sessionId}) {
    final target = _CdpTarget(
      targetId: targetId,
      type: type,
      url: url,
      sessionId: sessionId,
    );
    _targets[targetId] = target;
    if (type == 'page') {
      _pages.add(target);
    }
  }

  void _removeTargetBySession(String sessionId) {
    final target = _targets.values.firstWhere(
      (t) => t.sessionId == sessionId,
      orElse: () => _CdpTarget(targetId: '', type: ''),
    );
    if (target.targetId.isNotEmpty) {
      _targets.remove(target.targetId);
      _pages.remove(target);
      if (_focusedTarget?.targetId == target.targetId) {
        _focusedTarget = _pages.isNotEmpty ? _pages.first : null;
      }
    }
  }

  String? _resolveSessionId(String? frameId) {
    if (frameId != null) {
      return _frameToTarget[frameId] ?? _focusedTarget?.sessionId;
    }
    return _focusedTarget?.sessionId;
  }

  Future<void> dispose() async {
    _targets.clear();
    _pages.clear();
    _focusedTarget = null;
    _frameToTarget.clear();
  }
}

class _CdpTarget {

  _CdpTarget({
    required this.targetId,
    required this.type,
    this.url,
    this.sessionId,
  });
  final String targetId;
  String type;
  String? url;
  String? sessionId;
}
