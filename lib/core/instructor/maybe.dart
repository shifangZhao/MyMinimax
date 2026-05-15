/// A result type that either contains a value or an error.
///
/// [extract] returns a [Maybe] so callers handle both success and
/// failure without try/catch. The failure side carries structured
/// diagnostics.
library;

import 'exceptions.dart';

class Maybe<T> {

  const Maybe._({
    T? value,
    ValidationError? error,
    List<ValidationError> allErrors = const [],
    int attemptsUsed = 1,
    String? rawResponse,
  })  : _value = value,
        _error = error,
        _allErrors = allErrors,
        _attemptsUsed = attemptsUsed,
        _rawResponse = rawResponse;

  factory Maybe.success(T value, {String? rawResponse, int attempts = 1}) =>
      Maybe._(
        value: value,
        rawResponse: rawResponse,
        attemptsUsed: attempts,
      );

  factory Maybe.failure(
    ValidationError error, {
    List<ValidationError> allErrors = const [],
    int attemptsUsed = 1,
    String? rawResponse,
  }) =>
      Maybe._(
        error: error,
        allErrors: allErrors,
        attemptsUsed: attemptsUsed,
        rawResponse: rawResponse,
      );
  final T? _value;
  final ValidationError? _error;
  final List<ValidationError> _allErrors;
  final int _attemptsUsed;
  final String? _rawResponse;

  bool get isSuccess => _value != null;
  bool get isFailure => _error != null;

  T get value {
    if (_value != null) return _value as T;
    throw StateError('Maybe is failure, not success. Check isSuccess first.');
  }

  ValidationError get error {
    if (_error != null) return _error;
    throw StateError('Maybe is success, not failure. Check isFailure first.');
  }

  List<ValidationError> get allErrors => List.unmodifiable(_allErrors);
  int get attemptsUsed => _attemptsUsed;
  String? get rawResponse => _rawResponse;

  /// Pattern match.
  R when<R>({
    required R Function(T value) success,
    required R Function(ValidationError error, List<ValidationError> allErrors)
        failure,
  }) {
    if (isSuccess) return success(_value as T);
    return failure(_error!, _allErrors);
  }

  /// Map the success value. Passes through on failure.
  Maybe<R> map<R>(R Function(T) transform) {
    if (isSuccess) {
      return Maybe<R>.success(
        transform(_value as T),
        rawResponse: _rawResponse,
        attempts: _attemptsUsed,
      );
    }
    return Maybe<R>.failure(
      _error!,
      allErrors: _allErrors,
      attemptsUsed: _attemptsUsed,
      rawResponse: _rawResponse,
    );
  }

  /// Get the value or a fallback.
  T orElse(T fallback) => isSuccess ? _value as T : fallback;

  @override
  String toString() {
    if (isSuccess) return 'Maybe.success($_value)';
    return 'Maybe.failure(${_error?.message})';
  }
}
