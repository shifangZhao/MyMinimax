import '../../api/minimax_client.dart';
import '../models/dag_model.dart';
import '../models/task_model.dart';
import 'synthesis_prompt.dart';

/// Combines all sub-task outputs into a unified final response.
class ResultSynthesizer {
  ResultSynthesizer({required MinimaxClient client}) : _client = client;

  final MinimaxClient _client;

  /// Synthesize all completed task outputs into a single response.
  Future<String> synthesize(TaskGraph graph, {required String userRequest}) async {
    final taskOutputs = graph.nodes
        .where((n) => n.status == SubTaskStatus.completed)
        .map((n) => {
              'label': n.label,
              'status': 'completed',
              'output': n.result,
            })
        .toList();

    // Also include failed tasks for context
    for (final n in graph.nodes.where((n) => n.status == SubTaskStatus.failed)) {
      taskOutputs.add({
        'label': n.label,
        'status': 'failed',
        'error': n.errorMessage,
      });
    }

    if (taskOutputs.length <= 1) {
      // Single task: return its output directly
      for (final t in taskOutputs) {
        if (t['status'] == 'completed' && t['output'] != null) {
          return t['output'] as String;
        }
      }
      return '(无输出)';
    }

    final prompt = SynthesisPrompt.build(
      userRequest: userRequest,
      taskOutputs: taskOutputs,
    );

    return _client.chatCollect(prompt,
      temperature: 0.5,
      maxTokens: 4096,
      thinkingBudgetTokens: 0,
    );
  }
}
