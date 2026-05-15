/// Lightweight lifecycle hooks for Instructor operations.
///
/// These are separate from the existing [HookPipeline] which handles
/// tool-execution events (beforeToolUse, afterToolUse, etc.).
/// Instructor hooks observe the LLM call lifecycle (before/after
/// completion, parse errors).
library;

import 'package:flutter/foundation.dart';

import 'exceptions.dart';

/// Hook event types.
enum InstructorHookEvent {
  completionBefore,
  completionAfter,
  parseError,
}

/// Context passed to each hook invocation.
class InstructorHookContext {

  const InstructorHookContext({
    required this.event,
    this.schemaName,
    this.attemptNumber = 1,
    this.errors,
    this.custom = const {},
  });
  final InstructorHookEvent event;
  final String? schemaName;
  final int attemptNumber;
  final List<ValidationError>? errors;
  final Map<String, dynamic> custom;

  /// Total errors from the last validation or parse attempt.
  int get errorCount => errors?.length ?? 0;
}

/// Hook handler function type.
typedef InstructorHook = Future<void> Function(InstructorHookContext context);

/// Built-in hooks for common needs.
class BuiltInHooks {
  BuiltInHooks._();

  /// Logs each completion attempt to debugPrint.
  static InstructorHook debugLog() => (ctx) async {
        final label = ctx.schemaName ?? 'unknown';
        final tag =
            ctx.event == InstructorHookEvent.completionBefore ? 'REQ' : 'RES';
        if (ctx.event == InstructorHookEvent.parseError) {
          final errs = ctx.errors?.map((e) => e.toString()).join('; ') ?? '';
          debugPrint(
              '[Instructor] PARSE_ERROR [$label] #${ctx.attemptNumber}: $errs');
        } else {
          debugPrint(
              '[Instructor] $tag [$label] attempt #${ctx.attemptNumber}');
        }
      };
}
