/// Instructor — Structured output for LLMs in Dart.
///
/// Define your data model → Instructor handles schema generation,
/// LLM calling, parsing, validation, and retry with reask.
///
/// ```dart
/// final instructor = Instructor.fromClient(client);
/// final maybe = await instructor.extract<UserProfile>(
///   schema: userSchema,
///   messages: [Message.user('John is 34 years old')],
/// );
/// ```
library;

export 'exceptions.dart';
export 'hooks.dart';
export 'instructor_core.dart';
export 'maybe.dart';
export 'models.dart';
export 'partial.dart';
export 'provider.dart';
export 'retry_engine.dart';
export 'schema.dart';
export 'validators.dart';
