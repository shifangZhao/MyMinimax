import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myminimax/core/tools/tool_registry.dart';
import 'package:myminimax/core/hooks/hook_pipeline.dart';
import 'package:myminimax/core/mcp/mcp_registry.dart';
import 'package:myminimax/core/skills/skill.dart';

/// 工具注册中心（可通过 overrideWith 在测试中替换）
final toolRegistryProvider = Provider<ToolRegistry>((ref) => ToolRegistry.instance);

/// Hook 中间件管道
final hookPipelineProvider = Provider<HookPipeline>((ref) => HookPipeline.instance);

/// MCP 服务器注册中心
final mcpRegistryProvider = Provider<McpRegistry>((ref) => McpRegistry.instance);

/// 技能注册中心
final skillRegistryProvider = Provider<SkillRegistry>((ref) => SkillRegistry.instance);
