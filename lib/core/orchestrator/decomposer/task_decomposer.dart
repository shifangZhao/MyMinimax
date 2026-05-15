import 'dart:convert';
import '../../api/minimax_client.dart';
import '../../api/json_repair.dart';
import '../models/task_model.dart';
import '../models/dag_model.dart';
import 'decomposition_prompt.dart';

/// Result of the decomposition phase.
class DecompositionResult {
  DecompositionResult({
    required this.complexityTier,
    required this.graph,
    required this.workingMemoryInit,
    this.rawResponse,
  });

  final ComplexityTier complexityTier;
  final TaskGraph graph;
  final Map<String, dynamic> workingMemoryInit;
  final String? rawResponse;
}

/// Intermediate result during streaming decomposition.
class StreamingDecomposition {
  StreamingDecomposition({
    required this.taskLabels,
    this.result,
  });

  /// Task labels discovered so far (progressively populated).
  final List<String> taskLabels;

  /// Non-null when the full JSON has been parsed.
  final DecompositionResult? result;
}

/// LLM-based Task Decomposer.
/// Single entry point: assesses complexity AND decomposes in one call.
class TaskDecomposer {
  TaskDecomposer({required MinimaxClient client}) : _client = client;

  final MinimaxClient _client;

  static const _validToolGroups = {
    'basic', 'map', 'browser', 'file', 'phone',
    'cron', 'express', 'generation', 'trend', 'train',
  };

  /// Regex to extract task labels from partial JSON.
  static final _labelRegex = RegExp(r'"label"\s*:\s*"([^"]+)"');

  /// Streaming entry: assess complexity + decompose in one LLM call.
  /// Yields [StreamingDecomposition] with progressively discovered task labels,
  /// then a final event with the fully parsed [DecompositionResult].
  Stream<StreamingDecomposition> decomposeStream(String userRequest, {
    String? projectContext,
    String? conversationContext,
  }) async* {
    final prompt = DecompositionPrompt.build(
      userRequest,
      projectContext: projectContext,
      conversationContext: conversationContext,
    );

    String accumulated = '';
    final seenLabels = <String>{};

    await for (final chunk in _client.chatStream(prompt,
      temperature: 0.3,
      maxTokens: 4096,
      thinkingBudgetTokens: 0,
    )) {
      // chunk.content is already accumulated by the SSE parser (cumulative, not delta)
      if (chunk.content != null) accumulated = chunk.content!;

      // Extract any new task labels from partial JSON
      final newLabels = _labelRegex.allMatches(accumulated)
          .map((m) => m.group(1)!)
          .where((l) => !seenLabels.contains(l))
          .toList();

      if (newLabels.isNotEmpty) {
        seenLabels.addAll(newLabels);
        yield StreamingDecomposition(
          taskLabels: seenLabels.toList(),
          result: null,
        );
      }
    }

    // Try to parse the full response
    final parsed = _tryParse(accumulated);
    yield StreamingDecomposition(
      taskLabels: parsed?.graph.nodes.map((n) => n.label).toList() ?? seenLabels.toList(),
      result: parsed,
    );
  }

  /// Non-streaming fallback: assess complexity + decompose in one LLM call.
  /// Returns a [DecompositionResult] whose [complexityTier] tells the caller
  /// whether orchestration is needed (medium/large) or fallthrough (trivial/small).
  Future<DecompositionResult> decompose(String userRequest, {
    String? projectContext,
    String? conversationContext,
  }) async {
    final prompt = DecompositionPrompt.build(
      userRequest,
      projectContext: projectContext,
      conversationContext: conversationContext,
    );

    String? lastRaw;

    // Retry up to 2 times on parse failure
    for (int attempt = 0; attempt < 2; attempt++) {
      final response = await _client.chatCollect(prompt,
        temperature: 0.3,
        maxTokens: 4096,
        thinkingBudgetTokens: 0,
      );

      lastRaw = response;
      final parsed = _tryParse(response);
      if (parsed != null) return parsed;
    }

    // Fallback: treat as a single small task
    return DecompositionResult(
      complexityTier: ComplexityTier.small,
      graph: TaskGraph(nodes: [
        TaskNode(
          id: 't1',
          label: '处理用户请求',
          description: userRequest,
          requiredToolGroups: ['basic'],
          status: SubTaskStatus.ready,
        ),
      ]),
      workingMemoryInit: {'userIntent': userRequest},
      rawResponse: lastRaw,
    );
  }

  DecompositionResult? _tryParse(String raw) {
    // Strip markdown code fences if present
    var json = raw.trim();
    if (json.startsWith('```')) {
      final start = json.indexOf('\n');
      final end = json.lastIndexOf('```');
      if (start > 0 && end > start) {
        json = json.substring(start, end).trim();
      }
    }

    // Try direct parse, then repair
    Map<String, dynamic> data;
    try {
      data = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      final repaired = JsonRepair.repair(json);
      if (repaired == null) return null;
      try {
        data = jsonDecode(repaired) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }

    // Parse complexity tier
    final tierStr = (data['complexityTier'] as String?)?.toLowerCase() ?? 'small';
    final tier = _parseTier(tierStr);

    // Parse working memory init
    final wmInit = data['workingMemoryInit'] as Map<String, dynamic>? ?? {};

    // Parse tasks (may be empty for trivial)
    final tasksRaw = data['tasks'] as List<dynamic>? ?? [];
    final nodes = <TaskNode>[];
    for (final item in tasksRaw) {
      final task = item as Map<String, dynamic>;
      final requiredGroups = (task['requiredToolGroups'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [];

      // Validate tool group names
      final validGroups = requiredGroups.where((g) => _validToolGroups.contains(g)).toList();

      nodes.add(TaskNode(
        id: task['id'] as String? ?? 't${nodes.length + 1}',
        label: task['label'] as String? ?? '',
        description: task['description'] as String? ?? '',
        dependsOn: (task['dependsOn'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ?? [],
        requiredToolGroups: validGroups,
        complexity: _parseTier(task['complexity'] as String? ?? 'small'),
        params: task['params'] as Map<String, dynamic>? ?? {},
      ));
    }

    // For trivial/small: empty tasks is valid (fallthrough signal)
    // For medium/large: empty tasks means parse failure
    if (nodes.isEmpty && tier.needsDecomposition) return null;

    final graph = TaskGraph(nodes: nodes);

    // Validate graph (skip validation for empty graph — trivial fallthrough)
    if (nodes.isNotEmpty) {
      try {
        graph.topologicalLayers();
      } on StateError {
        return null;
      }
    }

    return DecompositionResult(
      complexityTier: tier,
      graph: graph,
      workingMemoryInit: wmInit,
      rawResponse: raw,
    );
  }

  ComplexityTier _parseTier(String s) {
    switch (s.trim().toLowerCase()) {
      case 'trivial':
        return ComplexityTier.trivial;
      case 'small':
        return ComplexityTier.small;
      case 'medium':
        return ComplexityTier.medium;
      case 'large':
        return ComplexityTier.large;
      default:
        return ComplexityTier.small;
    }
  }
}
