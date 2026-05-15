import '../../features/tools/domain/tool.dart';
import 'tool_registry.dart';
import 'tool_module.dart';
import 'tool_groups.dart';

class PhoneTools implements ToolModule {
  static final PhoneTools module = PhoneTools._();
  PhoneTools._();

  // ---- ToolModule interface ----
  @override
  String get name => 'phone';

  @override
  bool get isDynamic => false;

  @override
  Map<String, ToolGroup> get groupAssignments => const {
    // phone
    'contacts_search': ToolGroup.phone, 'contacts_list': ToolGroup.phone,
    'contacts_get': ToolGroup.phone, 'contacts_create': ToolGroup.phone,
    'contacts_delete': ToolGroup.phone,
    'calendar_query': ToolGroup.phone, 'calendar_create': ToolGroup.phone,
    'calendar_delete': ToolGroup.phone,
    'phone_call': ToolGroup.phone, 'phone_call_log': ToolGroup.phone,
    'location_get': ToolGroup.phone,
    'sms_read': ToolGroup.phone, 'sms_send': ToolGroup.phone,
    'sms_delete': ToolGroup.phone,
    'clipboard_write': ToolGroup.phone,
    'overlay_show': ToolGroup.phone, 'overlay_hide': ToolGroup.phone,
    'screen_capture': ToolGroup.phone, 'vibrate': ToolGroup.phone,
    'notification_read': ToolGroup.phone, 'notification_post': ToolGroup.phone,
    // cron
    'task_set': ToolGroup.cron, 'task_list': ToolGroup.cron,
    'task_delete': ToolGroup.cron, 'task_update': ToolGroup.cron,
    'task_history': ToolGroup.cron,
    // express
    'express_track': ToolGroup.express, 'express_subscribe': ToolGroup.express,
    'express_map': ToolGroup.express, 'express_check_subscriptions': ToolGroup.express,
  };

  @override
  List<ToolDefinition> get definitions => [
    // ── 通讯录 ──
    ToolDefinition(
      name: 'contacts_search',
      description: '搜索通讯录联系人，按名称匹配。传空字符串列出所有联系人。',
      category: ToolCategory.phone,
      baseRisk: 0.03,
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '搜索关键词（姓名），留空则返回所有联系人'},
        },
        'required': [],
      },
    ),
    ToolDefinition(
      name: 'contacts_list',
      description: '列出所有通讯录联系人',
      category: ToolCategory.phone,
      baseRisk: 0.03,
      inputSchema: {
        'type': 'object',
        'properties': {},
        'required': [],
      },
    ),
    ToolDefinition(
      name: 'contacts_get',
      description: '获取指定联系人的详细信息，包括电话号码、邮箱、组织等',
      category: ToolCategory.phone,
      baseRisk: 0.03,
      inputSchema: {
        'type': 'object',
        'properties': {
          'contactId': {'type': 'string', 'description': '联系人 ID，来自 contacts_search 返回结果'},
        },
        'required': ['contactId'],
      },
    ),
    ToolDefinition(
      name: 'contacts_create',
      description: '创建新的联系人',
      category: ToolCategory.phone,
      baseRisk: 0.10,
      inputSchema: {
        'type': 'object',
        'properties': {
          'givenName': {'type': 'string', 'description': '名'},
          'familyName': {'type': 'string', 'description': '姓（可选）'},
          'phone': {'type': 'string', 'description': '电话号码（可选）'},
          'email': {'type': 'string', 'description': '邮箱地址（可选）'},
        },
        'required': ['givenName'],
      },
    ),
    ToolDefinition(
      name: 'contacts_delete',
      description: '删除指定联系人。需要提供联系人 ID（来自 contacts_search 结果）。此操作不可逆。',
      category: ToolCategory.phone,
      baseRisk: 0.25,
      requiresConfirmation: true,
      tags: ['destructive'],
      inputSchema: {
        'type': 'object',
        'properties': {
          'contactId': {'type': 'string', 'description': '联系人 ID，来自 contacts_search 返回结果'},
        },
        'required': ['contactId'],
      },
    ),

    // ── 日历 ──
    ToolDefinition(
      name: 'calendar_query',
      description: '查询指定日期范围内的日历事件。日期为 ISO 格式字符串（如 2026-05-15）',
      category: ToolCategory.phone,
      baseRisk: 0.03,
      inputSchema: {
        'type': 'object',
        'properties': {
          'startDate': {'type': 'string', 'description': '开始日期，ISO 格式如 2026-05-01'},
          'endDate': {'type': 'string', 'description': '结束日期，ISO 格式如 2026-05-31'},
        },
        'required': ['startDate', 'endDate'],
      },
    ),
    ToolDefinition(
      name: 'calendar_create',
      description: '创建日历事件，可作为提醒使用（到时间手机会弹出通知）。用于：定时提醒、会议、待办事项等。',
      category: ToolCategory.phone,
      baseRisk: 0.10,
      inputSchema: {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': '事件标题（如"下午3点开会"）'},
          'startDate': {'type': 'string', 'description': '开始日期时间，如 2026-05-15T14:00:00'},
          'endDate': {'type': 'string', 'description': '结束日期时间，如 2026-05-15T15:00:00'},
          'description': {'type': 'string', 'description': '事件描述（可选）'},
        },
        'required': ['title', 'startDate', 'endDate'],
      },
    ),
    ToolDefinition(
      name: 'calendar_delete',
      description: '删除指定的日历事件',
      category: ToolCategory.phone,
      baseRisk: 0.15,
      requiresConfirmation: true,
      tags: ['destructive'],
      inputSchema: {
        'type': 'object',
        'properties': {
          'eventId': {'type': 'string', 'description': '事件 ID，来自 calendar_query 返回结果'},
        },
        'required': ['eventId'],
      },
    ),

    // ── AI 定时任务调度 ──
    ToolDefinition(
      name: 'task_set',
      description: '将用户的自然语言提醒需求转为标准的定时任务。\n'
          '用户说"X分钟后做Y""明天8点做Y""每天8点做Y"，你需要\n'
          '1) title — 简短概括任务名\n'
          '2) taskPrompt — AI到时具体做什么，写清目标和步骤\n'
          '3) dueTime — ISO 8601 时间字符串，如 2026-05-15T08:00:00\n'
          '4) repeatIntervalSeconds — 0=单次，86400=每天，3600=每小时，604800=每周',
      category: ToolCategory.cron,
      baseRisk: 0.05,
      inputSchema: {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': '任务名称，简短概括用户意图'},
          'taskPrompt': {'type': 'string', 'description': 'AI执行时要做的具体事项。写清任务目标、步骤和期望输出'},
          'dueTime': {'type': 'string', 'description': 'ISO 8601 执行时间，如 2026-05-15T08:00:00。把用户说的相对时间（"5分钟后""明天8点"）换算成绝对时间再传'},
          'repeatIntervalSeconds': {'type': 'integer', 'description': '重复间隔秒数。0或不填为一次性任务；3600为每小时；86400为每天；604800为每周'},
          'timeoutSeconds': {'type': 'integer', 'description': '超时秒数。执行超过此时长则视为超时，默认为60秒'},
          'maxRetries': {'type': 'integer', 'description': '最大重试次数。执行超时时自动重试，默认为1次（最多重试1次后标记失败）'},
        },
        'required': ['title', 'taskPrompt', 'dueTime'],
      },
    ),
    ToolDefinition(
      name: 'task_list',
      description: '查看已设置的 AI 定时任务列表。包括一次性任务和周期性任务，显示任务名称、下次执行时间、重复规则。',
      category: ToolCategory.cron,
      baseRisk: 0.02,
      inputSchema: {
        'type': 'object',
        'properties': {
          'status': {
            'type': 'string',
            'description': '筛选任务状态：active（默认，仅显示待执行任务）、completed（已完成的非重复任务）、all（全部）',
          },
        },
        'required': [],
      },
    ),
    ToolDefinition(
      name: 'task_delete',
      description: '删除一个已设置的 AI 定时任务。删除后该任务不会再执行。提供 taskId（来自 task_list）。',
      category: ToolCategory.cron,
      baseRisk: 0.25,
      requiresConfirmation: true,
      tags: ['destructive'],
      inputSchema: {
        'type': 'object',
        'properties': {
          'taskId': {'type': 'string', 'description': '任务 ID，来自 task_list 返回结果'},
        },
        'required': ['taskId'],
      },
    ),
    ToolDefinition(
      name: 'task_update',
      description: '修改一个已设置的 AI 定时任务的执行时间、重复规则或任务描述。只需提供要修改的字段。',
      category: ToolCategory.cron,
      baseRisk: 0.10,
      inputSchema: {
        'type': 'object',
        'properties': {
          'taskId': {'type': 'string', 'description': '任务 ID，来自 task_list 返回结果'},
          'title': {'type': 'string', 'description': '新的任务名称（可选）'},
          'taskPrompt': {'type': 'string', 'description': '新的 AI 执行指令（可选）'},
          'dueTime': {'type': 'string', 'description': '新的执行时间，ISO 8601 格式，同 task_set（可选）'},
          'repeatIntervalSeconds': {'type': 'integer', 'description': '新的重复间隔秒数，0 为不重复（可选）'},
          'timeoutSeconds': {'type': 'integer', 'description': '新的超时秒数（可选）'},
          'maxRetries': {'type': 'integer', 'description': '新的最大重试次数（可选）'},
        },
        'required': ['taskId'],
      },
    ),
    ToolDefinition(
      name: 'task_history',
      description: '查看 AI 定时任务的执行历史。包含每次执行的开始时间、耗时、执行结果摘要。用于回顾任务执行情况。',
      category: ToolCategory.cron,
      baseRisk: 0.02,
      inputSchema: {
        'type': 'object',
        'properties': {
          'limit': {'type': 'integer', 'description': '返回记录数量上限，默认 20'},
        },
        'required': [],
      },
    ),

    // ── 电话 ──
    ToolDefinition(
      name: 'phone_call',
      description: '拨打电话到指定号码。注意：此操作会直接呼出电话。',
      category: ToolCategory.phone,
      baseRisk: 0.20,
      requiresConfirmation: true,
      inputSchema: {
        'type': 'object',
        'properties': {
          'phoneNumber': {'type': 'string', 'description': '要拨打的电话号码'},
        },
        'required': ['phoneNumber'],
      },
    ),
    ToolDefinition(
      name: 'phone_call_log',
      description: '获取最近的通话记录列表',
      category: ToolCategory.phone,
      baseRisk: 0.05,
      inputSchema: {
        'type': 'object',
        'properties': {
          'limit': {'type': 'integer', 'description': '返回数量上限，默认 50'},
        },
        'required': [],
      },
    ),

    // ── 定位 ──
    ToolDefinition(
      name: 'location_get',
      description: '获取当前设备位置。优先使用原生 GPS（高精度），不可用时自动降级为 IP 定位（城市级精度）。返回经度、纬度及位置来源。',
      category: ToolCategory.phone,
      baseRisk: 0.05,
      inputSchema: {
        'type': 'object',
        'properties': {},
        'required': [],
      },
    ),

    // ── 短信 ──
    ToolDefinition(
      name: 'sms_read',
      description: '读取短信收件箱内容。可按发送人号码过滤。',
      category: ToolCategory.phone,
      baseRisk: 0.08,
      inputSchema: {
        'type': 'object',
        'properties': {
          'limit': {'type': 'integer', 'description': '返回数量上限，默认 50'},
          'senderFilter': {'type': 'string', 'description': '发送人号码过滤，支持模糊匹配（可选）'},
        },
        'required': [],
      },
    ),
    ToolDefinition(
      name: 'sms_send',
      description: '发送短信到指定号码',
      category: ToolCategory.phone,
      baseRisk: 0.15,
      requiresConfirmation: true,
      inputSchema: {
        'type': 'object',
        'properties': {
          'phoneNumber': {'type': 'string', 'description': '目标电话号码'},
          'message': {'type': 'string', 'description': '短信内容'},
        },
        'required': ['phoneNumber', 'message'],
      },
    ),
    ToolDefinition(
      name: 'sms_delete',
      description: '删除指定短信。需要提供短信 ID（来自 sms_read 返回的 smsId）。此操作不可逆。',
      category: ToolCategory.phone,
      baseRisk: 0.25,
      requiresConfirmation: true,
      tags: ['destructive'],
      inputSchema: {
        'type': 'object',
        'properties': {
          'smsId': {'type': 'string', 'description': '短信 ID，来自 sms_read 返回结果'},
        },
        'required': ['smsId'],
      },
    ),

    // ── 系统工具 ──
    ToolDefinition(
      name: 'clipboard_write',
      description: '将文本写入系统剪贴板，之后用户可在任意 App 中粘贴。用于：复制生成的文本、保存重要信息到剪贴板等。',
      category: ToolCategory.phone,
      baseRisk: 0.02,
      inputSchema: {
        'type': 'object',
        'properties': {
          'text': {'type': 'string', 'description': '要复制到剪贴板的文本内容'},
        },
        'required': ['text'],
      },
    ),

    // ── 悬浮窗 ──
    ToolDefinition(
      name: 'overlay_show',
      description: '在屏幕上显示悬浮窗气泡，可拖拽移动，点击回到 App',
      category: ToolCategory.phone,
      baseRisk: 0.02,
      inputSchema: {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': '气泡标题（可选，默认显示 App 名）'},
          'text': {'type': 'string', 'description': '气泡正文（可选）'},
        },
        'required': [],
      },
    ),
    ToolDefinition(
      name: 'overlay_hide',
      description: '隐藏当前显示的悬浮窗气泡',
      category: ToolCategory.phone,
      baseRisk: 0.02,
      inputSchema: {
        'type': 'object',
        'properties': {},
        'required': [],
      },
    ),

    // ── 屏幕截图 ──
    ToolDefinition(
      name: 'screen_capture',
      description: '截取当前设备屏幕并进行文字识别（OCR），返回屏幕上的所有文字内容。'
          '用于查看用户当前屏幕内容、识别任意 App 中的文字。离线OCR，不消耗API额度。'
          '首次使用会弹出系统授权框，需用户确认。',
      category: ToolCategory.phone,
      baseRisk: 0.05,
      inputSchema: {
        'type': 'object',
        'properties': {},
        'required': [],
      },
    ),

    // ── 振动 ──
    ToolDefinition(
      name: 'vibrate',
      description: '让手机振动一下作为提醒（轻振、中等、重振）',
      category: ToolCategory.phone,
      baseRisk: 0.01,
      inputSchema: {
        'type': 'object',
        'properties': {
          'intensity': {'type': 'string', 'description': '振动强度: light/medium/heavy，默认 light'},
        },
        'required': [],
      },
    ),

    // ── 通知监听 ──
    ToolDefinition(
      name: 'notification_read',
      description: '读取设备最近收到的通知列表（需要在系统设置中预先授权通知使用权）',
      category: ToolCategory.phone,
      baseRisk: 0.08,
      inputSchema: {
        'type': 'object',
        'properties': {
          'limit': {'type': 'integer', 'description': '返回数量上限，默认 50'},
        },
        'required': [],
      },
    ),
    ToolDefinition(
      name: 'notification_post',
      description: '发送一条系统通知，会出现在手机通知栏。用于：长任务完成后提醒用户、定时提醒等。',
      category: ToolCategory.phone,
      baseRisk: 0.02,
      inputSchema: {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': '通知标题'},
          'body': {'type': 'string', 'description': '通知正文内容'},
        },
        'required': ['title', 'body'],
      },
    ),
    ToolDefinition(
      name: 'express_track',
      description: '查询快递物流轨迹。输入快递单号即可自动识别快递公司并返回完整物流信息。'
          '支持所有主流快递公司（顺丰、中通、圆通、韵达、EMS、极兔等）。'
          '注意：单号最小6位，最大32位。部分快递（顺丰、中通）还需收件人或寄件人手机号后四位。'
          '返回信息包括：当前状态、物流轨迹明细、预计到达时间、发件/收件城市。',
      category: ToolCategory.phone,
      baseRisk: 0.02,
      inputSchema: {
        'type': 'object',
        'properties': {
          'trackingNumber': {'type': 'string', 'description': '快递单号，6-32位'},
          'companyCode': {'type': 'string', 'description': '快递公司编码（小写），如 yuantong/ems/zhongtong/shunfeng。不确定时留空，系统自动识别'},
          'phone': {'type': 'string', 'description': '收件人或寄件人手机号后四位（顺丰、中通必填，其他选填）'},
        },
        'required': ['trackingNumber'],
      },
    ),
    ToolDefinition(
      name: 'express_subscribe',
      description: '订阅快递单号，之后该快递的状态变化会被持续监控。订阅后用 express_track 查询最新进展。'
          '注意：同一快递公司同一单号每月最多订阅 4 次。如果不确定快递公司，留空 companyCode 会自动识别。',
      category: ToolCategory.phone,
      baseRisk: 0.02,
      inputSchema: {
        'type': 'object',
        'properties': {
          'trackingNumber': {'type': 'string', 'description': '快递单号，6-32位'},
          'companyCode': {'type': 'string', 'description': '快递公司编码（小写），如 yuantong/ems/zhongtong/shunfeng。不确定时留空，系统自动识别'},
          'phone': {'type': 'string', 'description': '收件人或寄件人手机号后四位（顺丰、中通必填，其他选填）'},
        },
        'required': ['trackingNumber'],
      },
    ),
    ToolDefinition(
      name: 'express_map',
      description: '查询快递的地图轨迹，返回可视化地图链接和各物流节点的坐标。'
          '需要提供快递公司编码、出发地和目的地（标准省市区格式）。'
          '适用于用户想看快递在地图上的行进路线时调用。',
      category: ToolCategory.phone,
      baseRisk: 0.02,
      inputSchema: {
        'type': 'object',
        'properties': {
          'trackingNumber': {'type': 'string', 'description': '快递单号，6-32位'},
          'companyCode': {'type': 'string', 'description': '快递公司编码（小写，必填），如 yuantong/ems/zhongtong/shunfeng'},
          'from': {'type': 'string', 'description': '发件地址，标准省市区格式，如"广东省深圳市南山区"'},
          'to': {'type': 'string', 'description': '收件地址，标准省市区格式，如"北京市朝阳区"'},
          'phone': {'type': 'string', 'description': '收件人或寄件人手机号后四位（顺丰、中通必填）'},
        },
        'required': ['trackingNumber', 'companyCode', 'from', 'to'],
      },
    ),
    ToolDefinition(
      name: 'express_check_subscriptions',
      description: '批量查询所有已订阅的快递单号最新状态。返回每个订阅的物流概要。'
          '用于用户问"我的快递都到哪了"或想统一查看所有在途包裹时调用。',
      category: ToolCategory.phone,
      baseRisk: 0.02,
      inputSchema: {
        'type': 'object',
        'properties': {
          'limit': {'type': 'integer', 'description': '最多查询多少个订阅，默认 10'},
        },
        'required': [],
      },
    ),
  ];
}
