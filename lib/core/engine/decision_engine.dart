import 'input_processor.dart';

/// 决策优先级
enum DecisionPriority {
  /// P0: 实时数据/最新事实 - 必须调用搜索/API
  realtime(0),
  /// P1: 计算/可视化 - 调用代码执行/数据分析
  computation(1),
  /// P2: 图片参考 - 图像分析/搜索
  reference(2),
  /// P3: 纯知识推理 - 直接基于训练数据
  knowledge(3);

  final int level;
  const DecisionPriority(this.level);
}

/// 决策结果
class Decision {

  Decision({
    required this.priority,
    this.tools = const [],
    this.reasoning,
    this.confidence = 1.0,
  });
  final DecisionPriority priority;
  final List<ToolCall> tools;
  final String? reasoning;
  final double confidence;
}

/// 工具调用计划
class ToolCall {

  ToolCall({
    required this.toolName,
    required this.arguments,
    this.required = true,
  });
  final String toolName;
  final Map<String, dynamic> arguments;
  final bool required;
}

/// 决策引擎 - 简化版，让AI自行理解用户需求
class DecisionEngine {
  DecisionEngine();

  /// 根据输入分析结果做出决策
  Decision decide(InputAnalysis analysis) {
    // 简化决策：让AI自行判断优先级
    return Decision(
      priority: DecisionPriority.knowledge,
      tools: [],
      reasoning: '直接传递用户输入给AI，让AI自行理解需求',
    );
  }
}
