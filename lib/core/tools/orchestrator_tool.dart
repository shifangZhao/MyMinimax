import 'tool_registry.dart';
import '../../features/tools/domain/tool.dart';
import 'tool_module.dart';
import 'tool_groups.dart';

class OrchestratorTools implements ToolModule {
  static final OrchestratorTools module = OrchestratorTools._();
  OrchestratorTools._();

  @override
  String get name => 'orchestrator';

  @override
  bool get isDynamic => false;

  @override
  List<ToolDefinition> get definitions => [
    ToolDefinition(
      name: 'task_orchestrate',
      description: '将复杂多步骤请求拆解为子任务，并行或串行执行，最后汇总为完整结果。\n'
          '适用：跨部门任务（如"查天气+规划路线+订会议室"）、多文件处理、需要多个工具协同的复杂流程。\n'
          '不适用：单步查询、简单问答、已有专用工具能一步完成的任务。\n'
          '传入用户原始请求即可，编排引擎自动规划执行。',
      category: ToolCategory.custom,
      baseRisk: 0.20,
      tags: ['planning', 'complex'],
      inputSchema: {
        'type': 'object',
        'properties': {
          'userRequest': {
            'type': 'string',
            'description': '用户原始请求全文',
          },
          'projectContext': {
            'type': 'string',
            'description': '项目上下文（可选）',
          },
          'conversationContext': {
            'type': 'string',
            'description': '对话历史上下文（可选）',
          },
        },
        'required': ['userRequest'],
      },
    ),
  ];

  @override
  Map<String, ToolGroup> get groupAssignments => {
    'task_orchestrate': ToolGroup.basic,
  };
}
