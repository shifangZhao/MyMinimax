import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/core/api/minimax_client.dart';
import 'package:myminimax/core/orchestrator/decomposer/task_decomposer.dart';
import 'package:myminimax/core/orchestrator/decomposer/decomposition_prompt.dart';
import 'package:myminimax/core/orchestrator/models/task_model.dart';

/// A minimal MinimaxClient subclass that returns predefined responses.
class _MockMinimaxClient extends MinimaxClient {
  _MockMinimaxClient({String collectResponse = ''}) : super(apiKey: 'test-key');

  String collectResponse = '';

  @override
  Future<String> chatCollect(
    String message, {
    List<Map<String, String>>? history,
    dynamic systemPrompt,
    List<Map<String, dynamic>>? tools,
    double temperature = 1.0,
    double topP = 0.95,
    int maxTokens = 16384,
    int thinkingBudgetTokens = 6000,
    Map<String, dynamic>? toolChoice,
  }) async {
    return collectResponse;
  }

  @override
  Stream<ChatStreamResponse> chatStream(
    String message, {
    List<Map<String, String>>? history,
    dynamic systemPrompt,
    List<Map<String, dynamic>>? tools,
    List<Map<String, dynamic>>? directMessages,
    CancelToken? cancelToken,
    double temperature = 1.0,
    double topP = 0.95,
    int maxTokens = 16384,
    int thinkingBudgetTokens = 6000,
    Map<String, dynamic>? toolChoice,
  }) async* {
    yield ChatStreamResponse(content: collectResponse, stopReason: 'end_turn');
  }
}

void main() {
  // ── DecompositionPrompt ──
  group('DecompositionPrompt', () {
    test('build returns a non-empty string', () {
      final prompt = DecompositionPrompt.build('test request');
      expect(prompt, isNotEmpty);
    });

    test('build includes the user request', () {
      final prompt = DecompositionPrompt.build('帮我查天气');
      expect(prompt, contains('帮我查天气'));
    });

    test('build includes tool group definitions', () {
      final prompt = DecompositionPrompt.build('test');
      expect(prompt, contains('map'));
      expect(prompt, contains('browser'));
      expect(prompt, contains('phone'));
    });

    test('build includes project context when provided', () {
      final prompt = DecompositionPrompt.build('test', projectContext: 'Flutter项目');
      expect(prompt, contains('Flutter项目'));
    });

    test('build includes conversation context when provided', () {
      final prompt = DecompositionPrompt.build('test', conversationContext: '历史对话');
      expect(prompt, contains('历史对话'));
    });
  });

  // ── TaskDecomposer ──
  group('TaskDecomposer', () {
    late _MockMinimaxClient mockClient;
    late TaskDecomposer decomposer;

    setUp(() {
      mockClient = _MockMinimaxClient();
      decomposer = TaskDecomposer(client: mockClient);
    });

    group('decompose', () {
      test('parses valid JSON decomposition', () async {
        mockClient.collectResponse = '''
{
  "complexityTier": "medium",
  "tasks": [
    {
      "id": "t1",
      "label": "查询天气",
      "description": "使用 getWeather 查询北京天气",
      "dependsOn": [],
      "requiredToolGroups": ["basic"],
      "params": {"temperature": 0.3}
    },
    {
      "id": "t2",
      "label": "生成报告",
      "description": "将天气数据整理成报告",
      "dependsOn": ["t1"],
      "requiredToolGroups": ["basic"],
      "params": {}
    }
  ],
  "workingMemoryInit": {
    "userIntent": "查询天气并生成报告"
  }
}
''';
        final result = await decomposer.decompose('查询天气并生成报告');
        expect(result.complexityTier, ComplexityTier.medium);
        expect(result.graph.nodes, hasLength(2));
        expect(result.workingMemoryInit['userIntent'], '查询天气并生成报告');
      });

      test('handles markdown code fence wrapping', () async {
        mockClient.collectResponse = '```json\n{"complexityTier": "small", "tasks": [{"id": "t1", "label": "test", "description": "test", "dependsOn": [], "requiredToolGroups": ["basic"], "params": {}}], "workingMemoryInit": {}}\n```';
        final result = await decomposer.decompose('test');
        expect(result.graph.nodes, hasLength(1));
      });

      test('filters out invalid tool groups', () async {
        mockClient.collectResponse = '''
{
  "complexityTier": "small",
  "tasks": [
    {
      "id": "t1",
      "label": "test",
      "description": "test",
      "dependsOn": [],
      "requiredToolGroups": ["invalid_group", "basic"],
      "params": {}
    }
  ],
  "workingMemoryInit": {}
}
''';
        final result = await decomposer.decompose('test');
        expect(result.graph.nodes[0].requiredToolGroups, isNot(contains('invalid_group')));
        expect(result.graph.nodes[0].requiredToolGroups, contains('basic'));
      });

      test('falls back to single task on all parse failures', () async {
        mockClient.collectResponse = 'not valid json at all {{{';
        final result = await decomposer.decompose('test');
        expect(result.graph.nodes, hasLength(1));
        expect(result.graph.nodes[0].label, '处理用户请求');
      });

      test('rejects graph with cycles and falls back', () async {
        mockClient.collectResponse = '''
{
  "complexityTier": "small",
  "tasks": [
    {"id": "t1", "label": "A", "description": "A", "dependsOn": ["t2"], "requiredToolGroups": ["basic"], "params": {}},
    {"id": "t2", "label": "B", "description": "B", "dependsOn": ["t1"], "requiredToolGroups": ["basic"], "params": {}}
  ],
  "workingMemoryInit": {}
}
''';
        final result = await decomposer.decompose('test');
        expect(result.graph.nodes, hasLength(1)); // fallback
      });
    });
  });
}
