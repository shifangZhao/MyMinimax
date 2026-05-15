import 'dart:async';
import 'package:dio/dio.dart';
import '../api/minimax_client.dart';
import 'orchestrator_types.dart';
import 'models/execution_state.dart';
import 'decomposer/task_decomposer.dart';
import 'executor/dag_executor.dart';
import 'executor/sub_task_runner.dart';
import 'memory/working_memory_store.dart';
import 'synthesizer/result_synthesizer.dart';

/// Main orchestrator entry point.
///
/// Entry flow:
/// 1. Decompose (assesses complexity + builds DAG in one streaming call)
/// 2. Execute DAG layer by layer
/// 3. Synthesize results
class OrchestratorEngine {
  OrchestratorEngine({required MinimaxClient client})
      : _decomposer = TaskDecomposer(client: client),
        _subTaskRunner = SubTaskRunner(client: client),
        _synthesizer = ResultSynthesizer(client: client) {
    _dagExecutor = DagExecutor(subTaskRunner: _subTaskRunner);
  }

  final TaskDecomposer _decomposer;
  final SubTaskRunner _subTaskRunner;
  late final DagExecutor _dagExecutor;
  final ResultSynthesizer _synthesizer;
  final WorkingMemoryStore _memoryStore = WorkingMemoryStore();

WorkingMemoryStore get memoryStore => _memoryStore;

  /// Whether the engine is currently orchestrating.
  bool get isActive => _active;
  bool _active = false;

  /// Main entry: orchestrate a user request.
  ///
  /// Returns a stream of [OrchestratorState] for real-time UI feedback.
  /// For trivial/small tasks, emits a single "fallthrough" state.
  /// For medium/large tasks, runs the full pipeline.
  Stream<OrchestratorState> orchestrate({
    required String userRequest,
    required String requestId,
    required ExecuteToolFn executeTool,
    String? projectContext,
    String? conversationContext,
    CancelToken? cancelToken,
  }) async* {
    _active = true;

    try {
      // ── Phase 1: Assess complexity (immediate yield) ──
      yield OrchestratorState(phase: OrchestratorPhase.assessingComplexity, progress: 0.05);

      // ── Phase 2: Stream decomposition (assess + decompose in one call) ──
      // First yield "decomposing" so status bar shows immediately
      yield OrchestratorState(
        phase: OrchestratorPhase.decomposing,
        progress: 0.1,
        partialResult: '',
      );

      StreamingDecomposition? finalDecomp;
      final taskLabels = <String>[];

      await for (final partial in _decomposer.decomposeStream(
        userRequest,
        projectContext: projectContext,
        conversationContext: conversationContext,
      )) {
        if (partial.result != null) {
          finalDecomp = partial;
        } else {
          // Update task labels as they arrive
          taskLabels.clear();
          taskLabels.addAll(partial.taskLabels);
          final labelStr = taskLabels.join(' → ');
          yield OrchestratorState(
            phase: OrchestratorPhase.decomposing,
            progress: 0.2,
            partialResult: labelStr,
          );
        }
      }

      // Final decomposition result must be available
      final result = finalDecomp?.result;
      if (result == null) {
        // Parse failed even after streaming — fallthrough
        _active = false;
        yield OrchestratorState(
          phase: OrchestratorPhase.completed,
          progress: 1.0,
          partialResult: '__FALLTHROUGH__',
        );
        return;
      }

      final tier = result.complexityTier;

      // Trivial/small: fallthrough
      if (!tier.needsDecomposition) {
        _active = false;
        yield OrchestratorState(
          phase: OrchestratorPhase.completed,
          complexityTier: tier,
          progress: 1.0,
          partialResult: '__FALLTHROUGH__',
        );
        return;
      }

      final graph = result.graph;
      _memoryStore.initialize(requestId, result.workingMemoryInit);

      // Show task plan briefly before execution
      final planLabels = graph.nodes.map((n) => n.label).join(' → ');
      yield OrchestratorState(
        phase: OrchestratorPhase.decomposing,
        complexityTier: tier,
        graph: graph,
        memory: _memoryStore.memory,
        progress: 0.3,
        partialResult: '已拆解为 ${graph.nodes.length} 个子任务: $planLabels',
      );

      // ── Phase 2: Execute DAG ──
      await for (final state in _dagExecutor.execute(
        graph,
        _memoryStore.memory,
        executeTool: executeTool,
        cancelToken: cancelToken,
      )) {
        yield state.copyWith(
          complexityTier: tier,
          partialResult: state.partialResult,
        );

        if (state.phase == OrchestratorPhase.failed) {
          _active = false;
          return;
        }
      }

      // ── Phase 3: Synthesize ──
      yield OrchestratorState(
        phase: OrchestratorPhase.synthesizing,
        complexityTier: tier,
        graph: graph,
        memory: _memoryStore.memory,
        progress: 0.95,
      );

      final finalResponse = await _synthesizer.synthesize(graph, userRequest: userRequest);

      yield OrchestratorState(
        phase: OrchestratorPhase.completed,
        complexityTier: tier,
        graph: graph,
        memory: _memoryStore.memory,
        progress: 1.0,
        partialResult: finalResponse,
      );
    } finally {
      _active = false;
    }
  }
}
