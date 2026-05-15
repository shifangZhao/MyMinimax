import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/core/instructor/instructor.dart';

// ============================================================
// Test helpers
// ============================================================

Map<String, dynamic> _json(String raw) => jsonDecode(raw) as Map<String, dynamic>;

SchemaDefinition _userSchema() => SchemaDefinition(
      name: 'extract_user',
      description: 'Extract user profile from text',
      inputSchema: {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'age': {'type': 'integer'},
        },
        'required': ['name', 'age'],
      },
      fromJson: (json) => _User(json['name'] as String, json['age'] as int),
    );

class _User {
  const _User(this.name, this.age);
  final String name;
  final int age;

  @override
  bool operator ==(Object other) =>
      other is _User && other.name == name && other.age == age;

  @override
  String toString() => '_User($name, $age)';
}

// ============================================================
// 1. SchemaDefinition
// ============================================================

void main() {
  group('SchemaDefinition', () {
    test('toAnthropicTool produces correct format', () {
      final schema = _userSchema();
      final tool = schema.toAnthropicTool();

      expect(tool['name'], 'extract_user');
      expect(tool['description'], isA<String>());
      expect(tool['input_schema'], isA<Map>());
      expect(tool['input_schema']['type'], 'object');
    });

    test('forceToolChoice produces correct map', () {
      final schema = _userSchema();
      final choice = schema.forceToolChoice;

      expect(choice['type'], 'tool');
      expect(choice['name'], 'extract_user');
    });

    test('requiredFields extracts from inputSchema', () {
      final schema = _userSchema();
      expect(schema.requiredFields, ['name', 'age']);
    });

    test('requiredFields returns empty list when absent', () {
      final schema = SchemaDefinition(
        name: 'test',
        description: '',
        inputSchema: {'type': 'object', 'properties': {}},
        fromJson: (_) => null,
      );
      expect(schema.requiredFields, isEmpty);
    });

    test('properties extracts from inputSchema', () {
      final schema = _userSchema();
      final props = schema.properties;
      expect(props.containsKey('name'), true);
      expect(props.containsKey('age'), true);
    });

    test('properties returns empty map when absent', () {
      final schema = SchemaDefinition(
        name: 'test',
        description: '',
        inputSchema: {'type': 'object'},
        fromJson: (_) => null,
      );
      expect(schema.properties, isEmpty);
    });

    test('parseJson decodes and passes through fromJson', () {
      final schema = _userSchema();
      final user = schema.parseJson('{"name":"Alice","age":30}') as _User;
      expect(user.name, 'Alice');
      expect(user.age, 30);
    });

    test('tryParseJson returns null on invalid JSON', () {
      final schema = _userSchema();
      expect(schema.tryParseJson('not json'), isNull);
    });

    test('tryParseJson returns value on valid JSON', () {
      final schema = _userSchema();
      final user = schema.tryParseJson('{"name":"Bob","age":25}') as _User;
      expect(user.name, 'Bob');
    });
  });

  // ============================================================
  // 2. Maybe<T>
  // ============================================================

  group('Maybe<T>', () {
    test('success stores value and sets isSuccess', () {
      final maybe = Maybe<String>.success('hello', attempts: 2);
      expect(maybe.isSuccess, true);
      expect(maybe.isFailure, false);
      expect(maybe.value, 'hello');
      expect(maybe.attemptsUsed, 2);
    });

    test('failure stores error and sets isFailure', () {
      const err = ValidationError(message: 'bad');
      final maybe = Maybe<String>.failure(err, attemptsUsed: 3);
      expect(maybe.isFailure, true);
      expect(maybe.isSuccess, false);
      expect(maybe.error.message, 'bad');
      expect(maybe.attemptsUsed, 3);
    });

    test('value throws StateError on failure', () {
      final maybe = Maybe<String>.failure(const ValidationError(message: 'x'));
      expect(() => maybe.value, throwsStateError);
    });

    test('error throws StateError on success', () {
      final maybe = Maybe<String>.success('ok');
      expect(() => maybe.error, throwsStateError);
    });

    test('when dispatches to success branch', () {
      final maybe = Maybe<int>.success(42);
      final result = maybe.when(
        success: (v) => 'got $v',
        failure: (e, _) => 'fail: ${e.message}',
      );
      expect(result, 'got 42');
    });

    test('when dispatches to failure branch', () {
      final maybe = Maybe<int>.failure(const ValidationError(message: 'nope'));
      final result = maybe.when(
        success: (v) => 'got $v',
        failure: (e, _) => 'fail: ${e.message}',
      );
      expect(result, 'fail: nope');
    });

    test('map transforms success value', () {
      final maybe = Maybe<int>.success(10);
      final mapped = maybe.map((v) => v * 2);
      expect(mapped.isSuccess, true);
      expect(mapped.value, 20);
    });

    test('map passes through failure', () {
      final maybe = Maybe<int>.failure(const ValidationError(message: 'x'));
      final mapped = maybe.map((v) => v * 2);
      expect(mapped.isFailure, true);
    });

    test('map preserves attemptsUsed and rawResponse', () {
      final maybe = Maybe<int>.success(1, rawResponse: 'raw', attempts: 5);
      final mapped = maybe.map((v) => v + 1);
      expect(mapped.attemptsUsed, 5);
      expect(mapped.rawResponse, 'raw');
    });

    test('orElse returns value on success', () {
      final maybe = Maybe<int>.success(99);
      expect(maybe.orElse(0), 99);
    });

    test('orElse returns fallback on failure', () {
      final maybe = Maybe<int>.failure(const ValidationError(message: 'x'));
      expect(maybe.orElse(42), 42);
    });

    test('allErrors returns unmodifiable list', () {
      final errors = [const ValidationError(message: 'a')];
      final maybe = Maybe<String>.failure(
        const ValidationError(message: 'a'),
        allErrors: errors,
      );
      expect(maybe.allErrors.length, 1);
      expect(() => maybe.allErrors.add(const ValidationError(message: 'b')),
          throwsUnsupportedError);
    });
  });

  // ============================================================
  // 3. ValidationResult
  // ============================================================

  group('ValidationResult', () {
    test('success has no errors', () {
      final r = ValidationResult.success();
      expect(r.isValid, true);
      expect(r.errors, isEmpty);
    });

    test('failure carries errors', () {
      final errors = [const ValidationError(message: 'e1')];
      final r = ValidationResult.failure(errors);
      expect(r.isValid, false);
      expect(r.errors, errors);
    });

    test('single creates one error with field', () {
      final r = ValidationResult.single('bad', field: 'name');
      expect(r.isValid, false);
      expect(r.errors.length, 1);
      expect(r.errors.first.field, 'name');
    });

    test('merge combines multiple results', () {
      final results = [
        ValidationResult.success(),
        ValidationResult.single('error 1'),
        ValidationResult.single('error 2'),
        ValidationResult.success(),
      ];
      final merged = ValidationResult.merge(results);
      expect(merged.isValid, false);
      expect(merged.errors.length, 2);
    });

    test('merge all success returns valid', () {
      final merged = ValidationResult.merge([
        ValidationResult.success(),
        ValidationResult.success(),
      ]);
      expect(merged.isValid, true);
    });
  });

  // ============================================================
  // 4. Built-in Validators
  // ============================================================

  group('Validators.required', () {
    final required = Validators.required<String>();

    test('passes non-null non-empty string', () {
      expect(required('hello').isValid, true);
    });

    test('fails empty string', () {
      expect(required('').isValid, false);
    });
  });

  group('Validators.min', () {
    final min5 = Validators.min(5);

    test('passes when >= min', () {
      expect(min5(5).isValid, true);
      expect(min5(10).isValid, true);
    });

    test('fails when < min', () {
      expect(min5(3).isValid, false);
    });
  });

  group('Validators.max', () {
    final max10 = Validators.max(10);

    test('passes when <= max', () {
      expect(max10(10).isValid, true);
      expect(max10(5).isValid, true);
    });

    test('fails when > max', () {
      expect(max10(15).isValid, false);
    });
  });

  group('Validators.oneOf', () {
    final colors = Validators.oneOf<String>(['red', 'green', 'blue']);

    test('passes when in allowed', () {
      expect(colors('red').isValid, true);
    });

    test('fails when not in allowed', () {
      expect(colors('yellow').isValid, false);
    });
  });

  group('Validators.minLength', () {
    final min3 = Validators.minLength(3);

    test('passes long enough', () {
      expect(min3('abc').isValid, true);
    });

    test('fails too short', () {
      expect(min3('ab').isValid, false);
    });
  });

  // ============================================================
  // 5. RetryPolicy
  // ============================================================

  group('RetryPolicy', () {
    test('delayForAttempt grows exponentially', () {
      const policy = RetryPolicy(
        initialDelay: Duration(seconds: 1),
        backoffMultiplier: 2.0,
        maxDelay: Duration(seconds: 30),
        jitter: false,
      );

      expect(policy.delayForAttempt(1), const Duration(seconds: 1));
      expect(policy.delayForAttempt(2), const Duration(seconds: 2));
      expect(policy.delayForAttempt(3), const Duration(seconds: 4));
      expect(policy.delayForAttempt(4), const Duration(seconds: 8));
    });

    test('delayForAttempt capped at maxDelay', () {
      const policy = RetryPolicy(
        initialDelay: Duration(seconds: 1),
        backoffMultiplier: 10.0,
        maxDelay: Duration(seconds: 5),
        jitter: false,
      );

      // attempt 4 would be 1000 * 10^3 = 1,000,000 ms → capped at 5000
      final delay = policy.delayForAttempt(4);
      expect(delay.inMilliseconds, lessThanOrEqualTo(5000));
    });

    test('jitter adds randomness', () {
      const policy = RetryPolicy(
        initialDelay: Duration(seconds: 1),
        jitter: true,
      );

      // Run 50 times to check jitter varies
      final delays = List.generate(50, (_) => policy.delayForAttempt(1));
      final allSame = delays.every((d) => d == delays.first);
      expect(allSame, false, reason: 'Jitter should produce varied delays');
    });
  });

  // ============================================================
  // 6. PartialAccumulator (streaming JSON repair)
  // ============================================================

  group('PartialAccumulator', () {
    test('feed builds partial from complete JSON', () {
      final acc = PartialAccumulator();
      final result = acc.feed('{"name":"Alice","age":30}');
      expect(result, isNotNull);
      expect(result!.get<String>('name'), 'Alice');
      expect(result.get<int>('age'), 30);
    });

    test('feed returns null on incomplete unrepairable JSON', () {
      final acc = PartialAccumulator();
      // Incomplete: key without value
      final result = acc.feed('{"name":');
      expect(result, isNull);
    });

    test('feed repairs closing brace (was the fixed-suffix bug)', () {
      final acc = PartialAccumulator();
      final result = acc.feed('{"name":"Alice"');
      expect(result, isNotNull);
      expect(result!.get<String>('name'), 'Alice');
    });

    test('feed repairs string closure', () {
      final acc = PartialAccumulator();
      final result = acc.feed('{"name":"Ali');
      expect(result, isNotNull);
      expect(result!.get<String>('name'), 'Ali');
    });

    test('feed repairs trailing comma', () {
      final acc = PartialAccumulator();
      final result = acc.feed('{"name":"Alice",');
      expect(result, isNotNull);
      expect(result!.get<String>('name'), 'Alice');
    });

    test('feed repairs nested objects', () {
      final acc = PartialAccumulator();
      final result = acc.feed('{"user":{"name":"Alice"');
      // Should close both inner } and outer }
      expect(result, isNotNull);
    });

    test('feed repairs array in object', () {
      final acc = PartialAccumulator();
      final result = acc.feed('{"items":[1,2');
      // Should close ] and }
      expect(result, isNotNull);
    });

    test('feed yields new partial only when fields change', () {
      final acc = PartialAccumulator();

      // First fragment: name alone → Partial emitted with name
      final r1 = acc.feed('{"name":"Alice"');
      expect(r1, isNotNull);
      expect(r1!.get<String>('name'), 'Alice');
      expect(r1.get<int>('age'), isNull);
      expect(r1.filledCount, 1);

      // Second fragment adds age → new Partial emitted with both fields
      // Simulating streaming: LLM continues writing after the comma
      acc.reset();
      final acc2 = PartialAccumulator();
      final r2a = acc2.feed('{"name":"Alice"');
      final r2b = acc2.feed(',"age":30}');
      // r2b should emit a new Partial now containing both fields
      expect(r2b, isNotNull);
      expect(r2b!.get<String>('name'), 'Alice');
      expect(r2b.get<int>('age'), 30);
      expect(r2b.filledCount, 2);
    });

    test('Partial.isComplete checks required fields', () {
      final acc = PartialAccumulator();
      acc.feed('{"name":"Alice","age":30}');
      final partial = acc.current;

      expect(partial.isComplete(['name', 'age']), true);
      expect(partial.isComplete(['name', 'age', 'email']), false);
    });

    test('Partial.tryBuild succeeds when complete', () {
      final acc = PartialAccumulator();
      acc.feed('{"name":"Alice","age":30}');
      final partial = acc.current;

      final user = partial.tryBuild(
        (json) => _User(json['name'] as String, json['age'] as int),
        ['name', 'age'],
      );
      expect(user, isNotNull);
      expect(user!.name, 'Alice');
    });

    test('Partial.tryBuild returns null when incomplete', () {
      final acc = PartialAccumulator();
      acc.feed('{"name":"Alice"}');
      final partial = acc.current;

      final user = partial.tryBuild(
        (json) => _User(json['name'] as String, (json['age'] ?? 0) as int),
        ['name', 'age'],
      );
      expect(user, isNull);
    });

    test('reset clears state', () {
      final acc = PartialAccumulator();
      acc.feed('{"name":"Alice"}');
      acc.reset();
      expect(acc.current.filledCount, 0);
    });
  });

  // ============================================================
  // 7. Model equality (Equatable props fix)
  // ============================================================

  group('Model equality', () {
    test('Message equality includes toolInput', () {
      final a = Message.assistantToolUse(
          toolName: 't', toolUseId: '1', input: const {'x': 1});
      final b = Message.assistantToolUse(
          toolName: 't', toolUseId: '1', input: const {'x': 2});
      expect(a == b, false,
          reason:
              'Different toolInput should not be equal (props fix verified)');
    });

    test('ToolCallBlock equality includes input', () {
      const a = ToolCallBlock(id: '1', name: 't', input: {'x': 1});
      const b = ToolCallBlock(id: '1', name: 't', input: {'x': 2});
      expect(a == b, false);
    });

    test('Message equality — same data is equal', () {
      final a = Message.user('hello');
      final b = Message.user('hello');
      expect(a == b, true);
    });
  });

  // ============================================================
  // 8. Error types
  // ============================================================

  group('ValidationError', () {
    test('toString includes field and message', () {
      const err = ValidationError(message: 'bad value', field: 'age');
      expect(err.toString(), contains('age'));
      expect(err.toString(), contains('bad value'));
    });

    test('toString defaults to root when no field', () {
      const err = ValidationError(message: 'general issue');
      expect(err.toString(), contains('root'));
    });
  });

  // ============================================================
  // 9. Hooks
  // ============================================================

  group('InstructorHook', () {
    test('BuiltInHooks.debugLog does not throw', () async {
      final hook = BuiltInHooks.debugLog();
      const ctx = InstructorHookContext(
        event: InstructorHookEvent.completionBefore,
        schemaName: 'test',
        attemptNumber: 1,
      );
      // Should not throw
      await hook(ctx);
    });
  });
}
