import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:meta/meta.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'cdp_message.dart';

/// Callback for unsolicited CDP events received from the browser.
typedef CdpEventCallback = void Function(CdpEvent event);

/// Callback when the connection state changes.
typedef CdpConnectionStateCallback = void Function(CdpConnectionState state);

enum CdpConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  closing,
}

/// Manages a CDP WebSocket connection to a Chromium browser.
///
/// Features:
/// - Automatic reconnection with exponential backoff (1s → 30s max)
/// - Heartbeat keep-alive every 5 seconds
/// - Event routing: subscribe to specific CDP domains/events
/// - Pending request tracking with response promise resolution
/// - Timeout handling for unresponsive connections
class CdpConnection {

  CdpConnection({
    required this.wsUrl,
    this.reconnectBase = const Duration(seconds: 1),
    this.reconnectMax = const Duration(seconds: 30),
    this.heartbeatInterval = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 60),
    this.maxReconnectAttempts,
    this.onPermanentFailure,
    this.onEvent,
    this.onStateChange,
    this.onLog,
  });
  final String wsUrl;
  final Duration reconnectBase;
  final Duration reconnectMax;
  final Duration heartbeatInterval;
  final Duration requestTimeout;
  final CdpEventCallback? onEvent;
  final CdpConnectionStateCallback? onStateChange;
  final void Function(String log)? onLog;

  /// Max reconnect attempts before giving up permanently.
  /// null (default) = retry forever.
  final int? maxReconnectAttempts;

  /// Called when reconnect attempts are exhausted.
  /// The caller should switch to a fallback backend (JS injection).
  final void Function()? onPermanentFailure;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  int _nextId = 1;
  CdpConnectionState _state = CdpConnectionState.disconnected;
  int _reconnectAttempts = 0;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  // Pending requests awaiting response
  final Map<int, Completer<CdpResponse>> _pendingRequests = {};

  // Per-domain event subscribers
  final Map<String, List<CdpEventCallback>> _eventSubscribers = {};

  // ------------------------------------------------------------------
  // Public API
  // ------------------------------------------------------------------

  CdpConnectionState get state => _state;
  bool get isConnected => _state == CdpConnectionState.connected;

  /// Open the WebSocket and start listening.
  Future<void> connect() async {
    if (_state == CdpConnectionState.connected ||
        _state == CdpConnectionState.connecting) {
      return;
    }
    _setState(CdpConnectionState.connecting);
    await _openChannel();
    _setState(CdpConnectionState.connected);
    _reconnectAttempts = 0;
    testSentMessages.clear();
    _startHeartbeat();
  }

  /// Send a CDP command and wait for its response.
  ///
  /// Commands with a [sessionId] are routed to the specified CDP session
  /// (e.g., a specific iframe/target). Returns the parsed response.
  Future<CdpResponse> send(
    String method, {
    Map<String, dynamic>? params,
    String? sessionId,
    Duration? timeout,
  }) async {
    final id = _nextId++;
    final request = CdpRequest(
      id: id,
      method: method,
      params: params,
      sessionId: sessionId,
    );

    final completer = Completer<CdpResponse>();
    _pendingRequests[id] = completer;

    final raw = jsonEncode(request.toJson());
    testSentMessages.add(raw);
    try {
      _sendRaw(raw);
    } catch (e) {
      _pendingRequests.remove(id);
      if (!completer.isCompleted) completer.completeError(e);
      rethrow;
    }

    try {
      return await completer.future
          .timeout(timeout ?? requestTimeout, onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException(
            'CDP command timed out: $method (${timeout ?? requestTimeout})');
      });
    } catch (e) {
      _pendingRequests.remove(id);
      rethrow;
    }
  }

  /// Send a CDP command and discard the response (fire-and-forget).
  void sendAsync(
    String method, {
    Map<String, dynamic>? params,
    String? sessionId,
  }) {
    final id = _nextId++;
    final request = CdpRequest(
      id: id,
      method: method,
      params: params,
      sessionId: sessionId,
    );
    _pendingRequests[id] = Completer<CdpResponse>(); // Track but don't await
    final raw = jsonEncode(request.toJson());
    testSentMessages.add(raw);
    _sendRaw(raw);
  }

  /// Subscribe to all events from a specific CDP domain (e.g., "Page", "Network").
  void on(String domain, CdpEventCallback callback) {
    _eventSubscribers.putIfAbsent(domain, () => []).add(callback);
  }

  /// Cancel a domain subscription.
  void off(String domain, CdpEventCallback callback) {
    _eventSubscribers[domain]?.remove(callback);
  }

  /// Graceful close.
  Future<void> close() async {
    _setState(CdpConnectionState.closing);
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer = null;

    // Fail all pending requests
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(
            const CdpConnectionException('Connection closed'));
      }
    }
    _pendingRequests.clear();

    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _subscription = null;
    _setState(CdpConnectionState.disconnected);
  }

  // ------------------------------------------------------------------
  // Testing API — injects CDP messages without a real WebSocket.
  // ------------------------------------------------------------------

  /// Enter connected state without a real WebSocket handshake.
  @visibleForTesting
  void connectForTesting() {
    _setState(CdpConnectionState.connected);
    _reconnectAttempts = 0;
  }

  /// Feed a CDP response as if it arrived over the wire.
  @visibleForTesting
  void injectResponse(CdpResponse response) {
    final completer = _pendingRequests.remove(response.id);
    if (completer != null && !completer.isCompleted) {
      completer.complete(response);
    }
  }

  /// Feed a CDP event as if it arrived over the wire.
  @visibleForTesting
  void injectEvent(CdpEvent event) {
    onEvent?.call(event);
    final domain = event.domain;
    for (final sub in _eventSubscribers[domain] ?? <CdpEventCallback>[]) {
      sub(event);
    }
    for (final sub in _eventSubscribers['*'] ?? <CdpEventCallback>[]) {
      sub(event);
    }
  }

  /// Raw JSON strings sent via [send] / [sendAsync]. Cleared by [connectForTesting].
  @visibleForTesting
  final List<String> testSentMessages = [];

  // ------------------------------------------------------------------
  // Internals
  // ------------------------------------------------------------------

  void _setState(CdpConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    onStateChange?.call(newState);
  }

  /// Factory overridable for testing — plugs in a mock WebSocket.
  @visibleForTesting
  Future<WebSocketChannel> createChannel(String url) async {
    final ch = WebSocketChannel.connect(Uri.parse(url));
    await ch.ready;
    return ch;
  }

  Future<void> _openChannel() async {
    _log('CDP connecting to $wsUrl...');
    _channel = await createChannel(wsUrl);
    _log('CDP WebSocket connected');
    _subscription = _channel!.stream.listen(
      _onMessage,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  void _sendRaw(String data) {
    // If no channel (testing mode), message was already captured in testSentMessages
    _channel?.sink.add(data);
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;
    final msg = classifyCdpMessage(data);

    if (msg.isResponse) {
      final response = msg.asResponse!;
      final completer = _pendingRequests.remove(response.id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(response);
      }
    } else if (msg.isEvent) {
      final event = msg.asEvent!;
      // Route to onEvent callback
      onEvent?.call(event);
      // Route to domain subscribers
      final domain = event.domain;
      for (final sub in _eventSubscribers[domain] ?? <CdpEventCallback>[]) {
        sub(event);
      }
      // Also route to wildcard subscribers
      for (final sub in _eventSubscribers['*'] ?? <CdpEventCallback>[]) {
        sub(event);
      }
    }
    // Request messages from browser are unexpected in CDP — ignore
  }

  void _onError(dynamic error) {
    _log('CDP WebSocket error: $error');
    _reconnect();
  }

  void _onDone() {
    _log('CDP WebSocket closed');
    if (_state != CdpConnectionState.closing) {
      _reconnect();
    }
  }

  void _reconnect() {
    if (_state == CdpConnectionState.closing ||
        _state == CdpConnectionState.reconnecting) {
      return;
    }

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _subscription?.cancel();
    _channel = null;
    _subscription = null;

    // Fail all pending requests so they don't hang forever
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(
            const CdpConnectionException('Connection lost during request'));
      }
    }
    _pendingRequests.clear();

    // Give up if max attempts exceeded
    if (maxReconnectAttempts != null &&
        _reconnectAttempts >= maxReconnectAttempts!) {
      _log('CDP reconnect exhausted ($_reconnectAttempts attempts). Giving up.');
      _setState(CdpConnectionState.disconnected);
      onPermanentFailure?.call();
      return;
    }

    _setState(CdpConnectionState.reconnecting);

    final delay = Duration(
      milliseconds: min(
        (reconnectBase.inMilliseconds * pow(2, _reconnectAttempts)).round(),
        reconnectMax.inMilliseconds,
      ),
    );
    _reconnectAttempts++;
    _log('CDP reconnect #$_reconnectAttempts in ${delay.inMilliseconds}ms...');
    _reconnectTimer = Timer(delay, () async {
      try {
        await _openChannel();
        _setState(CdpConnectionState.connected);
        _reconnectAttempts = 0;
        _startHeartbeat();
      } catch (e) {
        print('[cdp] error: \$e');
        _log('CDP reconnect failed: $e');
        _reconnect();
      }
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      try {
        send('Browser.getVersion')
            .timeout(const Duration(seconds: 3))
            .catchError((_) => _reconnect());
      } catch (_) {
        _reconnect();
      }
    });
  }

  void _log(String msg) {
    onLog?.call('[CdpConnection] $msg');
  }
}

class CdpConnectionException implements Exception {
  const CdpConnectionException(this.message);
  final String message;
  @override
  String toString() => 'CdpConnectionException: $message';
}
