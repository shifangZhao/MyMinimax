import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/core/api/minimax_client.dart';
import 'package:myminimax/core/orchestrator/models/task_model.dart';
import 'package:myminimax/core/orchestrator/models/dag_model.dart';
import 'package:myminimax/core/orchestrator/models/working_memory.dart';
import 'package:myminimax/core/orchestrator/models/execution_state.dart';
import 'package:myminimax/core/orchestrator/executor/sub_task_runner.dart';
import 'package:myminimax/core/orchestrator/executor/dag_executor.dart';
import 'package:myminimax/core/orchestrator/synthesizer/result_synthesizer.dart';
import 'package:myminimax/core/orchestrator/synthesizer/synthesis_prompt.dart';
import 'package:myminimax/core/orchestrator/orchestrator_types.dart';

/// Minimal client that returns predefined chunks.
class _MockMinimaxClient extends MinimaxClient {
  _MockMinimaxClient() : super(apiKey: 'test-key');

  /// Each element: (content, stopReason, isToolCall, toolName, toolUseId, toolInput)
  final List<_MockChunk> chunks = [];

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
    for (final c in chunks) {
      yield ChatStreamResponse(
        content: c.content,
        stopReason: c.stopReason,
        isToolCall: c.isToolCall,
        toolName: c.toolName,
        toolUseId: c.toolUseId,
        toolInput: c.toolInput,
        isToolCallFinished: c.isToolCallFinished,
      );
    }
  }

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
    for (final c in chunks) {
      if (c.content != null) return c.content!;
    }
    return '';
  }
}

class _MockChunk {
  final String? content;
  final String? stopReason;
  final bool isToolCall;
  final String? toolName;
  final String? toolUseId;
  final String? toolInput;
  final bool isToolCallFinished;

  _MockChunk({
    this.content,
    this.stopReason,
    this.isToolCall = false,
    this.toolName,
    this.toolUseId,
    this.toolInput,
    this.isToolCallFinished = false,
  });
}

void main() {
  // ── SynthesisPrompt ──
  group('SynthesisPrompt', () {
    test('build returns non-empty prompt', () {
      final prompt = SynthesisPrompt.build(
        userRequest: 'test',
        taskOutputs: [
          {'label': 'A', 'status': 'completed', 'output': 'result A'},
        ],
      );
      expect(prompt, isNotEmpty);
      expect(prompt, contains('test'));
    });

    test('includes task outputs', () {
      final prompt = SynthesisPrompt.build(
        userRequest: 'multi task',
        taskOutputs: [
          {'label': 'Task1', 'status': 'completed', 'output': 'Output1'},
          {'label': 'Task2', 'status': 'completed', 'output': 'Output2'},
        ],
      );
      expect(prompt, contains('Task1'));
      expect(prompt, contains('Output1'));
      expect(prompt, contains('Task2'));
      expect(prompt, contains('Output2'));
    });

    test('includes failed task info', () {
      final prompt = SynthesisPrompt.build(
        userRequest: 'test',
        taskOutputs: [
          {'label': 'FailedTask', 'status': 'failed', 'error': 'some error'},
        ],
      );
      expect(prompt, contains('FailedTask'));
      expect(prompt, contains('failed'));
    });
  });

  // ── ResultSynthesizer ──
  group('ResultSynthesizer', () {
    late _MockMinimaxClient client;
    late ResultSynthesizer synthesizer;

    setUp(() {
      client = _MockMinimaxClient();
      client.chunks.add(_MockChunk(content: '合成的结果'));
      synthesizer = ResultSynthesizer(client: client);
    });

    test('single completed task returns its output directly (no LLM call)', () async {
      final graph = TaskGraph(nodes: [
        TaskNode(id: 't1', label: 'A', description: 'A',
            status: SubTaskStatus.completed, result: '直接输出'),
      ]);
      final result = await synthesizer.synthesize(graph, userRequest: 'test');
      expect(result, '直接输出');
    });

    test('multiple tasks calls LLM for synthesis', () async {
      final graph = TaskGraph(nodes: [
        TaskNode(id: 't1', label: 'A', description: 'A',
            status: SubTaskStatus.completed, result: '结果A'),
        TaskNode(id: 't2', label: 'B', description: 'B',
            status: SubTaskStatus.completed, result: '结果B'),
      ]);
      final result = await synthesizer.synthesize(graph, userRequest: 'test');
      expect(result, '合成的结果');
    });

    test('handles empty outputs', () async {
      final graph = TaskGraph(nodes: [
        TaskNode(id: 't1', label: 'A', description: 'A',
            status: SubTaskStatus.completed, result: null),
      ]);
      final result = await synthesizer.synthesize(graph, userRequest: 'test');
      expect(result, '(无输出)');
    });

    test('handles all failed tasks', () async {
      final graph = TaskGraph(nodes: [
        TaskNode(id: 't1', label: 'A', description: 'A',
            status: SubTaskStatus.failed, errorMessage: '错误'),
      ]);
      final result = await synthesizer.synthesize(graph, userRequest: 'test');
      expect(result, '(无输出)');
    });
  });

  // ── SubTaskRunner ──
  group('SubTaskRunner', () {
    late _MockMinimaxClient client;
    late SubTaskRunner runner;
    late WorkingMemory memory;
    late TaskNode simpleTask;

    setUp(() {
      client = _MockMinimaxClient();
      runner = SubTaskRunner(client: client);
      memory = WorkingMemory();
      simpleTask = TaskNode(
        id: 't1',
        label: '测试任务',
        description: '执行测试',
        requiredToolGroups: ['basic'],
        complexity: ComplexityTier.small,
      );
    });

    test('returns success with output when no tool calls', () async {
      client.chunks.add(_MockChunk(content: '测试完成'));
      final result = await runner.run(simpleTask, memory,
        executeTool: (name, args) async => {'success': true, 'output': 'ok'},
      );
      expect(result.success, true);
      expect(result.output, '测试完成');
      expect(result.toolCallCount, 0);
    });

    test('returns success with extracted data', () async {
      client.chunks.add(_MockChunk(content: '结果 [WM:city=Beijing]'));
      final result = await runner.run(simpleTask, memory,
        executeTool: (name, args) async => {'success': true, 'output': 'ok'},
      );
      expect(result.success, true);
      expect(result.extractedData['city'], 'Beijing');
    });

    test('executes tool and returns result', () async {
      client.chunks.add(_MockChunk(
        isToolCall: true,
        toolName: 'getWeather',
        toolUseId: 'call1',
        toolInput: '{"city":"Beijing"}',
      ));
      client.chunks.add(_MockChunk(
        isToolCallFinished: true,
      ));
      // Second round returns text (no more tools)
      client.chunks.add(_MockChunk(content: 'Weather done'));

      bool toolExecuted = false;
      final result = await runner.run(simpleTask, memory,
        executeTool: (name, args) async {
          toolExecuted = true;
          expect(name, 'getWeather');
          return {'success': true, 'output': '25°C'};
        },
      );
      expect(result.success, true);
      expect(toolExecuted, true);
    });

    test('handles tool execution failure gracefully', () async {
      client.chunks.add(_MockChunk(
        isToolCall: true,
        toolName: 'badTool',
        toolUseId: 'call1',
        toolInput: '{}',
      ));
      client.chunks.add(_MockChunk(
        isToolCallFinished: true,
      ));
      client.chunks.add(_MockChunk(content: 'completed after error'));

      final result = await runner.run(simpleTask, memory,
        executeTool: (name, args) async => throw Exception('工具失败'),
      );
      expect(result.success, true); // recovers from tool error
    });

    test('stops on cancel', () async {
      final cancelToken = CancelToken();
      cancelToken.cancel();
      final result = await runner.run(simpleTask, memory,
        executeTool: (name, args) async => {'success': true, 'output': ''},
        cancelToken: cancelToken,
      );
      expect(result.success, false);
    });
  });

  // ── DagExecutor ──
  group('DagExecutor', () {
    late _MockMinimaxClient client;
    late SubTaskRunner realRunner;
    late DagExecutor executor;
    late WorkingMemory memory;

    setUp(() {
      client = _MockMinimaxClient();
      client.chunks.add(_MockChunk(content: 'done'));
      realRunner = SubTaskRunner(client: client);
      executor = DagExecutor(subTaskRunner: realRunner);
      memory = WorkingMemory();
    });

    test('executes single node graph', () async {
      final graph = TaskGraph(nodes: [
        TaskNode(id: 't1', label: 'A', description: 'do A'),
      ]);
      final states = await executor.execute(graph, memory,
        executeTool: (name, args) async => {'success': true, 'output': ''},
      ).toList();
      expect(states, isNotEmpty);
      expect(graph.nodes[0].status, SubTaskStatus.completed);
    });

    test('executes sequential nodes in order', () async {
      final graph = TaskGraph(nodes: [
        TaskNode(id: 't1', label: 'A', description: 'do A'),
        TaskNode(id: 't2', label: 'B', description: 'do B', dependsOn: ['t1']),
      ]);
      await executor.execute(graph, memory,
        executeTool: (name, args) async => {'success': true, 'output': ''},
      ).toList();
      expect(graph.nodes[0].status, SubTaskStatus.completed);
      expect(graph.nodes[1].status, SubTaskStatus.completed);
    });

    test('skips downstream tasks when predecessor fails', () async {
      // Use a dedicated mock runner that returns failure for t1
      final mockRunner = _MockSubTaskRunner([
        SubTaskResult(taskId: 't1', success: false, error: '模拟失败'),
        SubTaskResult(taskId: 't2', success: true, output: 'should not run'),
      ]);
      final dagExecutor = DagExecutor(subTaskRunner: mockRunner);

      final graph = TaskGraph(nodes: [
        TaskNode(id: 't1', label: 'A', description: 'do A'),
        TaskNode(id: 't2', label: 'B', description: 'do B', dependsOn: ['t1']),
      ]);
      await dagExecutor.execute(graph, memory,
        executeTool: (name, args) async => {'success': true, 'output': ''},
      ).toList();
      expect(graph.nodes[0].status, SubTaskStatus.failed);
      expect(graph.nodes[1].status, SubTaskStatus.skipped);
    });

    test('handles empty graph', () async {
      final graph = TaskGraph(nodes: []);
      final states = await executor.execute(graph, memory,
        executeTool: (name, args) async => {'success': true, 'output': ''},
      ).toList();
      expect(states, hasLength(1));
      expect(states.last.phase, OrchestratorPhase.completed);
    });

    test('aborts when all root tasks fail', () async {
      final mockRunner = _MockSubTaskRunner([
        SubTaskResult(taskId: 't1', success: false, error: '根任务失败'),
      ]);
      final dagExecutor = DagExecutor(subTaskRunner: mockRunner);

      final graph = TaskGraph(nodes: [
        TaskNode(id: 't1', label: 'A', description: 'do A'),
        TaskNode(id: 't2', label: 'B', description: 'do B', dependsOn: ['t1']),
      ]);
      await dagExecutor.execute(graph, memory,
        executeTool: (name, args) async => {'success': true, 'output': ''},
      ).toList();
      expect(graph.nodes[0].status, SubTaskStatus.failed);
      expect(graph.nodes[1].status, SubTaskStatus.skipped);
    });

    test('emits progress states', () async {
      final graph = TaskGraph(nodes: [
        TaskNode(id: 't1', label: 'A', description: 'do A'),
        TaskNode(id: 't2', label: 'B', description: 'do B'),
      ]);
      final states = await executor.execute(graph, memory,
        executeTool: (name, args) async => {'success': true, 'output': ''},
      ).toList();
      expect(states.length, greaterThanOrEqualTo(2));
    });
  });
}

/// A SubTaskRunner that returns predefined results in order.
class _MockSubTaskRunner extends SubTaskRunner {
  _MockSubTaskRunner(this._results)
      : super(client: _MockMinimaxClient());

  final List<SubTaskResult> _results;
  int _callCount = 0;

  @override
  Future<SubTaskResult> run(
    TaskNode task,
    WorkingMemory memory, {
    required ExecuteToolFn executeTool,
    List<String> dependencyIds = const [],
    CancelToken? cancelToken,
  }) async {
    if (_callCount < _results.length) {
      return _results[_callCount++];
    }
    return SubTaskResult(taskId: task.id, success: true, output: 'fallback');
  }
}
