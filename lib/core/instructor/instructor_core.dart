/// Instructor — the main entry point for structured LLM output.
///
/// ```dart
/// final instructor = Instructor.fromClient(client);
/// final maybe = await instructor.extract<UserProfile>(
///   schema: userSchema,
///   messages: [Message.user('John is 34 years old')],
/// );
/// ```
library;

import 'dart:async';

import '../api/minimax_client.dart';
import 'hooks.dart';
import 'maybe.dart';
import 'models.dart';
import 'partial.dart';
import 'provider.dart';
import 'retry_engine.dart';
import 'schema.dart';
import 'validators.dart';

class Instructor {

  Instructor._({
    required LlmProvider provider,
    RetryPolicy? retryPolicy,
    List<InstructorHook>? hooks,
  })  : _provider = provider,
        _retryEngine = RetryEngine(
          policy: retryPolicy ?? const RetryPolicy(),
          hooks: hooks ?? const [],
        );

  // ── Factory ──

  /// Create an Instructor from an existing [MinimaxClient].
  ///
  /// ```dart
  /// final instructor = Instructor.fromClient(myClient,
  ///   retryPolicy: RetryPolicy(maxRetries: 2),
  /// );
  /// ```
  factory Instructor.fromClient(
    MinimaxClient client, {
    RetryPolicy? retryPolicy,
    List<InstructorHook>? hooks,
  }) {
    return Instructor._(
      provider: MinimaxProvider(client),
      retryPolicy: retryPolicy,
      hooks: hooks,
    );
  }
  final LlmProvider _provider;
  final RetryEngine _retryEngine;

  // ── Structured Extraction ──

  /// Extract structured data from a prompt.
  ///
  /// Returns a [Maybe<T>] — never throws. The consumer decides how to
  /// handle failure.
  ///
  /// On validation failure the error context is automatically fed back
  /// to the LLM (reask) and the request is retried up to [maxRetries]
  /// times.
  Future<Maybe<T>> extract<T>({
    required SchemaDefinition schema,
    required List<Message> messages,
    dynamic systemPrompt,
    int? maxRetries,
    ValidationFn<T>? validator,
  }) async {
    final policy = maxRetries != null
        ? RetryPolicy(maxRetries: maxRetries)
        : _retryEngine.policy;

    final engine = RetryEngine(policy: policy, hooks: _retryEngine.hooks);

    return engine.executeWithReask<T>(
      attemptFn: (msgs, sch) => _provider.complete(
        CompletionRequest(
          messages: msgs,
          systemPrompt: systemPrompt,
          thinkingBudgetTokens: 0, // No thinking needed for extraction
        ),
        sch,
      ),
      validator: validator ?? _noopValidator,
      schema: schema,
      initialMessages: messages,
      systemPrompt: systemPrompt,
    );
  }

  /// Extract without retry/reask. Single call, returns [ProviderResponse].
  Future<ProviderResponse> complete({
    required SchemaDefinition schema,
    required List<Message> messages,
    dynamic systemPrompt,  // String or List<Map> (with cache_control)
  }) {
    return _provider.complete(
      CompletionRequest(
        messages: messages,
        systemPrompt: systemPrompt,
        thinkingBudgetTokens: 0,
      ),
      schema,
    );
  }

  // ── Streaming ──

  /// Stream a partial structured object as the LLM generates.
  ///
  /// Each yield carries the accumulated fields so far. Null fields
  /// haven't been extracted yet.
  Stream<Partial<dynamic>> streamPartial({
    required SchemaDefinition schema,
    required List<Message> messages,
    String? systemPrompt,
  }) async* {
    final accumulator = PartialAccumulator();

    await for (final event in _provider.streamComplete(
      CompletionRequest(
        messages: messages,
        systemPrompt: systemPrompt,
        thinkingBudgetTokens: 0,
      ),
      schema,
    )) {
      switch (event.type) {
        case StreamEventType.toolCallDelta:
          final updated = accumulator.feed(event.partialJson ?? '');
          if (updated != null) yield updated;

        case StreamEventType.done:
        case StreamEventType.error:
          break;

        default:
          break;
      }
    }
  }

  // ── Hooks ──

  static ValidationResult _noopValidator<T>(T _) => ValidationResult.success();
}
