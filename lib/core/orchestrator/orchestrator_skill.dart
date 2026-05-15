import '../skills/skill.dart';

/// Skill that enables the Task Orchestrator for complex requests.
///
/// This skill injects instructions that guide the model to use the
/// orchestrator when multi-step, multi-domain tasks are detected.
class OrchestratorSkill extends Skill {
  OrchestratorSkill._()
      : super(
          name: 'task-orchestrator',
          description: '任务编排引擎 — 将复杂请求拆解为子任务 DAG 并执行',
          category: 'planning',
          triggerOn: [
            // 中文触发词
            '同时', '然后', '接着', '再', '先...再',
            '帮我规划', '帮我安排', '帮我整理',
            '比较', '对比', '调研', '分析',
            '开发', '实现', '写一个', '重构',
            '如果...就', '根据', '依次',
            // 英文触发词
            'plan', 'organize', 'compare', 'research',
            'implement', 'refactor', 'develop',
            'if.*then', 'first.*then',
          ],
          systemPromptSnippet: '''
## 任务编排能力
你有一个 **task_orchestrate** 工具可用。当用户请求复杂、多步骤任务时，调用此工具：
1. 对于**多领域任务**（同时涉及搜索、文件、地图等），编排引擎会自动拆解为子任务 DAG 并依次执行
2. 对于**开发任务**（实现功能、重构代码、写项目），编排引擎按 research → plan → implement → review 流水线执行
3. 子任务之间通过工作内存传递数据，失败时自动降级

调用方式：直接传入用户的原始请求全文，编排器会返回完整的处理结果。
注意：简单问题（单步查询、闲聊、翻译、简单问答）不需要调用编排器，直接回答即可。
''',
          suggestedTools: [],
        );

  static final OrchestratorSkill instance = OrchestratorSkill._();
}
