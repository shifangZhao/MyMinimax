import 'dart:convert';
import '../api/minimax_client.dart';

/// Judge 评审结果
class JudgeResult {
  JudgeResult({
    required this.verdict,
    required this.reasoning,
    this.failureReason,
    this.reachedCaptcha = false,
    this.impossibleTask = false,
  });
  final bool? verdict;
  final String? reasoning;
  final String? failureReason;
  final bool reachedCaptcha;
  final bool impossibleTask;

  bool get agreed => verdict == true;
}

/// 通用的任务评审器 — 基于 WebAgent 的 Judge 机制泛化
///
/// 使用方式：
/// ```dart
/// final judge = Judge(client: minimaxClient);
/// final result = await judge.evaluate(
///   task: '用户原始任务描述',
///   agentSummary: 'Agent 报告的结果',
///   steps: [StepRecord(...), ...],
///   agentReportedSuccess: true,
/// );
/// if (!result.agreed) {
///   // Agent 报告成功但 Judge 不同意
/// }
/// ```
class Judge {
  Judge({
    required MinimaxClient client,
    this.maxTokens = 1024,
    this.temperature = 0.0,
  }) : _client = client;

  final MinimaxClient _client;
  final int maxTokens;
  final double temperature;

  /// 通用评审 Prompt 模板
  static String buildJudgePrompt({
    required String task,
    required String agentSummary,
    required String agentTrajectory,
    required bool agentReportedSuccess,
    String? evaluationCriteria,
  }) {
    return '''Evaluate this agent's performance.

<task>
$task
</task>

<agent_result>
Success reported: $agentReportedSuccess
Summary: $agentSummary
</agent_result>

<agent_trajectory>
$agentTrajectory
</agent_trajectory>

${evaluationCriteria ?? _defaultCriteria}

Respond with JSON:
{"verdict": true/false, "reasoning": "...", "failure_reason": "...", "reached_captcha": true/false, "impossible_task": true/false}

- verdict=true: agent correctly completed the task
- verdict=false: agent failed, was blocked, or returned incomplete results
- impossible_task=true: task was fundamentally impossible (broken site, missing auth, 404)''';
  }

  static const _defaultCriteria = '''
Evaluate these criteria:
1. Task Satisfaction: Did the agent complete every explicit requirement?
2. Output Quality: Is the output accurate, complete, and grounded in data?
3. Tool Effectiveness: Did the agent use appropriate tools effectively?
4. Agent Reasoning: Did the agent recover from errors and avoid loops?
5. Resource Handling: Did the agent handle errors, edge cases, and limitations appropriately?''';

  /// 评审 Agent 的执行结果
  ///
  /// [task] 原始任务描述
  /// [agentSummary] Agent 报告的结果摘要
  /// [steps] 执行步骤记录（用于轨迹分析）
  /// [agentReportedSuccess] Agent 自己报告的成功状态
  /// [evaluationCriteria] 可选的评审标准（如果不传，使用默认标准）
  Future<JudgeResult> evaluate({
    required String task,
    required String agentSummary,
    required List<Object> steps,
    required bool agentReportedSuccess,
    String? evaluationCriteria,
  }) async {
    final stepsText = steps.map((s) => s.toString()).join('\n');

    final judgePrompt = buildJudgePrompt(
      task: task,
      agentSummary: agentSummary,
      agentTrajectory: stepsText,
      agentReportedSuccess: agentReportedSuccess,
      evaluationCriteria: evaluationCriteria,
    );

    try {
      final result = await _client.chatCollect(
        judgePrompt,
        maxTokens: maxTokens,
        temperature: temperature,
      );
      return _parseJudgeResponse(result);
    } catch (e) {
      print('[judge] error: \$e');
      return JudgeResult(
        verdict: null,
        reasoning: 'Judge call failed: $e',
      );
    }
  }

  /// 轻量级自评审 — 用于主 Agent 自我检查
  ///
  /// 比完整 Judge 更轻量，适用于频繁的自我检查
  Future<JudgeResult> lightweightCheck({
    required String task,
    required String agentSummary,
    required bool agentReportedSuccess,
  }) async {
    final checkPrompt = '''
Do a quick self-check.

<task>
$task
</task>

<your_result>
Success: $agentReportedSuccess
Summary: $agentSummary
</your_result>

Did you truly complete the task? Reply with JSON:
{"verdict": true/false, "reasoning": "brief explanation"}
''';

    try {
      final result = await _client.chatCollect(
        checkPrompt,
        maxTokens: 512,
        temperature: 0.0,
      );
      return _parseJudgeResponse(result);
    } catch (e) {
      print('[judge] error: \$e');
      return JudgeResult(
        verdict: null,
        reasoning: 'Self-check failed: $e',
      );
    }
  }

  JudgeResult _parseJudgeResponse(String rawResponse) {
    try {
      final jsonStart = rawResponse.indexOf('{');
      final jsonEnd = rawResponse.lastIndexOf('}');
      if (jsonStart >= 0 && jsonEnd > jsonStart) {
        final parsed = jsonDecode(rawResponse.substring(jsonStart, jsonEnd + 1)) as Map<String, dynamic>;
        return JudgeResult(
          verdict: parsed['verdict'] as bool?,
          reasoning: parsed['reasoning'] as String? ?? parsed['failure_reason'] as String?,
          failureReason: parsed['failure_reason'] as String?,
          reachedCaptcha: parsed['reached_captcha'] as bool? ?? false,
          impossibleTask: parsed['impossible_task'] as bool? ?? false,
        );
      }
      return JudgeResult(
        verdict: null,
        reasoning: 'Judge response not parseable: $rawResponse',
      );
    } catch (e) {
      print('[judge] error: \$e');
      return JudgeResult(
        verdict: null,
        reasoning: 'Judge parse error: $e',
      );
    }
  }
}

/// WebAgent 专用的步骤记录
class WebAgentStepRecord {
  const WebAgentStepRecord(this.number, this.url, this.description, this.isError);
  final int number;
  final String url;
  final String description;
  final bool isError;

  @override
  String toString() => '[Step $number] $description';
}

/// MapAgent 专用的步骤记录
class MapAgentStepRecord {
  const MapAgentStepRecord(this.number, this.toolName, this.description, this.isError);
  final int number;
  final String toolName;
  final String description;
  final bool isError;

  @override
  String toString() => '[Step $number] $toolName → $description';
}
