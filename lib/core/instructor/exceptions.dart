/// Error types for the Instructor structured extraction system.
library;

/// A single validation problem — one field or the whole model.
class ValidationError {

  const ValidationError({
    required this.message,
    this.field,
    this.code,
    this.rejectedValue,
  });
  final String message;
  final String? field;
  final String? code;
  final dynamic rejectedValue;

  @override
  String toString() {
    final loc = field ?? 'root';
    return '$loc: $message';
  }
}

/// Raised when all retry attempts (including reasks) are exhausted.
class MaxRetriesExceededError extends Error {

  MaxRetriesExceededError({
    required this.attemptsUsed,
    required this.maxRetries,
    required this.lastErrors,
  });
  final int attemptsUsed;
  final int maxRetries;
  final List<ValidationError> lastErrors;

  @override
  String toString() =>
      'MaxRetriesExceeded: $attemptsUsed/$maxRetries attempts. '
      'Last errors: ${lastErrors.map((e) => e.toString()).join("; ")}';
}

/// Failed to find the expected tool_use block in the LLM response.
class SchemaNotSatisfiedError extends Error {

  SchemaNotSatisfiedError(this.schemaName, {this.rawResponse});
  final String schemaName;
  final String? rawResponse;

  @override
  String toString() =>
      'SchemaNotSatisfied: LLM did not call tool "$schemaName". '
      'Check that the schema name is a valid identifier.';
}
