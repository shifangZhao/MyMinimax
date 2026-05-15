import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/chat/presentation/chat_page.dart';
import 'decision_engine.dart';
import 'input_processor.dart';
import 'agent_engine.dart';

/// 智能体引擎Provider
final agentEngineProvider = Provider<AgentEngine>((ref) {
  final client = ref.watch(minimaxClientProvider);
  return AgentEngine(client: client);
});

/// 引擎决策信息（给UI展示用）
class EngineDecisionInfo {

  EngineDecisionInfo({
    required this.priority,
    required this.reasoning,
    required this.needsSearch,
    required this.needsCodeExecution,
  });
  final String priority;
  final String reasoning;
  final bool needsSearch;
  final bool needsCodeExecution;
}

/// 引擎集成扩展
extension AgentEngineChatMixin on AgentEngine {
  /// 分析用户输入，返回决策信息
  EngineDecisionInfo analyzeInput(String input, {List<Map<String, String>>? history}) {
    final decision = decisionEngine.decide(InputAnalysis(rawInput: input));

    return EngineDecisionInfo(
      priority: decision.priority.name,
      reasoning: decision.reasoning ?? '',
      needsSearch: decision.priority == DecisionPriority.realtime,
      needsCodeExecution: decision.priority == DecisionPriority.computation,
    );
  }
}
