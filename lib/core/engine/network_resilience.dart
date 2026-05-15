import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkStatus { online, offline }

class NetworkResilience {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  final _networkStatusController = StreamController<NetworkStatus>.broadcast();
  Stream<NetworkStatus> get networkStatusStream => _networkStatusController.stream;

  NetworkStatus _currentStatus = NetworkStatus.online;
  NetworkStatus get currentStatus => _currentStatus;

  bool _isRetrying = false;
  Function? _pendingRetry;

  void init() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen(_handleConnectivityChange);
    _checkInitialConnectivity();
  }

  Future<void> _checkInitialConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    _updateStatus(results);
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    _updateStatus(results);

    if (_currentStatus == NetworkStatus.online && _pendingRetry != null) {
      _retryPendingRequest();
    }
  }

  void _updateStatus(List<ConnectivityResult> results) {
    final hasConnection = results.any((r) => r != ConnectivityResult.none);
    _currentStatus = hasConnection ? NetworkStatus.online : NetworkStatus.offline;
    _networkStatusController.add(_currentStatus);
  }

  void setPendingRetry(Function retryFn) {
    _pendingRetry = retryFn;
  }

  Future<void> _retryPendingRequest() async {
    if (_isRetrying || _pendingRetry == null) return;
    if (_currentStatus != NetworkStatus.online) return;

    _isRetrying = true;
    try {
      await Future.delayed(const Duration(seconds: 1));
      final retry = _pendingRetry;
      // ignore: avoid_dynamic_calls
      if (retry != null) retry();
    } finally {
      _isRetrying = false;
      _pendingRetry = null;
    }
  }

  void clearPendingRetry() {
    _pendingRetry = null;
  }

  bool get isOnline => _currentStatus == NetworkStatus.online;

  void dispose() {
    _connectivitySub?.cancel();
    _networkStatusController.close();
  }
}