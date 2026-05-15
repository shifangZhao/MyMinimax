/// Execution status of a single sub-task.
enum SubTaskStatus {
  pending,
  ready,
  running,
  completed,
  failed,
  skipped,
}

/// Complexity tier classification.
/// Determines whether decomposition and review pass are needed.
enum ComplexityTier {
  trivial,
  small,
  medium,
  large;

  /// Max tool-call rounds allowed within this tier.
  int get maxToolRounds {
    switch (this) {
      case ComplexityTier.trivial:
        return 0;
      case ComplexityTier.small:
        return 10;
      case ComplexityTier.medium:
        return 30;
      case ComplexityTier.large:
        return 80;
    }
  }

  /// Whether the orchestrator should schedule an independent review pass.
  bool get needsReview {
    switch (this) {
      case ComplexityTier.trivial:
      case ComplexityTier.small:
        return false;
      case ComplexityTier.medium:
        return true;
      case ComplexityTier.large:
        return true;
    }
  }

  /// Whether the full orchestrator pipeline is needed.
  bool get needsDecomposition {
    switch (this) {
      case ComplexityTier.trivial:
      case ComplexityTier.small:
        return false;
      case ComplexityTier.medium:
      case ComplexityTier.large:
        return true;
    }
  }
}

/// A single sub-task node in the orchestration DAG.
class TaskNode {
  TaskNode({
    required this.id,
    required this.label,
    required this.description,
    this.dependsOn = const [],
    this.requiredToolGroups = const [],
    this.complexity = ComplexityTier.small,
    this.params = const {},
    this.status = SubTaskStatus.pending,
    this.result,
    this.errorMessage,
    this.startedAt,
    this.completedAt,
    this.tokenCount,
    this.snapshotScopeId,
  });

  final String id;
  final String label;
  final String description;
  final List<String> dependsOn;
  final List<String> requiredToolGroups;
  final ComplexityTier complexity;
  final Map<String, dynamic> params;

  SubTaskStatus status;
  String? result;
  String? errorMessage;
  DateTime? startedAt;
  DateTime? completedAt;
  int? tokenCount;
  String? snapshotScopeId;

  TaskNode copyWith({
    SubTaskStatus? status,
    String? result,
    String? errorMessage,
    DateTime? startedAt,
    DateTime? completedAt,
    int? tokenCount,
    String? snapshotScopeId,
  }) {
    return TaskNode(
      id: id,
      label: label,
      description: description,
      dependsOn: dependsOn,
      requiredToolGroups: requiredToolGroups,
      complexity: complexity,
      params: params,
      status: status ?? this.status,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      tokenCount: tokenCount ?? this.tokenCount,
      snapshotScopeId: snapshotScopeId ?? this.snapshotScopeId,
    );
  }
}
