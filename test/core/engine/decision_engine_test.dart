import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/core/engine/decision_engine.dart';
import 'package:myminimax/core/engine/input_processor.dart';

void main() {
  group('InputProcessor', () {
    late InputProcessor processor;

    setUp(() {
      processor = InputProcessor();
    });

    test('analyze returns raw input', () {
      final result = processor.analyze('Hello, world!');
      expect(result.rawInput, 'Hello, world!');
    });

    test('analyze handles empty input', () {
      final result = processor.analyze('');
      expect(result.rawInput, '');
    });

    test('analyze handles context parameter', () {
      final result = processor.analyze('query', context: {'key': 'value'});
      expect(result.rawInput, 'query');
    });
  });

  group('DecisionEngine', () {
    late DecisionEngine engine;

    setUp(() {
      engine = DecisionEngine();
    });

    test('decide returns knowledge priority by default', () {
      final analysis = InputAnalysis(rawInput: 'What is Dart?');
      final decision = engine.decide(analysis);

      expect(decision.priority, DecisionPriority.knowledge);
      expect(decision.tools, isEmpty);
      expect(decision.reasoning, isNotNull);
    });

    test('Decision model has correct fields', () {
      final decision = Decision(
        priority: DecisionPriority.realtime,
        tools: [ToolCall(toolName: 'webSearch', arguments: {'query': 'test'})],
        reasoning: 'Needs live data',
        confidence: 0.9,
      );

      expect(decision.priority, DecisionPriority.realtime);
      expect(decision.tools.length, 1);
      expect(decision.tools.first.toolName, 'webSearch');
      expect(decision.confidence, 0.9);
    });
  });

  group('DecisionPriority', () {
    test('levels are in correct order', () {
      expect(DecisionPriority.realtime.level, lessThan(DecisionPriority.computation.level));
      expect(DecisionPriority.computation.level, lessThan(DecisionPriority.reference.level));
      expect(DecisionPriority.reference.level, lessThan(DecisionPriority.knowledge.level));
    });
  });

  group('ToolCall', () {
    test('defaults required to true', () {
      final call = ToolCall(toolName: 'test', arguments: {});
      expect(call.required, true);
    });

    test('stores arguments', () {
      final call = ToolCall(
        toolName: 'webSearch',
        arguments: {'query': 'flutter', 'limit': 10},
      );
      expect(call.toolName, 'webSearch');
      expect(call.arguments['query'], 'flutter');
      expect(call.arguments['limit'], 10);
    });
  });
}
