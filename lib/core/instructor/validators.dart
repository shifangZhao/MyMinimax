/// Validation utilities for Instructor structured extraction.
library;

import 'exceptions.dart';

/// Result of validating a parsed structured output.
class ValidationResult {

  const ValidationResult._({required this.isValid, required this.errors});

  factory ValidationResult.success() =>
      const ValidationResult._(isValid: true, errors: []);

  factory ValidationResult.failure(List<ValidationError> errors) =>
      ValidationResult._(isValid: false, errors: errors);

  factory ValidationResult.single(String message, {String? field}) =>
      ValidationResult._(
        isValid: false,
        errors: [ValidationError(message: message, field: field)],
      );

  /// Merge multiple results. Fails if any fail.
  factory ValidationResult.merge(List<ValidationResult> results) {
    final allErrors = <ValidationError>[];
    for (final r in results) {
      allErrors.addAll(r.errors);
    }
    return ValidationResult._(
      isValid: allErrors.isEmpty,
      errors: allErrors,
    );
  }
  final bool isValid;
  final List<ValidationError> errors;
}

/// A validation function receives the parsed value and returns
/// a [ValidationResult].
typedef ValidationFn<T> = ValidationResult Function(T value);

/// Built-in validators.
class Validators {
  Validators._();

  /// Value must not be null.
  static ValidationFn<T> required<T>({String? field}) => (T value) {
        if (value == null) {
          return ValidationResult.single('Value is required', field: field);
        }
        if (value is String && value.isEmpty) {
          return ValidationResult.single('String must not be empty', field: field);
        }
        return ValidationResult.success();
      };

  /// Number must be >= [min].
  static ValidationFn<num> min(num min, {String? field}) => (num value) {
        if (value < min) {
          return ValidationResult.single(
            'Must be at least $min, got $value',
            field: field,
          );
        }
        return ValidationResult.success();
      };

  /// Number must be <= [max].
  static ValidationFn<num> max(num max, {String? field}) => (num value) {
        if (value > max) {
          return ValidationResult.single(
            'Must be at most $max, got $value',
            field: field,
          );
        }
        return ValidationResult.success();
      };

  /// String length must be >= [min].
  static ValidationFn<String> minLength(int min, {String? field}) =>
      (String value) {
        if (value.length < min) {
          return ValidationResult.single(
            'Must be at least $min characters, got ${value.length}',
            field: field,
          );
        }
        return ValidationResult.success();
      };

  /// Value must be one of [allowed].
  static ValidationFn<T> oneOf<T>(List<T> allowed, {String? field}) =>
      (T value) {
        if (!allowed.contains(value)) {
          return ValidationResult.single(
            'Must be one of $allowed, got $value',
            field: field,
          );
        }
        return ValidationResult.success();
      };
}
