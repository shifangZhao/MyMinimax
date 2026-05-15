/// Retry + Reask engine.
///
/// The core Instructor pattern: when validation fails, the error context
/// is fed back to the LLM as a tool_result message and the request is
/// retried. This reuses Anthropic's native multi-turn tool_use/tool_result
/// message pattern.
library;

import 'dart:async';
import 'dart:math';

import 'exceptions.dart';
import 'hooks.dart';
import 'maybe.dart';
import 'models.dart';
import 'schema.dart';
import 'validators.dart';

// ── Retry Policy ──

class RetryPolicy {

  const RetryPolicy({
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(seconds: 30),
    this.jitter = true,
  });
  final int maxRetries;
  final Duration initialDelay;
  final double backoffMultiplier;
  final Duration maxDelay;
  final bool jitter;

  static const defaultPolicy = RetryPolicy();

  Duration delayForAttempt(int attempt) {
    final ms = initialDelay.inMilliseconds *
        pow(backoffMultiplier, attempt - 1).toDouble();
    final capped = min(ms.toInt(), maxDelay.inMilliseconds);
    if (jitter) {
      final jittered = capped * (0.5 + Random().nextDouble() * 0.5);
      return Duration(milliseconds: jittered.round());
    }
    return Duration(milliseconds: capped);
  }
}

// ── Reask Engine ──

/// The callback type for executing a single completion attempt.
typedef AttemptFn = Future<ProviderResponse> Function(
  List<Message> messages,
  SchemaDefinition schema,
);

class RetryEngine {

  RetryEngine({this.policy = const RetryPolicy(), this.hooks = const []});
  final RetryPolicy policy;
  final List<InstructorHook> hooks;

  /// Execute with automatic retry + reask on validation failure.
  ///
  /// [attempt] is called for each try. It receives the current message
  /// list (which grows with reask messages after validation failures).
  ///
  /// [validator] is called on each parsed result. If it returns failures,
  /// a reask is appended and the attempt is retried.
  Future<Maybe<T>> executeWithReask<T>({
    required AttemptFn attemptFn,
    required ValidationFn<T> validator,
    required SchemaDefinition schema,
    required List<Message> initialMessages,
    String? systemPrompt,
  }) async {
    var messages = <Message>[...initialMessages];
    int attemptCount = 0;
    List<ValidationError> lastErrors = [];
    String? lastRawResponse;

    while (attemptCount < policy.maxRetries) {
      attemptCount++;

      // Fire pre-completion hook
      await _fireHooks(
        InstructorHookEvent.completionBefore,
        _makeContext(
          attempt: attemptCount,
          schema: schema.name,
          event: InstructorHookEvent.completionBefore,
        ),
      );

      // Execute attempt
      ProviderResponse response;
      try {
        response = await attemptFn(messages, schema);
      } catch (e) {
        print('[retry] error: \$e');
        // Transient error (network etc.) — retry if attempts remain
        if (attemptCount < policy.maxRetries && _isTransientError(e)) {
          await Future.delayed(policy.delayForAttempt(attemptCount));
          continue;
        }
        // Non-transient or exhausted — wrap as Maybe failure
        final err = ValidationError(message: 'Request failed: $e');
        return Maybe<T>.failure(
          err,
          allErrors: [err],
          attemptsUsed: attemptCount,
        );
      }

      // Fire post-completion hook
      await _fireHooks(
        InstructorHookEvent.completionAfter,
        _makeContext(
          attempt: attemptCount,
          schema: schema.name,
          event: InstructorHookEvent.completionAfter,
        ),
      );

      lastRawResponse = response.text;

      // Find the schema tool call
      final toolCall = response.toolCalls.cast<ToolCallBlock?>().firstWhere(
            (tc) => tc?.name == schema.name,
            orElse: () => null,
          );

      if (toolCall == null) {
        // Schema not satisfied — reask
        lastErrors = [
          ValidationError(
            message:
                'Model did not call tool "${schema.name}". Please respond by '
                'calling the "${schema.name}" tool with properly formatted data.',
          ),
        ];
        messages = _buildReaskMessages(
          messages: messages,
          lastResponse: response,
          lastToolCall: null,
          schema: schema,
          errors: lastErrors,
        );
        await _fireHooks(
          InstructorHookEvent.parseError,
          _makeContext(
            attempt: attemptCount,
            schema: schema.name,
            event: InstructorHookEvent.parseError,
            errors: lastErrors,
          ),
        );
        if (attemptCount >= policy.maxRetries) break;
        await Future.delayed(policy.delayForAttempt(attemptCount));
        continue;
      }

      // Parse into T
      T parsed;
      try {
        parsed = schema.fromJson(toolCall.input) as T;
      } catch (e) {
        print('[retry] error: \$e');
        lastErrors = [
          ValidationError(message: 'Parse error: $e'),
        ];
        messages = _buildReaskMessages(
          messages: messages,
          lastResponse: response,
          lastToolCall: toolCall,
          schema: schema,
          errors: lastErrors,
        );
        await _fireHooks(
          InstructorHookEvent.parseError,
          _makeContext(
            attempt: attemptCount,
            schema: schema.name,
            event: InstructorHookEvent.parseError,
            errors: lastErrors,
          ),
        );
        if (attemptCount >= policy.maxRetries) break;
        await Future.delayed(policy.delayForAttempt(attemptCount));
        continue;
      }

      // Validate
      final validationResult = validator(parsed);
      if (validationResult.isValid) {
        return Maybe<T>.success(
          parsed,
          rawResponse: lastRawResponse,
          attempts: attemptCount,
        );
      }

      // Validation failure — reask
      lastErrors = validationResult.errors;
      messages = _buildReaskMessages(
        messages: messages,
        lastResponse: response,
        lastToolCall: toolCall,
        schema: schema,
        errors: lastErrors,
      );
      await _fireHooks(
        InstructorHookEvent.parseError,
        _makeContext(
          attempt: attemptCount,
          schema: schema.name,
          event: InstructorHookEvent.parseError,
          errors: lastErrors,
        ),
      );
      if (attemptCount >= policy.maxRetries) break;
      await Future.delayed(policy.delayForAttempt(attemptCount));
    }

    return Maybe<T>.failure(
      lastErrors.isNotEmpty
          ? lastErrors.first
          : const ValidationError(message: 'Max retries exhausted'),
      allErrors: lastErrors,
      attemptsUsed: attemptCount,
      rawResponse: lastRawResponse,
    );
  }

  // ── Reask message construction ──

  /// Build the retry message list by appending the failed tool_use
  /// (as assistant) + error tool_result (as user). This is the
  /// exact same Anthropic multi-turn pattern used in ChatRepository.
  List<Message> _buildReaskMessages({
    required List<Message> messages,
    required ProviderResponse lastResponse,
    required ToolCallBlock? lastToolCall,
    required SchemaDefinition schema,
    required List<ValidationError> errors,
  }) {
    final updated = <Message>[...messages];

    // Append the failed assistant tool_use
    final toolId = lastToolCall?.id ?? 'tool_${schema.name}';
    final toolInput =
        lastToolCall?.input ?? const <String, dynamic>{};
    updated.add(Message.assistantToolUse(
      toolName: schema.name,
      toolUseId: toolId,
      input: Map<String, dynamic>.from(toolInput),
    ));

    // Append the error feedback as tool_result
    final errorFeedback = errors.map((e) => '- ${e.toString()}').join('\n');
    updated.add(Message.toolResult(
      toolUseId: toolId,
      content: 'Validation failed. Correct the following errors and try '
          'again. Return valid JSON matching the ${schema.name} schema.\n\n'
          '$errorFeedback',
    ));

    return updated;
  }

  // ── Helpers ──

  bool _isTransientError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('connection') ||
        msg.contains('timeout') ||
        msg.contains('socket') ||
        msg.contains('network');
  }

  Future<void> _fireHooks(
    InstructorHookEvent event,
    InstructorHookContext ctx,
  ) async {
    for (final hook in hooks) {
      try {
        await hook(ctx);
      } catch (_) {
        // Individual hook failure must not block the pipeline
      }
    }
  }

  InstructorHookContext _makeContext({
    required int attempt,
    required String schema,
    required InstructorHookEvent event,
    List<ValidationError>? errors,
  }) =>
      InstructorHookContext(
        event: event,
        schemaName: schema,
        attemptNumber: attempt,
        errors: errors,
      );
}
