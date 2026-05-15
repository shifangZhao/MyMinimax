import '../../features/tools/domain/tool.dart';
import 'tool_registry.dart';
import 'tool_module.dart';
import 'tool_groups.dart';

class CityPolicyTools implements ToolModule {
  static final CityPolicyTools module = CityPolicyTools._();
  CityPolicyTools._();

  @override
  String get name => 'cityPolicy';

  @override
  bool get isDynamic => false;

  @override
  List<ToolDefinition> get definitions => [
    ToolDefinition(
      name: 'city_policy_lookup',
      description: '查询中国城市的便民政策信息。覆盖社保、公积金、落户、居住证、限行、教育入学、医保报销、购房资格等。'
          '搜索结果来自政府官方政务网站（*.gov.cn）。'
          '重要提示：'
          '① 城市名尽量用全称（如"杭州市"而非"杭州"）'
          '② policyType 决定了搜索的领域，可选值见 schema。不确定时用 general。'
          '③ 同一问题不要重复调用。搜索结果不够时，提取关键信息后再换一个 policyType 查询。'
          '④ 对于实时政策（如限行），配合 getCurrentTime 确认"今天/明天"的日期。',
      category: ToolCategory.search,
      baseRisk: 0.03,
      inputSchema: {
        'type': 'object',
        'properties': {
          'city': {'type': 'string', 'description': '城市全称，如"杭州市"、"深圳市"、"成都市"'},
          'policyType': {
            'type': 'string',
            'description': '政策类型。可选值：social_insurance(社保), housing_fund(公积金), hukou(落户/户口), '
                'residence_permit(居住证), traffic_restriction(限行/车辆), education(教育/学区/入学), '
                'medical_insurance(医保/看病), housing_purchase(购房资格), general(综合/其他)',
          },
          'keyword': {'type': 'string', 'description': '补充关键词，如"2025年缴费基数"、"异地就医"、"商转公"（可选）'},
          'year': {'type': 'string', 'description': '政策年份，如"2025"、"2026"（可选，不填则搜最新）'},
        },
        'required': ['city', 'policyType'],
      },
    ),
  ];

  @override
  Map<String, ToolGroup> get groupAssignments => {
    'city_policy_lookup': ToolGroup.basic,
  };
}
