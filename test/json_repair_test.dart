import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/core/api/json_repair.dart';

void main() {
  group('JsonRepair', () {
    test('valid JSON passes through unchanged', () {
      const input = '{"key": "value", "num": 42}';
      final result = JsonRepair.repair(input);
      expect(result, isNotNull);
      expect(jsonDecode(result!), equals({'key': 'value', 'num': 42}));
    });

    test('trailing comma before }', () {
      const input = '{"key": "value",}';
      final result = JsonRepair.repair(input);
      expect(result, isNotNull);
      expect(jsonDecode(result!), equals({'key': 'value'}));
    });

    test('trailing comma before ]', () {
      const input = '["a", "b",]';
      final result = JsonRepair.repair(input);
      expect(result, isNotNull);
      expect(jsonDecode(result!), equals(['a', 'b']));
    });

    test('trailing commas in nested structures', () {
      const input = '{"items": [1, 2,], "meta": {"x": 1,},}';
      final result = JsonRepair.repair(input);
      expect(result, isNotNull);
      expect(jsonDecode(result!), equals({
        'items': [1, 2],
        'meta': {'x': 1},
      }));
    });

    test('missing closing brace', () {
      const input = '{"key": "value"';
      final result = JsonRepair.repair(input);
      expect(result, isNotNull);
      expect(jsonDecode(result!), equals({'key': 'value'}));
    });

    test('missing closing bracket', () {
      const input = '[1, 2, 3';
      final result = JsonRepair.repair(input);
      expect(result, isNotNull);
      expect(jsonDecode(result!), equals([1, 2, 3]));
    });

    test('missing nested delimiters', () {
      const input = '{"a": {"b": "c"}';
      final result = JsonRepair.repair(input);
      expect(result, isNotNull);
      expect(jsonDecode(result!), equals({'a': {'b': 'c'}}));
    });

    test('missing array inside object', () {
      const input = '{"items": [1, 2, 3';
      final result = JsonRepair.repair(input);
      expect(result, isNotNull);
      expect(jsonDecode(result!), equals({'items': [1, 2, 3]}));
    });

    test('unclosed string', () {
      const input = '{"key": "unclosed';
      final result = JsonRepair.repair(input);
      expect(result, isNotNull);
      final decoded = jsonDecode(result!);
      expect(decoded['key'], 'unclosed');
    });

    test('completely broken input returns null', () {
      const input = 'not json at all!!!';
      final result = JsonRepair.repair(input);
      expect(result, isNull);
    });

    test('empty input returns null', () {
      final result = JsonRepair.repair('');
      expect(result, isNull);
    });

    test('already valid complex JSON', () {
      const input = '{"query": "search term", "page": 1, "filters": {"lang": "en"}}';
      final result = JsonRepair.repair(input);
      expect(result, equals(input)); // Unchanged
    });
  });
}
