import 'dart:async';
import 'package:dio/dio.dart';
import '../models/task_model.dart';
import '../models/dag_model.dart';
import '../models/working_memory.dart';
import '../models/execution_state.dart';
import '../orchestrator_types.dart';
import 'sub_task_runner.dart';

/// Executes a TaskGraph layer by layer, dispatching independent tasks concurrently.
class DagExecutor {
  DagExecutor({required SubTaskRunner subTaskRunner})
      : _subTaskRunner = subTaskRunner;

  final SubTaskRunner _subTaskRunner;

  /// Execute the DAG, emitting state updates as a stream.
  Stream<OrchestratorState> execute(
    TaskGraph graph,
    WorkingMemory memory, {
    required ExecuteToolFn executeTool,
    CancelToken? cancelToken,
  }) async* {
    List<List<TaskNode>> layers;
    try {
      layers = graph.topologicalLayers();
    } on StateError catch (e) {
      yield OrchestratorState(
        phase: OrchestratorPhase.failed,
        errorMessage: 'DAG cycle detected: ${e.message}',
      );
      return;
    }

    final completedTasks = <SubTaskRecord>[];
    int totalTasks = graph.nodes.length;
    int completedCount = 0;

    for (int layerIdx = 0; layerIdx < layers.length; layerIdx++) {
      // Check cancellation between layers
      if (cancelToken != null && cancelToken.isCancelled) {
        yield OrchestratorState(
          phase: OrchestratorPhase.failed,
          errorMessage: '编排被取消',
          graph: graph,
          memory: memory,
          completedTasks: completedTasks,
          progress: completedCount / totalTasks,
        );
        return;
      }

      final layer = layers[layerIdx];

      // Mark layer tasks as running
      for (final task in layer) {
        task.status = SubTaskStatus.running;
        task.startedAt = DateTime.now();
        yield _buildState(
          graph, memory, completedTasks,
          phase: OrchestratorPhase.executing,
          currentTaskId: task.id,
          progress: completedCount / totalTasks,
        );
      }

      // Run layer tasks concurrently
      final results = await Future.wait(
        layer.map((task) => _runTask(task, memory, executeTool, cancelToken)),
      );

      // Process results
      for (int i = 0; i < layer.length; i++) {
        final task = layer[i];
        final result = results[i];

        if (result.success) {
          task.status = SubTaskStatus.completed;
          task.result = result.output;
          task.tokenCount = result.tokenCount;
          task.completedAt = DateTime.now();

          // Write extracted data to working memory
          for (final entry in result.extractedData.entries) {
            memory.set(entry.key, entry.value, sourceTaskId: task.id);
          }
        } else {
          task.status = SubTaskStatus.failed;
          task.errorMessage = result.error;
          task.completedAt = DateTime.now();

          // Mark downstream tasks as skipped
          _markDownstreamSkipped(graph, task.id);
        }

        completedTasks.add(SubTaskRecord(
          taskId: task.id,
          label: task.label,
          status: task.status,
          startedAt: task.startedAt,
          completedAt: task.completedAt,
          toolCallCount: result.toolCallCount,
          tokenCount: result.tokenCount,
          error: result.error,
        ));
        completedCount++;

        // 每完成一个子任务就 yield 一次，实现流式输出子任务结果
        yield _buildState(
          graph, memory, completedTasks,
          phase: OrchestratorPhase.executing,
          currentTaskId: task.id,
          progress: completedCount / totalTasks,
          partialResult: result.success ? result.output : null,
        );
      }

      // If any critical failure, stop early
      if (graph.hasFailed && _shouldAbort(graph)) {
        yield _buildState(
          graph, memory, completedTasks,
          phase: OrchestratorPhase.failed,
          errorMessage: '关键子任务失败，编排终止',
          progress: completedCount / totalTasks,
        );
        return;
      }
    }

    // All done
    yield _buildState(
      graph, memory, completedTasks,
      phase: graph.hasFailed ? OrchestratorPhase.failed : OrchestratorPhase.completed,
      progress: 1.0,
    );
  }

  Future<SubTaskResult> _runTask(
    TaskNode task,
    WorkingMemory memory,
    ExecuteToolFn executeTool,
    CancelToken? cancelToken,
  ) {
    return _subTaskRunner.run(
      task,
      memory,
      executeTool: executeTool,
      dependencyIds: task.dependsOn,
      cancelToken: cancelToken,
    );
  }

  /// Mark all nodes that directly or indirectly depend on [failedId] as skipped.
  void _markDownstreamSkipped(TaskGraph graph, String failedId) {
    bool changed = true;
    while (changed) {
      changed = false;
      for (final node in graph.nodes) {
        if (node.status == SubTaskStatus.pending ||
            node.status == SubTaskStatus.ready) {
          final hasFailedDep = node.dependsOn.any((depId) {
            final dep = graph.nodes.firstWhere((n) => n.id == depId);
            return dep.status == SubTaskStatus.failed ||
                dep.status == SubTaskStatus.skipped;
          });
          if (hasFailedDep) {
            node.status = SubTaskStatus.skipped;
            changed = true;
          }
        }
      }
    }
  }

  /// Whether a failure should abort the entire orchestration.
  bool _shouldAbort(TaskGraph graph) {
    // Abort if ALL entry-level tasks failed (nothing could complete)
    final roots = graph.nodes.where((n) => n.dependsOn.isEmpty);
    return roots.isNotEmpty && roots.every((n) => n.status == SubTaskStatus.failed);
  }

  OrchestratorState _buildState(
    TaskGraph graph,
    WorkingMemory memory,
    List<SubTaskRecord> completedTasks, {
    required OrchestratorPhase phase,
    String? currentTaskId,
    double? progress,
    String? errorMessage,
    String? partialResult,
  }) {
    return OrchestratorState(
      phase: phase,
      graph: graph,
      memory: memory,
      completedTasks: List.from(completedTasks),
      currentTaskId: currentTaskId,
      progress: progress ?? 0.0,
      errorMessage: errorMessage,
      partialResult: partialResult,
    );
  }
}
