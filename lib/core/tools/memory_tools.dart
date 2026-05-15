import 'tool_registry.dart';
import '../../features/tools/domain/tool.dart';
import 'tool_module.dart';
import 'tool_groups.dart';

class MemoryTools implements ToolModule {
  static final MemoryTools module = MemoryTools._();
  MemoryTools._();

  @override
  String get name => 'memory';

  @override
  bool get isDynamic => false;

  @override
  List<ToolDefinition> get definitions => [
    ToolDefinition(
      name: 'memory_list',
      description: '列出所有活跃的用户记忆条目。可按分类筛选。'
          '返回每条记忆的 ID、内容、分类、key、置信度、创建时间。'
          '在写入（memory_change）前应先调用此工具，了解已有记忆避免重复。'
          '用户问"你记得我什么""查看我的记忆""列出记忆"时使用。',
      category: ToolCategory.system,
      baseRisk: 0.02,
      inputSchema: {
        'type': 'object',
        'properties': {
          'category': {
            'type': 'string',
            'description':
                '筛选分类: static(姓名/性别/生日/母语等不变信息), dynamic(当前身份/位置/兴趣/目标等可变信息), '
                'preference(回答风格/详细程度/格式/语气等交互偏好), notice(沟通规则/禁止事项等强制性约束), '
                'interest(长期兴趣爱好), fact(用户陈述的个人事实), experience(用户经历的具体事件), plan(计划目标), '
                'professional(职业/工作), health(健康), relationship(人际关系), episodic(对话场景片段), procedural(操作流程记录)。不传返回全部。',
          },
        },
        'required': [],
      },
    ),
    ToolDefinition(
      name: 'memory_search',
      description: '按关键词搜索用户记忆。搜索匹配内容和 key。'
          '返回匹配的记忆条目及其 ID、分类、置信度。'
          '用户问"关于XX我记得什么""搜索XX的记忆"时使用。',
      category: ToolCategory.system,
      baseRisk: 0.02,
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '搜索关键词，模糊匹配记忆内容'},
        },
        'required': ['query'],
      },
    ),
    ToolDefinition(
      name: 'memory_delete',
      description: '删除指定的用户记忆。传记忆 ID 精确删除，或传 keyword 模糊匹配删除。'
          '用户说"删除/忘记关于XX的记忆""不记XX了""清除记忆"时使用。',
      category: ToolCategory.system,
      baseRisk: 0.20,
      requiresConfirmation: true,
      tags: ['destructive'],
      inputSchema: {
        'type': 'object',
        'properties': {
          'id': {'type': 'string', 'description': '记忆 ID（memory_list 返回的 id 字段）'},
          'keyword': {'type': 'string', 'description': '关键词，匹配内容中包含该词的记忆并删除'},
        },
        'required': [],
      },
    ),
    ToolDefinition(
      name: 'memory_change',
      description: '添加或更新用户记忆。category + key 联合去重：相同 category+key 则更新内容，否则新增。\n'
          '\n'
          '重要：这不是简单的笔记功能——记忆会注入到每次对话的系统提示中，直接影响 AI 的行为和回答。\n'
          '\n'
          'category 指南（选错会导致记忆不被正确使用）：\n'
          '- static: 姓名/性别/生日/母语等几乎不变的信息\n'
          '- dynamic: 当前身份/所在地/使用语言(用户正在使用的语言，非母语)/短期兴趣/目标/行为习惯，以及 agentName(用户给你起的名字)、namePreference(用户希望你如何称呼他/她)、userTitle(用户尊称，如"先生""老师") 等身份设定\n'
          '- preference: 回答风格(answerStyle)、详细程度(detailLevel)、格式(formatPreference)、语气(tone)、视觉偏好(visualPreference) 等交互偏好——存入后自动生效\n'
          '- notice: 沟通规则(communicationRules)、禁止事项(prohibitedItems)、其他要求(otherRequirements) 等强制性约束——存入后自动执行\n'
          '- fact: 用户陈述的个人事实（如"我养了一只猫"）\n'
          '- experience: 用户经历的具体事件（如"上周去了日本"）\n'
          '- plan: 用户的计划/目标\n'
          '- interest: 长期稳定的兴趣爱好（如"喜欢摄影"）。注意：短期/临时的兴趣用 dynamic:shortTermInterests\n'
          '- professional: 职业/工作相关\n'
          '- health: 健康信息\n'
          '- relationship: 人际关系\n'
          '- episodic: 对话场景片段（自动生成，AI 一般不主动创建）\n'
          '- procedural: 操作流程记录（自动生成，AI 一般不主动创建）\n'
          '\n'
          'key 指南（category+key 联合唯一，同名 key 会覆盖旧值。key 必须用下面列出的标准名称，否则行为指令不会生效）：\n'
          '- preference 类请用 answerStyle / detailLevel / formatPreference / tone / visualPreference\n'
          '- dynamic 类请用 agentName / namePreference / userTitle / behaviorHabits / shortTermGoals / shortTermInterests / currentIdentity / location / usingLanguage / knowledgeBackground\n'
          '- notice 类请用 communicationRules / prohibitedItems / otherRequirements\n'
          '- 其他分类自行命名，如 favoriteColor, occupation, hobby 等',
      category: ToolCategory.system,
      baseRisk: 0.10,
      inputSchema: {
        'type': 'object',
        'properties': {
          'content': {
            'type': 'string',
            'description': '记忆内容，一句自包含的陈述。例: "用户偏好简洁的回答风格，不要客套话"、"用户的名字是张三"、"用户是一名后端工程师"',
          },
          'category': {
            'type': 'string',
            'description': '分类: static/dynamic/preference/notice/fact/experience/plan/interest/professional/health/relationship。详见工具 description。',
          },
          'key': {
            'type': 'string',
            'description': '短标识键名(camelCase)，如 agentName, answerStyle, favoriteColor。同一 category 下同名 key 会覆盖旧值。不传则用内容自动生成。',
          },
          'confidence': {
            'type': 'string',
            'enum': ['high', 'medium'],
            'description': '置信度: high=用户明确说出(可直接覆盖 low/medium)，medium=推断得出。默认 medium。',
          },
        },
        'required': ['content', 'category'],
      },
    ),
  ];

  @override
  Map<String, ToolGroup> get groupAssignments => {
    'memory_list': ToolGroup.basic,
    'memory_search': ToolGroup.basic,
    'memory_delete': ToolGroup.basic,
    'memory_change': ToolGroup.basic,
  };
}
