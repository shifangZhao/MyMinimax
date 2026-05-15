/// 工具组定义 — 所有工具按功能分类，模型通过 activate_tools 按需激活。
library;

enum ToolGroup {
  basic,
  map,
  browser,
  file,
  phone,
  cron,
  express,
  generation,
  trend,
  mcp,
}

extension ToolGroupName on ToolGroup {
  String get label {
    switch (this) {
      case ToolGroup.basic:
        return 'basic';
      case ToolGroup.map:
        return 'map';
      case ToolGroup.browser:
        return 'browser';
      case ToolGroup.file:
        return 'file';
      case ToolGroup.phone:
        return 'phone';
      case ToolGroup.cron:
        return 'cron';
      case ToolGroup.express:
        return 'express';
      case ToolGroup.generation:
        return 'generation';
      case ToolGroup.trend:
        return 'trend';
      case ToolGroup.mcp:
        return 'mcp';
    }
  }

  String get description {
    switch (this) {
      case ToolGroup.basic:
        return '基础工具：时间、天气、搜索、定位、询问用户';
      case ToolGroup.map:
        return '地图工具：地点搜索、路线规划（驾车/公交/步行/骑行）、实时路况、行政区划';
      case ToolGroup.browser:
        return '浏览器工具：网页操控、内容提取、截图、自动化表单填写';
      case ToolGroup.file:
        return '文件工具：文件读写、目录操作、文档转换、表格生成、索引检索';
      case ToolGroup.phone:
        return '手机原生工具：通讯录、日历、短信、电话、定位、通知、悬浮窗、屏幕截图';
      case ToolGroup.cron:
        return '定时任务工具：定时提醒、任务管理、定时任务列表与执行历史';
      case ToolGroup.express:
        return '快递工具：物流轨迹查询、单号订阅监控、地图轨迹追踪';
      case ToolGroup.generation:
        return '生成工具：网页/Markdown 设计稿生成';
      case ToolGroup.trend:
        return '热搜工具：各平台实时热搜榜单';
      case ToolGroup.mcp:
        return 'MCP工具：来自外部 MCP 服务器的动态工具';
    }
  }

  /// 静态工具组名→组的映射（由 tool_registry 填充）
  static ToolGroup? fromString(String s) {
    for (final g in ToolGroup.values) {
      if (g.label == s) return g;
    }
    return null;
  }
}

/// 工具名 → 所属组
class ToolGroupRegistry {
  static final Map<String, ToolGroup> _map = {};

  static void register(String toolName, ToolGroup group) {
    _map[toolName] = group;
  }

  static ToolGroup? groupOf(String toolName) => _map[toolName];

  static Set<String> toolNamesInGroup(ToolGroup group) =>
      _map.entries.where((e) => e.value == group).map((e) => e.key).toSet();

  static Set<String> toolNamesInGroups(Set<ToolGroup> groups) {
    final names = <String>{};
    for (final entry in _map.entries) {
      if (groups.contains(entry.value)) names.add(entry.key);
    }
    return names;
  }

  static Set<ToolGroup> groupsForToolNames(Set<String> names) {
    final groups = <ToolGroup>{};
    for (final name in names) {
      final g = _map[name];
      if (g != null) groups.add(g);
    }
    return groups;
  }

  static List<String> get allToolNames => _map.keys.toList();
}
