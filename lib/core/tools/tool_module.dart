/// 声明式工具模块接口
///
/// 每个模块自描述其工具定义和分组归属。
/// 替代过去 ToolRegistry.init() 中硬编码的工具注册和 _registerGroups() 分组映射。
library;

import 'tool_registry.dart';
import 'tool_groups.dart';

abstract class ToolModule {
  /// 模块唯一标识
  String get name;

  /// 模块提供的工具定义列表
  List<ToolDefinition> get definitions;

  /// toolName → ToolGroup 映射。不在此 map 中的工具默认归入 [ToolGroup.basic]。
  Map<String, ToolGroup> get groupAssignments;

  /// 是否为外部动态工具（MCP、浏览器），需要特殊生命周期管理。
  /// 动态模块可通过 [ToolRegistry.clearDynamicModules] 批量移除后重新注册。
  bool get isDynamic => false;
}
