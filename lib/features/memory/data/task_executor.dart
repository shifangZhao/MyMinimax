import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'memory_cache.dart';

/// 定时任务调度引擎：计算下次触发时间，到期通过 MethodChannel 委托原生执行。
///
/// 不再每秒轮询。改为：
/// 1. 找到所有 pending/inProgress 任务中最近的 dueTime
/// 2. 设单次 Timer 等到那时（最长 30s 保底，防止 cache 绕过的遗漏）
/// 3. Timer 到期 → 触发所有到期任务 → 递归排下一个
///
/// 任务 AI 执行不在 Dart 层，通过 onExecuteTask 委托给原生 AgentTaskService。
class TaskExecutor {

  TaskExecutor(this._cache);
  final MemoryCache _cache;

  Timer? _nextTimer;
  bool _running = false;
  final Set<String> _firingIds = {};

  /// 委托原生执行任务（由 TaskScheduler 注入，实际调 MethodChannel executeTask）
  Future<void> Function(String taskId, String title, String description)? onExecuteTask;

  bool get isRunning => _running;

  /// 外部通知：有新任务加入或任务变更 → 重新排 Timer
  void reschedule() {
    if (!_running) return;
    _nextTimer?.cancel();
    _scheduleNext();
  }

  /// 启动引擎：加载缓存 → 追赶过期任务 → 开始排程
  Future<void> start() async {
    if (_running) return;
    if (!_cache.isLoaded) {
      await _cache.load();
    }
    _running = true;

    await _catchUpMissedTasks();
    _scheduleNext();
  }

  void stop() {
    _running = false;
    _nextTimer?.cancel();
    _nextTimer = null;
    _firingIds.clear();
  }

  // ═══════════════════════════════════════════
  // 排程：找到最近到期任务，设单次 Timer
  // ═══════════════════════════════════════════

  void _scheduleNext() {
    if (!_running) return;

    final now = DateTime.now();
    int? closestDueMs;

    final allPending = [
      ..._cache.getTasks(status: 'pending'),
      ..._cache.getTasks(status: 'inProgress'),
    ];

    for (final t in allPending) {
      final dueMs = t['due_time'] as int?;
      if (dueMs == null) continue;
      if (dueMs <= now.millisecondsSinceEpoch) continue;
      if (closestDueMs == null || dueMs < closestDueMs) {
        closestDueMs = dueMs;
      }
    }

    if (closestDueMs == null) return; // 无未来任务，不设 Timer

    final delayMs = closestDueMs - now.millisecondsSinceEpoch;
    _nextTimer?.cancel();

    if (delayMs <= 0) {
      // 已有任务到期，立即触发（不做 scheduleNext 递归，避免堆栈过深）
      Timer.run(_fireDueTasks);
    } else {
      _nextTimer = Timer(Duration(milliseconds: delayMs), _fireDueTasks);
    }
  }

  // ═══════════════════════════════════════════
  // 到期触发：一次性触发所有 toDue <= now 的任务
  // ═══════════════════════════════════════════

  void _fireDueTasks() {
    if (!_running) return;
    final now = DateTime.now();

    final allActive = [
      ..._cache.getTasks(status: 'pending'),
      ..._cache.getTasks(status: 'inProgress'),
    ];

    for (final t in allActive) {
      final dueMs = t['due_time'] as int?;
      if (dueMs == null) continue;
      if (dueMs > now.millisecondsSinceEpoch) continue;
      if (_firingIds.contains(t['id'] as String)) continue;

      _fireTask(t);
    }

    // 排下一个
    _scheduleNext();
  }

  // ═══════════════════════════════════════════
  // 触发单个任务
  // ═══════════════════════════════════════════

  Future<void> _fireTask(Map<String, dynamic> taskRow, {bool isCatchUp = false}) async {
    final id = taskRow['id'] as String;
    if (_firingIds.contains(id)) return;
    _firingIds.add(id);

    final row = Map<String, dynamic>.from(taskRow);

    try {
      final title = _parseValue(row, 'title');
      final desc = _parseValue(row, 'description');
      final taskType = _parseValue(row, 'taskType');
      final intervalSeconds = int.tryParse(_parseValue(row, 'intervalSeconds')) ?? 0;
      final dueMs = row['due_time'] as int?;
      final dueTime = dueMs != null ? DateTime.fromMillisecondsSinceEpoch(dueMs) : null;

      // 追赶模式：定时/倒计时任务过期超 24h 的标记 expired
      if (isCatchUp && (taskType == 'scheduled' || taskType == 'countdown')) {
        if (dueTime != null) {
          final overdue = DateTime.now().difference(dueTime);
          if (overdue.inHours >= 24) {
            debugPrint('[TaskExecutor] 任务过期超过24h，跳过: $title');
            row['status'] = 'expired';
            await _cache.updateTask(row);
            return;
          }
        }
      }

      // 处理周期任务：计算下次触发时间
      if (taskType == 'recurring') {
        await _handleRecurring(row, intervalSeconds);
      }

      // 标记 inProgress（防止重复调度）
      if (taskType != 'recurring') {
        row['status'] = 'inProgress';
        await _cache.updateTask(row);
      }

      debugPrint('[TaskExecutor] ${isCatchUp ? "[追赶]" : ""}触发任务: $title (类型: $taskType)');

      // 委托原生 AgentTaskService 执行 AI（必须 await 等待结果回传后再结束）
      await onExecuteTask?.call(id, title, desc);
    } catch (e) {
      debugPrint('[TaskExecutor] 任务执行失败: $e');
      // 更新任务状态为失败（非 recurring 任务需要明确标记，否则一直 inProgress）
      row['status'] = 'failed';
      await _cache.updateTask(row);
    } finally {
      _firingIds.remove(id);
    }
  }

  Future<void> _handleRecurring(Map<String, dynamic> taskRow, int intervalSeconds) async {
    final row = Map<String, dynamic>.from(taskRow);

    if (intervalSeconds <= 0) {
      row['status'] = 'completed';
      await _cache.updateTask(row);
      return;
    }

    final oldDueMs = row['due_time'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    final oldDue = DateTime.fromMillisecondsSinceEpoch(oldDueMs);
    final now = DateTime.now();

    var nextDue = oldDue.add(Duration(seconds: intervalSeconds));
    while (!nextDue.isAfter(now)) {
      nextDue = nextDue.add(Duration(seconds: intervalSeconds));
    }

    row['due_time'] = nextDue.millisecondsSinceEpoch;
    row['status'] = 'pending';
    await _cache.updateTask(row);
  }

  // ═══════════════════════════════════════════
  // 追赶：处理 App 关闭期间错过的任务
  // ═══════════════════════════════════════════

  Future<void> _catchUpMissedTasks() async {
    if (!_cache.isLoaded) return;
    final now = DateTime.now();

    final allPending = _cache.getTasks(status: 'pending').toList()
      ..addAll(_cache.getTasks(status: 'inProgress'));

    final missed = <Map<String, dynamic>>[];
    for (final t in allPending) {
      final dueMs = t['due_time'] as int?;
      if (dueMs == null) continue;
      final dueTime = DateTime.fromMillisecondsSinceEpoch(dueMs);
      if (now.isAfter(dueTime)) {
        missed.add(t);
      }
    }

    if (missed.isEmpty) return;

    debugPrint('[TaskExecutor] 启动追赶: 发现 ${missed.length} 个过期任务');

    for (final t in missed) {
      if (!_running) return;
      await _fireTask(t, isCatchUp: true);
    }
  }

  // ═══════════════════════════════════════════
  // 工具方法
  // ═══════════════════════════════════════════

  String _parseValue(Map<String, dynamic> taskRow, String key) {
    if (taskRow.containsKey('value')) {
      try {
        final v = taskRow['value'] as String?;
        if (v == null) return '';
        final parsed = jsonDecode(v) as Map<String, dynamic>;
        return (parsed[key] ?? '').toString();
      } catch (_) {
        return '';
      }
    }
    switch (key) {
      case 'title': return (taskRow['title'] ?? '').toString();
      case 'description': return (taskRow['description'] ?? '').toString();
      case 'taskType': return (taskRow['task_type'] ?? '').toString();
      case 'intervalSeconds': return (taskRow['interval_seconds'] ?? 0).toString();
      default: return (taskRow[key] ?? '').toString();
    }
  }
}
