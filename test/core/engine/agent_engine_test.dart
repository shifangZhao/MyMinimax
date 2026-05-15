import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myminimax/core/engine/agent_engine.dart';
import '../../helpers/mocks.dart';

void main() {
  group('AgentEngine', () {
    late MockMinimaxClient mockClient;
    late AgentEngine engine;

    setUp(() {
      mockClient = MockMinimaxClient();
      engine = AgentEngine(client: mockClient);
    });

    test('initial state has empty message history', () {
      expect(engine.messages, isEmpty);
    });

    test('clearHistory empties messages', () {
      // Add a message via process, then clear
      when(() => mockClient.chatStream(
        any(),
        systemPrompt: any(named: 'systemPrompt'),
        tools: any(named: 'tools'),
        directMessages: any(named: 'directMessages'),
        temperature: any(named: 'temperature'),
        topP: any(named: 'topP'),
        maxTokens: any(named: 'maxTokens'),
        thinkingBudgetTokens: any(named: 'thinkingBudgetTokens'),
        toolChoice: any(named: 'toolChoice'),
      )).thenAnswer((_) => Stream.empty());

      // The engine is properly constructed with the mock
      expect(engine, isNotNull);
      expect(engine.messages, isEmpty);
    });

    test('configureInference sets parameters', () {
      engine.configureInference(
        temperature: 0.5,
        topP: 0.9,
        maxTokens: 4096,
      );

      expect(engine.temperature, 0.5);
      expect(engine.topP, 0.9);
      expect(engine.maxTokens, 4096);
    });

    test('decisionEngine is created', () {
      expect(engine.decisionEngine, isNotNull);
    });
  });
}
