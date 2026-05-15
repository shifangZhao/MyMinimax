import 'task_model.dart';
import 'dag_model.dart';
import 'working_memory.dart';

/// Phases of the orchestration pipeline.
enum OrchestratorPhase {
  assessingComplexity,
  decomposing,
  executing,
  synthesizing,
  completed,
  failed,
}

/// A single sub-task execution record for UI display.
class SubTaskRecord {
  SubTaskRecord({
    required this.taskId,
    required this.label,
    required this.status,
    this.startedAt,
    this.completedAt,
    this.toolCallCount = 0,
    this.tokenCount = 0,
    this.error,
  });

  final String taskId;
  final String label;
  final SubTaskStatus status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int toolCallCount;
  final int tokenCount;
  final String? error;
}

/// Snapshot of orchestrator state emitted during execution.
class OrchestratorState {
  OrchestratorState({
    required this.phase,
    this.complexityTier = ComplexityTier.small,
    this.graph,
    this.memory,
    this.completedTasks = const [],
    this.currentTaskId,
    this.progress = 0.0,
    this.errorMessage,
    this.partialResult,
  });

  final OrchestratorPhase phase;
  final ComplexityTier complexityTier;
  final TaskGraph? graph;
  final WorkingMemory? memory;
  final List<SubTaskRecord> completedTasks;
  final String? currentTaskId;
  final double progress;
  final String? errorMessage;
  final String? partialResult;

  OrchestratorState copyWith({
    OrchestratorPhase? phase,
    ComplexityTier? complexityTier,
    TaskGraph? graph,
    WorkingMemory? memory,
    List<SubTaskRecord>? completedTasks,
    String? currentTaskId,
    double? progress,
    String? errorMessage,
    String? partialResult,
  }) {
    return OrchestratorState(
      phase: phase ?? this.phase,
      complexityTier: complexityTier ?? this.complexityTier,
      graph: graph ?? this.graph,
      memory: memory ?? this.memory,
      completedTasks: completedTasks ?? this.completedTasks,
      currentTaskId: currentTaskId ?? this.currentTaskId,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      partialResult: partialResult ?? this.partialResult,
    );
  }
}
