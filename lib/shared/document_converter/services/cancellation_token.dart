/// Lightweight cancellation token for async operations.
library;

import 'dart:async';

class CancellationToken {
  CancellationToken._(this._source);
  final CancellationTokenSource _source;
  bool get isCancelled => _source._isCancelled;
  void throwIfCancelled() {
    if (_source._isCancelled) throw CancellationException();
  }
}

class CancellationTokenSource {

  CancellationTokenSource({Duration? timeout}) {
    if (timeout != null) {
      _timer = Timer(timeout, cancel);
    }
  }
  bool _isCancelled = false;
  Timer? _timer;
  late final CancellationToken token = CancellationToken._(this);

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

class CancellationException implements Exception {
  @override
  String toString() => 'Operation was cancelled';
}

/// Run a list of deferred futures with a concurrency limit.
Future<List<T>> runWithConcurrency<T>(
  List<Future<T> Function()> factories, {
  int concurrency = 3,
  CancellationToken? cancelToken,
}) async {
  final results = <T>[];
  int i = 0;
  while (i < factories.length) {
    cancelToken?.throwIfCancelled();
    final end = (i + concurrency > factories.length) ? factories.length : i + concurrency;
    final batch = factories.sublist(i, end);
    final batchResults = await Future.wait(batch.map((f) => f()));
    results.addAll(batchResults);
    i = end;
  }
  return results;
}
