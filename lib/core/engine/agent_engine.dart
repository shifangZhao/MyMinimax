import '../api/minimax_client.dart';
import '../tools/tool_registry.dart';
import 'decision_engine.dart';

/// 智能体引擎 - 支持多轮工具调用
class AgentEngine {

  AgentEngine({required MinimaxClient client})
      : _client = client,
        _decisionEngine = DecisionEngine();
  final MinimaxClient _client;
  final DecisionEngine _decisionEngine;

  /// 对话历史，使用完整的 content 列表格式（包含 thinking + tool_use + text）
  final List<Map<String, dynamic>> _messages = [];

  DecisionEngine get decisionEngine => _decisionEngine;

  /// 获取当前对话历史（用于UI显示）
  List<Map<String, dynamic>> get messages => List.unmodifiable(_messages);

  /// 清空对话历史
  void clearHistory() {
    _messages.clear();
  }

  /// 工具定义（从 ToolRegistry 获取，不再重复维护）
  List<Map<String, dynamic>> get tools => ToolRegistry.instance.anthropicSchemas;

  // ── 推理参数（MiniMax 最佳实践默认值） ──
  double temperature = 1.0;
  double topP = 0.95;
  int maxTokens = 16384;
  int thinkingBudgetTokens = 2000;
  Map<String, dynamic>? toolChoice;

  /// 设置推理参数（链式调用）
  void configureInference({
    double? temperature,
    double? topP,
    int? maxTokens,
    int? thinkingBudgetTokens,
    Map<String, dynamic>? toolChoice,
  }) {
    if (temperature != null) this.temperature = temperature;
    if (topP != null) this.topP = topP;
    if (maxTokens != null) this.maxTokens = maxTokens;
    if (thinkingBudgetTokens != null) this.thinkingBudgetTokens = thinkingBudgetTokens;
    this.toolChoice = toolChoice;
  }

  /// 处理用户输入 - 返回流式输出
  Stream<AgentOutput> process(
    String input, {
    String? systemPrompt,
  }) async* {
    // 添加用户消息到历史
    _messages.add({
      'role': 'user',
      'content': [{'type': 'text', 'text': input}]
    });

    // 执行流式响应
    yield* _executeStream(systemPrompt);
  }

  /// 提交工具执行结果（用于多轮对话）
  Stream<AgentOutput> submitToolResult(
    String toolUseId,
    String toolName,
    String result,
  ) async* {
    // 添加工具结果到历史（role 是 user）
    _messages.add({
      'role': 'user',
      'content': [
        {
          'type': 'tool_result',
          'tool_use_id': toolUseId,
          'content': result,
        }
      ]
    });

    // 继续执行流式响应
    yield* _executeStream(null);
  }

  /// 内部流式执行
  Stream<AgentOutput> _executeStream(String? systemPrompt) async* {
    String currentThinking = '';
    String currentContent = '';
    String? pendingToolName;
    String? pendingToolInput;

    await for (final chunk in _client.chatStream(
      '',
      systemPrompt: systemPrompt,
      tools: tools,
      directMessages: _messages,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      thinkingBudgetTokens: thinkingBudgetTokens,
      toolChoice: toolChoice,
    )) {
      final shouldContinue = !chunk.isContentFinished;

      // 处理思考
      if (chunk.hasThinking && chunk.thinking != null) {
        currentThinking = chunk.thinking!;
        yield AgentOutput(
          type: OutputType.thinking,
          content: currentThinking,
          metadata: const OutputMetadata(priority: 'streaming'),
        );
      }

      // 处理文本内容
      if (chunk.content != null && chunk.content!.isNotEmpty) {
        currentContent = chunk.content!;
        yield AgentOutput(
          type: OutputType.content,
          content: currentContent,
          metadata: const OutputMetadata(priority: 'streaming'),
        );
      }

      // 处理工具调用
      if (chunk.isToolCall && chunk.toolName != null) {
        pendingToolName = chunk.toolName;
        pendingToolInput = chunk.toolInput;

        yield AgentOutput(
          type: OutputType.toolCall,
          content: chunk.toolInput ?? '',
          metadata: OutputMetadata(
            intent: chunk.toolName,
            priority: 'tool_call',
          ),
        );
      }

      // 工具调用完成
      if (chunk.isToolCallFinished && pendingToolName != null) {
        yield AgentOutput(
          type: OutputType.toolCallFinished,
          content: pendingToolInput ?? '',
          metadata: OutputMetadata(
            intent: pendingToolName,
            priority: 'tool_call',
          ),
        );
        pendingToolName = null;
        pendingToolInput = null;
      }

      // 对话完成
      if (chunk.isContentFinished) {
        yield AgentOutput(
          type: OutputType.done,
          content: '[完成]',
          metadata: const OutputMetadata(priority: 'done'),
        );
      }

      if (!shouldContinue) break;
    }
  }
}

/// 输出类型
enum OutputType {
  decision,
  thinking,
  content,
  toolCall,
  toolCallFinished,
  done,
}

/// 单个输出块
class AgentOutput {

  AgentOutput({
    required this.type,
    required this.content,
    required this.metadata,
  });
  final OutputType type;
  final String content;
  final OutputMetadata metadata;
}

class OutputMetadata {

  const OutputMetadata({
    this.intent,
    this.constraints,
    this.priority,
  });
  final String? intent;
  final String? constraints;
  final String? priority;
}
