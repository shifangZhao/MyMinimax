/// 生命周期 Hook 中间件管道
///
/// 支持优先级排序、异步执行、三级 profile（minimal/standard/strict）。
library;

import 'dart:async';

/// Hook 事件类型
enum HookEvent {
  beforeToolUse,
  afterToolUse,
  onToolFailure,
  beforeSend,
  afterReceive,
  onSessionStart,
  onSessionEnd,
  beforeCompaction,
}

/// Hook 上下文，携带事件相关数据
class HookContext {

  HookContext(this.event, this.data);
  final HookEvent event;
  final Map<String, dynamic> data;

  /// 工厂：从工具调用参数构建 HookContext。
  factory HookContext.forToolUse({
    required String toolName,
    required Map<String, dynamic> params,
    String? conversationId,
    String? workspace,
    Map<String, dynamic>? riskAssessment,
  }) {
    return HookContext(HookEvent.beforeToolUse, {
      'toolName': toolName,
      'params': params,
      if (conversationId != null) 'conversationId': conversationId,
      if (workspace != null) 'workspace': workspace,
      if (riskAssessment != null) 'riskAssessment': riskAssessment,
    });
  }

  // 便捷访问器
  String? get toolName => data['toolName'] as String?;
  Map<String, dynamic>? get toolParams =>
      data['params'] != null ? Map<String, dynamic>.from(data['params'] as Map) : null;
  bool get isBlocked => data['blocked'] == true;
  String? get blockReason => data['blockReason'] as String?;
  String? get conversationId => data['conversationId'] as String?;
  String? get error => data['error'] as String?;
}

/// Hook 处理函数类型
typedef HookHandler = Future<void> Function(HookContext context);

/// 已注册的 Hook
class RegisteredHook {

  RegisteredHook({
    required this.handler,
    required this.name, this.priority = 100,
    this.async = false,
  });
  final HookHandler handler;
  final int priority; // 越小越先执行
  final bool async; // true = 后台执行，不阻塞
  final String name;
}

/// Hook Profile（决定哪些 hook 生效）
enum HookProfile { minimal, standard, strict }

class HookPipeline {
  HookPipeline._();

  /// 创建空管道（用于 forProfile 过滤和测试）
  HookPipeline._empty();
  HookPipeline.empty();

  static final HookPipeline _defaultInstance = HookPipeline._();
  static HookPipeline? _override;

  /// 获取当前实例。测试中可通过 [setTestInstance] 覆盖。
  static HookPipeline get instance => _override ?? _defaultInstance;

  /// 测试用：注入实例。用 [reset] 恢复默认。
  static void setTestInstance(HookPipeline v) => _override = v;
  static void reset() => _override = null;

  final Map<HookEvent, List<RegisteredHook>> _hooks = {};

  void register(
    HookEvent event,
    HookHandler handler, {
    required String name, int priority = 100,
    bool async = false,
  }) {
    _hooks.putIfAbsent(event, () => []);
    _hooks[event]!.add(RegisteredHook(
      handler: handler,
      priority: priority,
      async: async,
      name: name,
    ));
    _hooks[event]!.sort((a, b) => a.priority.compareTo(b.priority));
  }

  void unregister(String name) {
    for (final list in _hooks.values) {
      list.removeWhere((h) => h.name == name);
    }
  }

  /// 执行某事件的所有注册 handler
  ///
  /// 按优先级排序执行。async handler 通过 unawaited 触发不阻塞。
  /// 单个 handler 异常不影响后续 handler。
  Future<void> execute(HookEvent event, HookContext context) async {
    final handlers = _hooks[event];
    if (handlers == null || handlers.isEmpty) return;

    for (final hook in handlers) {
      if (hook.async) {
        // 不阻塞主流程
        _runAsync(hook, context);
      } else {
        try {
          await hook.handler(context);
        } catch (e) {
          print('[hook] error: \$e');
          // 单个 handler 失败不影响后续
          context.data['_hookError_${hook.name}'] = e.toString();
        }
      }
    }
  }

  void _runAsync(RegisteredHook hook, HookContext context) {
    hook.handler(context).catchError((e) {
      context.data['_hookError_${hook.name}'] = e.toString();
    });
  }

  /// 根据 Profile 创建子管道
  ///
  /// minimal: 仅 sessionStart/sessionEnd
  /// standard: + safety/logging/MCP health（默认）
  /// strict: + compaction warning
  HookPipeline forProfile(HookProfile profile) {
    final filtered = HookPipeline._empty();
    final allowedPrefixes = _profilePrefixes(profile);

    for (final entry in _hooks.entries) {
      for (final hook in entry.value) {
        if (allowedPrefixes.any((p) => hook.name.startsWith(p))) {
          filtered.register(
            entry.key,
            hook.handler,
            priority: hook.priority,
            async: hook.async,
            name: hook.name,
          );
        }
      }
    }
    return filtered;
  }

  Set<String> _profilePrefixes(HookProfile profile) {
    switch (profile) {
      case HookProfile.minimal:
        return {'session'};
      case HookProfile.standard:
        return {'safety', 'logging', 'mcp', 'retry', 'session', 'compaction', 'browser', 'pii'};
      case HookProfile.strict:
        return {'safety', 'logging', 'mcp', 'retry', 'session', 'compaction', 'browser', 'pii'};
    }
  }

  /// 获取注册在某事件上的所有 hook 名称
  List<String> getRegisteredNames(HookEvent event) =>
      _hooks[event]?.map((h) => h.name).toList() ?? const [];
}
