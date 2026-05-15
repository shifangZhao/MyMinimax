/// 工具注册中心 — 所有工具定义的唯一来源
///
/// 消除 agent_engine / chat_repository / tool_executor 三处重复定义。
/// 每个工具包含 Anthropic schema、UI 元数据、风险评估基准值。
///
/// 支持三种工具来源:
/// - builtin: 内置核心工具
/// - mcp: 从 MCP 服务器动态发现的工具
/// - browser: 浏览器工具（动态注入，通过 BrowserTools 模块）
///
/// 通过 ToolModule 接口实现声明式模块化注册。
library;

import '../../features/tools/domain/tool.dart';
import 'tool_module.dart';
import 'tool_groups.dart';
import 'tool_activation_state.dart';

enum ToolSource { builtin, mcp, browser }

class ToolRegistry {
  static final ToolRegistry _defaultInstance = ToolRegistry._();
  static ToolRegistry? _override;

  static ToolRegistry get instance => _override ?? _defaultInstance;

  /// Create a fresh instance for testing.
  static ToolRegistry createForTest() => ToolRegistry._();

  /// Override the singleton instance (for testing).
  static void setTestInstance(ToolRegistry v) => _override = v;

  /// Reset to the default singleton (for testing).
  static void reset() => _override = null;

  ToolRegistry._();

  final Map<String, ToolDefinition> _tools = {};
  final Map<String, ToolDefinition> _mcpTools = {};
  final Map<String, ToolDefinition> _browserTools = {};
  final List<ToolModule> _modules = [];
  final Set<String> _dynamicToolNames = {};

  // ── Modular Registration ──

  /// 注册一个声明式工具模块。
  /// 自动将模块中的所有定义加入 _tools，并注册分组归属。
  void registerModule(ToolModule module) {
    _modules.add(module);
    for (final def in module.definitions) {
      _tools[def.name] = def;
      if (module.isDynamic) {
        _dynamicToolNames.add(def.name);
      }
      final group = module.groupAssignments[def.name] ?? ToolGroup.basic;
      ToolGroupRegistry.register(def.name, group);
    }
  }

  /// 移除所有动态模块（MCP、浏览器），用于重连/刷新场景。
  void clearDynamicModules() {
    for (final name in _dynamicToolNames) {
      _tools.remove(name);
      // MCP tools might also be in _mcpTools
      _mcpTools.remove(name);
      _browserTools.remove(name);
    }
    _dynamicToolNames.clear();
    _modules.removeWhere((m) => m.isDynamic);
    _mcpTools.clear();
    _browserTools.clear();
  }

  // ── Internal (backward compat) ──

  void _register(ToolDefinition def) {
    _tools[def.name] = def;
  }

  // ── Lookup ──

  ToolDefinition? getTool(String name) =>
      _tools[name] ?? _mcpTools[name] ?? _browserTools[name];

  ToolDefinition getToolRequired(String name) => getTool(name)!;

  bool exists(String name) =>
      _tools.containsKey(name) ||
      _mcpTools.containsKey(name) ||
      _browserTools.containsKey(name);

  List<ToolDefinition> get allTools =>
      [..._tools.values, ..._mcpTools.values, ..._browserTools.values];

  List<ToolDefinition> get builtinTools => _tools.values.toList();

  List<ToolDefinition> getToolsByCategory(ToolCategory category) =>
      allTools.where((t) => t.category == category).toList();

  // ── Schemas ──

  /// 全部工具的 Anthropic schema（含 MCP + 浏览器）。
  List<Map<String, dynamic>> get anthropicSchemas =>
      allTools
          .where((t) => t.isEnabled)
          .map((t) => t.toAnthropicSchema())
          .toList();

  /// 仅内置工具的 schema（不含 MCP、浏览器）。
  List<Map<String, dynamic>> get builtinSchemas =>
      _tools.values
          .where((t) => t.isEnabled)
          .map((t) => t.toAnthropicSchema())
          .toList();

  /// 根据当前工具激活状态返回可用工具的 Anthropic schema。
  /// [ToolGroup.basic] 总是包含，其他 group 需在 [state] 中激活才返回。
  List<Map<String, dynamic>> schemasForState([ToolActivationState? state]) {
    final activeNames = state?.activeToolNames ?? ToolGroupRegistry.toolNamesInGroup(ToolGroup.basic);
    final schemas = <Map<String, dynamic>>[];
    for (final tool in allTools) {
      if (!tool.isEnabled) continue;
      if (activeNames.contains(tool.name)) {
        schemas.add(tool.toAnthropicSchema());
      }
    }
    return schemas;
  }

  // ── Activation ──

  /// 解析 activate_tools 参数并返回新的激活状态。
  /// - [] 或 null → 重置为 basic only
  /// - ["trend"] → 添加 trend 组
  /// - ["-trend"] → 移除 trend 组
  ToolActivationState processActivateTools(
      List<dynamic>? args, ToolActivationState currentState) {
    final newState = ToolActivationState();

    if (args == null || args.isEmpty) {
      return newState; // reset to basic only
    }

    // Copy current groups
    for (final g in currentState.activeGroups) {
      newState.addGroups({g});
    }

    for (final raw in args) {
      if (raw is! String) continue;
      if (raw.startsWith('-')) {
        final group = ToolGroupName.fromString(raw.substring(1));
        if (group != null) newState.removeGroups({group});
      } else {
        final group = ToolGroupName.fromString(raw);
        if (group != null) newState.addGroups({group});
      }
    }

    return newState;
  }

  // ── MCP ──

  /// 批量注入 MCP 发现的工具。
  /// 内部委托给 registerModule(McpToolModule)，统一走模块化路径。
  void injectMcpTools(List<Map<String, dynamic>> schemas) {
    _mcpTools.clear();
    // Remove old MCP dynamic tools
    _dynamicToolNames.removeWhere((n) => _mcpTools.containsKey(n));
    _tools.removeWhere((_, def) => def.source == ToolSource.mcp);
    _modules.removeWhere((m) => m.name == 'mcp');

    // Build ToolDefinitions and register via module
    final defs = <ToolDefinition>[];
    for (final schema in schemas) {
      final name = schema['name'] as String;
      final def = ToolDefinition(
        name: name,
        description: schema['description'] as String? ?? '',
        category: ToolCategory.custom,
        inputSchema: schema['input_schema'] as Map<String, dynamic>? ?? {},
        baseRisk: 0.08,
        tags: ['mcp'],
        source: ToolSource.mcp,
      );
      _mcpTools[name] = def;
      defs.add(def);
    }
    if (defs.isNotEmpty) {
      for (final def in defs) {
        _tools[def.name] = def;
        _dynamicToolNames.add(def.name);
        ToolGroupRegistry.register(def.name, ToolGroup.mcp);
      }
    }
  }

  void clearMcpTools() => _mcpTools.clear();

  void clearBrowserTools() {
    _browserTools.clear();
    _dynamicToolNames.removeWhere((n) => _browserTools.containsKey(n));
    _tools.removeWhere((_, def) => def.source == ToolSource.browser);
  }
  int get mcpToolCount => _mcpTools.length;
  int get builtinToolCount => _tools.length;
  int get browserToolCount => _browserTools.length;
  int get totalToolCount =>
      _tools.length + _mcpTools.length + _browserTools.length;

  // ── Backward Compat ──

  /// 批量注册工具定义（旧 API，内部使用）。
  void registerAll(List<ToolDefinition> definitions) {
    for (final def in definitions) {
      _tools[def.name] = def;
    }
  }

  /// 注入浏览器工具（旧 API，内部使用）。
  void injectBrowserTools(List<ToolDefinition> definitions) {
    _browserTools.clear();
    for (final def in definitions) {
      _browserTools[def.name] = def;
    }
  }

  // ── Init ──

  void init() {
    registerModule(_CoreTools());
  }

  // ── UI ──

  List<Tool> toToolModels() =>
      allTools.map((t) => t.toToolModel()).toList();

  void setEnabled(String name, bool enabled) {
    final tool = getTool(name);
    if (tool != null) tool.isEnabled = enabled;
  }
}

// ────────────────────────────────────────────
// CoreTools — 核心内置工具（basic + file + generation）
// ────────────────────────────────────────────

class _CoreTools implements ToolModule {
  @override
  String get name => 'core';

  @override
  bool get isDynamic => false;

  @override
  Map<String, ToolGroup> get groupAssignments => _groupMap;

  static final Map<String, ToolGroup> _groupMap = _buildGroupMap();

  static Map<String, ToolGroup> _buildGroupMap() {
    final m = <String, ToolGroup>{};

    // basic group
    const basic = [
      'getCurrentTime', 'getWeather', 'ask',
      'fetchUrl', 'webSearch',
      'web_agent', 'activate_tools',
      'task_orchestrate',
      'city_policy_lookup',
      'skill_load', 'skill_unload',
    ];
    for (final t in basic) {
      m[t] = ToolGroup.basic;
    }

    // file group
    const file = [
      'readFile', 'writeFile', 'updateFile', 'deleteFile',
      'listFiles', 'moveFile', 'mkdir', 'appendFile',
      'grep', 'glob', 'convertFile',
      // document generation
      'generateDocx', 'generateXlsx', 'generatePptx',
      'generatePdf', 'generateEpub',
    ];
    for (final t in file) {
      m[t] = ToolGroup.file;
    }

    // generation group
    m['generate_page'] = ToolGroup.generation;

    return m;
  }

  @override
  List<ToolDefinition> get definitions => [
        // ── Time ──
        ToolDefinition(
          name: 'getCurrentTime',
          description: '获取当前日期时间、星期、时区、Unix时间戳。用于需要精确时间戳的场景。',
          category: ToolCategory.system,
          baseRisk: 0.0,
          inputSchema: {
            'type': 'object',
            'properties': {
              'timezone': {
                'type': 'string',
                'description': '时区，如 Asia/Shanghai, America/New_York。默认自动检测设备时区',
              },
            },
            'required': [],
          },
        ),

        // ── Weather ──
        ToolDefinition(
          name: 'getWeather',
          description: '查询指定城市当前天气或未来天气预报。返回温度、天气状况、湿度、风力风向、体感温度。',
          category: ToolCategory.search,
          baseRisk: 0.02,
          tags: ['network'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'city': {
                'type': 'string',
                'description': '城市名，如"北京"、"上海"、"杭州"。支持区县级城市',
              },
              'forecastDays': {
                'type': 'integer',
                'description': '预报天数，1=今天，3=今明后三天（默认），7=七天',
              },
            },
            'required': ['city'],
          },
        ),

        // ── System ──
        ToolDefinition(
          name: 'ask',
          description: '需要用户二选一或多选决策时弹窗询问。用于：多个可行方案需要用户选择、'
              '操作前需确认偏好、信息不足需要用户补充但不想中断对话流程。'
              '不要用于简单的"是否继续"——那应该直接执行并汇报。',
          category: ToolCategory.system,
          baseRisk: 0.0,
          inputSchema: {
            'type': 'object',
            'properties': {
              'question': {'type': 'string', 'description': '询问的问题，要具体明确'},
              'options': {
                'type': 'string',
                'description': '可选项，逗号分隔。如 "方案A, 方案B, 方案C"',
              },
            },
            'required': ['question'],
          },
        ),

        // ── activate_tools ──
        ToolDefinition(
          name: 'activate_tools',
          description:
              '按需激活或停用工具组，控制上下文大小和工具可见性。\n'
              'basic 组（时间/天气/搜索/定位/记忆/文件读写）始终可用无需激活。\n'
              '可选组：map(地图导航)、browser(浏览器操控)、phone(通讯录/日历/短信/电话)、'
              'cron(定时任务)、express(快递)、generation(图片/视频/音乐生成)、trend(热搜)、mcp(外部服务器工具)。\n'
              '用法：["map"]激活地图组；["-browser"]停用浏览器组；[]重置为仅 basic。\n'
              '典型场景：用户要求导航 → 先 activate_tools(["map"])；用户说要发短信 → activate_tools(["phone"])；'
              '发现工具定义太多影响判断 → activate_tools(["-不需要的组"])。',
          category: ToolCategory.system,
          baseRisk: 0.02,
          tags: ['meta'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'tool_groups': {
                'type': 'array',
                'items': {'type': 'string'},
                'description':
                    '要激活的工具组名列表。+前缀/无前缀=激活，-前缀=停用。空数组=重置为仅 basic。',
              },
            },
            'required': ['tool_groups'],
          },
        ),

        // ── Skill 管理 ──
        ToolDefinition(
          name: 'skill_load',
          description: '加载指定的专业能力模块。当你需要某个领域专业知识时调用。'
              '加载后该 Skill 的完整工作流程和工具指引会注入上下文。'
              '调用此工具前请先检查当前 system prompt 开头的「可用专业能力模块」目录，确认 skill 名称。',
          category: ToolCategory.system,
          baseRisk: 0.01,
          tags: ['meta', 'skill'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'skill_name': {
                'type': 'string',
                'description': '要加载的技能名称，来自目录列表',
              },
            },
            'required': ['skill_name'],
          },
        ),
        ToolDefinition(
          name: 'skill_unload',
          description: '卸载不再需要的专业能力模块以节省上下文空间。',
          category: ToolCategory.system,
          baseRisk: 0.0,
          tags: ['meta', 'skill'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'skill_name': {
                'type': 'string',
                'description': '要卸载的技能名称',
              },
            },
            'required': ['skill_name'],
          },
        ),

        // ── File Operations ──
        ToolDefinition(
          name: 'readFile',
          description: '读取文件内容',
          category: ToolCategory.file,
          baseRisk: 0.05,
          inputSchema: {
            'type': 'object',
            'properties': {
              'path': {
                'type': 'string',
                'description': '文件路径（基于工作目录根地址，如 test.txt 或 docs/readme.md）',
              },
            },
            'required': ['path'],
          },
        ),
        ToolDefinition(
          name: 'writeFile',
          description: '创建或覆盖写入文件',
          category: ToolCategory.file,
          baseRisk: 0.15,
          requiresConfirmation: true,
          inputSchema: {
            'type': 'object',
            'properties': {
              'path': {
                'type': 'string',
                'description': '文件路径（基于工作目录根地址，如 test.txt 或 docs/readme.md）',
              },
              'content': {'type': 'string', 'description': '文件内容'},
            },
            'required': ['path', 'content'],
          },
        ),
        ToolDefinition(
          name: 'updateFile',
          description: '替换文件中的指定文本',
          category: ToolCategory.file,
          baseRisk: 0.10,
          inputSchema: {
            'type': 'object',
            'properties': {
              'path': {
                'type': 'string',
                'description': '文件路径（基于工作目录根地址，如 test.txt 或 docs/readme.md）',
              },
              'old_str': {'type': 'string', 'description': '要替换的原文本'},
              'new_str': {'type': 'string', 'description': '替换后的新文本'},
            },
            'required': ['path', 'old_str', 'new_str'],
          },
        ),
        ToolDefinition(
          name: 'deleteFile',
          description: '删除文件或目录（移至回收站）',
          category: ToolCategory.file,
          baseRisk: 0.25,
          requiresConfirmation: true,
          tags: ['destructive'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'path': {
                'type': 'string',
                'description': '路径（基于工作目录根地址，如 test.txt 或 docs/）',
              },
            },
            'required': ['path'],
          },
        ),
        ToolDefinition(
          name: 'listFiles',
          description: '列出目录中所有文件',
          category: ToolCategory.file,
          baseRisk: 0.02,
          inputSchema: {
            'type': 'object',
            'properties': {
              'path': {
                'type': 'string',
                'description': '目录路径（基于工作目录根地址）',
              },
            },
            'required': ['path'],
          },
        ),
        ToolDefinition(
          name: 'moveFile',
          description: '移动或重命名文件/目录',
          category: ToolCategory.file,
          baseRisk: 0.12,
          inputSchema: {
            'type': 'object',
            'properties': {
              'source': {
                'type': 'string',
                'description': '源路径（基于工作目录根地址）',
              },
              'destination': {
                'type': 'string',
                'description': '目标路径（基于工作目录根地址）',
              },
            },
            'required': ['source', 'destination'],
          },
        ),
        ToolDefinition(
          name: 'mkdir',
          description: '创建新目录（自动创建父目录）',
          category: ToolCategory.file,
          baseRisk: 0.03,
          inputSchema: {
            'type': 'object',
            'properties': {
              'path': {
                'type': 'string',
                'description': '目录路径（基于工作目录根地址，如 new_folder）',
              },
            },
            'required': ['path'],
          },
        ),
        ToolDefinition(
          name: 'appendFile',
          description: '在文件末尾追加内容',
          category: ToolCategory.file,
          baseRisk: 0.08,
          inputSchema: {
            'type': 'object',
            'properties': {
              'path': {
                'type': 'string',
                'description': '文件路径（基于工作目录根地址，如 test.txt 或 docs/readme.md）',
              },
              'content': {'type': 'string', 'description': '追加的内容'},
            },
            'required': ['path', 'content'],
          },
        ),
        ToolDefinition(
          name: 'grep',
          description: '按正则表达式搜索文件内容，返回匹配行及行号',
          category: ToolCategory.search,
          baseRisk: 0.05,
          inputSchema: {
            'type': 'object',
            'properties': {
              'pattern': {
                'type': 'string',
                'description': '搜索的正则表达式',
              },
              'path': {
                'type': 'string',
                'description': '搜索的目录路径（基于工作目录根地址，不传则为根目录）',
              },
              'include': {
                'type': 'string',
                'description': '文件名过滤 glob，如 *.dart',
              },
            },
            'required': ['pattern'],
          },
        ),
        ToolDefinition(
          name: 'glob',
          description: '按文件名模式匹配查找文件，返回匹配的文件路径列表',
          category: ToolCategory.file,
          baseRisk: 0.02,
          inputSchema: {
            'type': 'object',
            'properties': {
              'pattern': {
                'type': 'string',
                'description': '文件名匹配模式，如 **/*.dart 或 *.json',
              },
              'path': {
                'type': 'string',
                'description': '搜索的目录路径（基于工作目录根地址，不传则为根目录）',
              },
            },
            'required': ['pattern'],
          },
        ),

        // ── File Conversion ──
        ToolDefinition(
          name: 'convertFile',
          description: '将文档/电子表格/演示文稿在常见格式之间互转。'
              '支持：docx↔pdf, xlsx↔csv, pptx↔pdf, html→pdf, md→docx/pdf, csv→xlsx, txt→pdf 等。'
              '返回转换后的文件路径。',
          category: ToolCategory.file,
          baseRisk: 0.08,
          tags: ['file', 'conversion'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'inputPath': {
                'type': 'string',
                'description': '源文件路径',
              },
              'outputFormat': {
                'type': 'string',
                'enum': ['pdf', 'docx', 'xlsx', 'pptx', 'csv', 'html', 'md', 'txt', 'epub'],
                'description': '目标格式',
              },
              'outputPath': {
                'type': 'string',
                'description': '输出文件路径（可选，默认自动生成）',
              },
            },
            'required': ['inputPath', 'outputFormat'],
          },
        ),

        // ── Document Generation ──
        ToolDefinition(
          name: 'generateDocx',
          description: '生成 Word 文档（.docx）。支持标题、正文、表格、图片、页眉页脚、页码、目录等。'
              '传入 Markdown 内容自动转换为 Word 格式。',
          category: ToolCategory.file,
          baseRisk: 0.08,
          tags: ['file', 'generation'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'content': {
                'type': 'string',
                'description': 'Markdown 格式的文档内容',
              },
              'outputPath': {
                'type': 'string',
                'description': '输出文件路径，如 output.docx（可选，默认自动命名）',
              },
              'title': {'type': 'string', 'description': '文档标题（可选）'},
            },
            'required': ['content'],
          },
        ),
        ToolDefinition(
          name: 'generateXlsx',
          description:
              '生成 Excel 电子表格（.xlsx）。支持多 Sheet、公式、数据验证、条件格式、图表、筛选、冻结窗格等。'
              '每个 sheet 对象需包含 name(工作表名) 和 data(二维数组或 CSV 字符串)。',
          category: ToolCategory.file,
          baseRisk: 0.08,
          tags: ['file', 'generation'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'sheets': {
                'type': 'array',
                'description': 'Sheet 定义列表。每项格式: {"name": "Sheet名", "data": [["A1","B1"],["A2","B2"]]}',
                'items': {'type': 'object'},
              },
              'outputPath': {
                'type': 'string',
                'description': '输出文件路径（可选）',
              },
            },
            'required': ['sheets'],
          },
        ),
        ToolDefinition(
          name: 'generatePptx',
          description:
              '生成 PowerPoint 演示文稿（.pptx）。支持多种布局、图片、图表、SmartArt、动画、演讲者备注。',
          category: ToolCategory.file,
          baseRisk: 0.08,
          tags: ['file', 'generation'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'slides': {
                'type': 'array',
                'description': '幻灯片内容列表，每项为 Markdown 字符串',
                'items': {'type': 'string'},
              },
              'outputPath': {
                'type': 'string',
                'description': '输出文件路径（可选）',
              },
              'title': {'type': 'string', 'description': '演示文稿标题（可选）'},
            },
            'required': ['slides'],
          },
        ),
        ToolDefinition(
          name: 'generatePdf',
          description:
              '生成 PDF 文档。支持 Markdown→PDF、HTML→PDF。自动处理中文、分页、页眉页脚、页码。',
          category: ToolCategory.file,
          baseRisk: 0.08,
          tags: ['file', 'generation'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'content': {
                'type': 'string',
                'description': 'Markdown 或 HTML 内容',
              },
              'format': {
                'type': 'string',
                'enum': ['markdown', 'html'],
                'description': '内容格式，默认 markdown',
              },
              'outputPath': {
                'type': 'string',
                'description': '输出文件路径（可选）',
              },
              'title': {'type': 'string', 'description': '文档标题（可选）'},
            },
            'required': ['content'],
          },
        ),
        ToolDefinition(
          name: 'generateEpub',
          description: '生成 EPUB 电子书。支持 Markdown→EPUB，自动生成目录、元数据、封面。',
          category: ToolCategory.file,
          baseRisk: 0.08,
          tags: ['file', 'generation'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'content': {
                'type': 'string',
                'description': 'Markdown 格式内容',
              },
              'title': {'type': 'string', 'description': '书名'},
              'author': {'type': 'string', 'description': '作者（可选）'},
              'outputPath': {
                'type': 'string',
                'description': '输出文件路径（可选）',
              },
            },
            'required': ['content', 'title'],
          },
        ),

        // ── Web Search ──
        ToolDefinition(
          name: 'fetchUrl',
          description: '抓取网页内容。自动渲染 JavaScript 页面后返回 HTML/文本。'
              '支持多层提取：HTTP 直取 → SPA 渲染 → 浏览器渲染。',
          category: ToolCategory.search,
          baseRisk: 0.08,
          tags: ['network'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'url': {'type': 'string', 'description': '网页URL'},
            },
            'required': ['url'],
          },
        ),
        ToolDefinition(
          name: 'webSearch',
          description:
              '联网搜索最新信息、实时数据或不确定的知识。返回搜索结果摘要和链接。'
              '支持指定搜索条数、过滤域名、限定语言/地区。',
          category: ToolCategory.search,
          baseRisk: 0.05,
          tags: ['network'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'query': {'type': 'string', 'description': '搜索关键词'},
              'numResults': {
                'type': 'integer',
                'description': '返回结果数量，默认 10，最大 50',
              },
            },
            'required': ['query'],
          },
        ),

        // ── Web Agent ──
        ToolDefinition(
          name: 'web_agent',
          description:
              '浏览器自动化代理。打开网页，执行多步操作（点击、输入、提取、截图等），智能完成网页任务。'
              '适用场景：网页信息采集、表单自动填写提交、多页面信息整合、需要交互的网页任务。'
              '单步简单操作（如仅截个图）建议直接用 browser_* 工具。',
          category: ToolCategory.search,
          baseRisk: 0.12,
          tags: ['network', 'browser', 'agent'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'task': {
                'type': 'string',
                'description': '要执行的网页任务描述，越具体越好。'
                    '如"打开xxx网站，搜索关键词，提取前10条结果的标题和链接"',
              },
              'maxSteps': {
                'type': 'integer',
                'description': '最大操作步数，默认 15',
              },
            },
            'required': ['task'],
          },
        ),

        // ── Page Generation ──
        ToolDefinition(
          name: 'generate_page',
          description: '生成完整的网页 / 落地页 / UI 组件。5 种工作模式，根据需求自动选择最佳模式。\n\n'
              '【模式 1 · 参考复刻】先调用 browser_extract_design 提取目标网站的设计语言，再将 extraction JSON 传入本工具，'
              '自动匹配 shadcn/ui 风格预设并生成同风格页面。适合"做一个跟某某网站一样的"。\n'
              '【模式 2 · 自由设计】传入 freestyle:true，无需参考。LLM 自动分析产品类型（161 类）、匹配风格、挑选字体和配色。适合"帮我设计一个XX产品官网"。\n'
              '【模式 3 · 多变体对比】传入 multiVariant:true，同时生成 3 种布局变体（Hero 大图、Split 分栏、Card 卡片网格），LLM 自动评分选最佳。\n'
              '【模式 4 · 紧凑组件】自动检测简单请求（按钮、卡片、表单等）或在明确只需要小组件时传入 compact:true，快速生成单个 UI 组件。\n'
              '【模式 5 · 评审精炼】生成后自动对布局/排版/交互/原创性/配色评分，低于 8 分自动重生成（可用 skipRefine:true 跳过）。\n\n'
              '返回：页面 HTML 源码 + 预览链接。可用 browser_load_html 在内置浏览器中预览效果。',
          category: ToolCategory.custom,
          baseRisk: 0.05,
          tags: ['generation', 'web'],
          inputSchema: {
            'type': 'object',
            'properties': {
              'requirements': {
                'type': 'string',
                'description': '【必填】页面需求描述。包含用途、目标用户、内容结构、风格偏好、配色倾向等。越详细越好。',
              },
              'extraction': {
                'type': 'string',
                'description': '【参考模式】browser_extract_design 返回的设计提取 JSON。有则启动参考复刻模式，无则为自由设计。',
              },
              'contentText': {
                'type': 'string',
                'description': '【参考模式】从参考页面中提取的文本内容，用于填充新页面。配合 extraction 使用。',
              },
              'freestyle': {
                'type': 'boolean',
                'description': '【自由模式】设为 true 则完全自主设计，LLM 自行匹配产品类型、风格、字体、配色。适合无参考的设计需求。',
              },
              'multiVariant': {
                'type': 'boolean',
                'description': '【多变体模式】设为 true 则生成 3 种布局变体并自动评分选最佳。适合对设计质量要求高的场景。',
              },
              'compact': {
                'type': 'boolean',
                'description': '【紧凑模式】设为 true 则快速生成单个 UI 组件（按钮/卡片/表单/导航栏等），跳过复杂分析。',
              },
              'skipRefine': {
                'type': 'boolean',
                'description': '设为 true 则跳过生成后的自动评审精炼，直接返回初稿。适合快速原型阶段。',
              },
              'style': {
                'type': 'string',
                'description': 'shadcn/ui 风格预设：vega(通用后台) / nova(数据密集) / maia(圆润消费) / lyra(硬朗极简) / mira(高密度终端) / luma(圆角光影) / sera(时尚编辑)。默认 vega。',
              },
              'baseColor': {
                'type': 'string',
                'description': '基础色：neutral / stone / zinc / mauve / olive / mist / taupe。默认 neutral。',
              },
              'accentTheme': {
                'type': 'string',
                'description': '强调色：amber / blue / cyan / emerald / fuchsia / green / indigo / lime / orange / pink / purple / red / rose / sky / teal / violet / yellow。',
              },
              'font': {
                'type': 'string',
                'description': '字体：inter / jetbrains-mono / noto-sans-sc / playfair / space-grotesk 等。默认 inter。',
              },
            },
            'required': ['requirements'],
          },
        ),
      ];
}

// ────────────────────────────────────────────
// ToolDefinition
// ────────────────────────────────────────────

class ToolDefinition {
  final String name;
  final String description;
  final ToolCategory category;
  final Map<String, dynamic> inputSchema;
  final double baseRisk;

  /// 无论风险评分如何，始终需用户确认
  final bool requiresConfirmation;

  /// 额外标签（如 "destructive", "network", "mcp"）
  final List<String> tags;

  /// 工具来源
  ToolSource source;

  bool isEnabled;

  bool get isMcp => source == ToolSource.mcp || tags.contains('mcp');
  bool get isBrowser => source == ToolSource.browser || tags.contains('browser');

  ToolDefinition({
    required this.name,
    required this.description,
    required this.category,
    required this.inputSchema,
    this.baseRisk = 0.05,
    this.requiresConfirmation = false,
    this.tags = const [],
    this.source = ToolSource.builtin,
    this.isEnabled = true,
  });

  /// 转为 Anthropic Messages API 工具格式
  Map<String, dynamic> toAnthropicSchema() => {
        'name': name,
        'description': description,
        'input_schema': inputSchema,
      };

  /// 转为 UI Tool 模型
  Tool toToolModel() => Tool(
        name: name,
        description: description,
        category: category,
        isEnabled: isEnabled,
      );
}
