import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/user_memory.dart';
import 'memory_cache.dart';

class MemoryRepository {

  MemoryRepository({MemoryCache? cache}) : _cache = cache ?? MemoryCache.instance;
  static const _legacyKey = 'user_memory';
  final MemoryCache _cache;
  bool _migrated = false;

  MemoryCache get cache => _cache;

  // ── 初始化 ──

  Future<void> init() async {
    // 首次：从旧 shared_preferences JSON 迁移到 SQLite（在 load 前检查）
    if (!_migrated) {
      await _tryMigrate();
    }
    await _cache.load();
  }

  Future<void> _tryMigrate() async {
    _migrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_legacyKey);
      if (raw != null && raw.isNotEmpty) {
        await _cache.migrateFromJson(raw);
        await prefs.remove(_legacyKey); // 迁移后删除旧数据
      }
    } catch (_) {}
  }

  // ── 加载 ──

  Future<UserMemory> loadMemory() async {
    await _cache.load();
    return _toUserMemory();
  }

  UserMemory _toUserMemory() {
    return UserMemory(
      birthday: _cache.get('static', 'birthday') ?? '',
      gender: _cache.get('static', 'gender') ?? '',
      nativeLanguage: _cache.get('static', 'nativeLanguage') ?? '',
      knowledgeBackground: _cache.get('dynamic', 'knowledgeBackground') ?? '',
      currentIdentity: _cache.get('dynamic', 'currentIdentity') ?? '',
      location: _cache.get('dynamic', 'location') ?? '',
      usingLanguage: _cache.get('dynamic', 'usingLanguage') ?? '',
      shortTermGoals: _cache.get('dynamic', 'shortTermGoals') ?? '',
      shortTermInterests: _cache.get('dynamic', 'shortTermInterests') ?? '',
      behaviorHabits: _cache.get('dynamic', 'behaviorHabits') ?? '',
      namePreference: _cache.get('dynamic', 'namePreference') ?? '',
      answerStyle: _cache.get('preference', 'answerStyle') ?? '',
      detailLevel: _cache.get('preference', 'detailLevel') ?? '',
      formatPreference: _cache.get('preference', 'formatPreference') ?? '',
      visualPreference: _cache.get('preference', 'visualPreference') ?? '',
      communicationRules: _cache.get('notice', 'communicationRules') ?? '',
      prohibitedItems: _cache.get('notice', 'prohibitedItems') ?? '',
      otherRequirements: _cache.get('notice', 'otherRequirements') ?? '',
      tasks: _cache.getTasks().map(_toScheduledTask).toList(),
    );
  }

  ScheduledTask _toScheduledTask(Map<String, dynamic> row) {
    // New tasks table has typed columns; also handle old user_memory format
    String title = (row['title'] as String?) ?? '';
    String description = (row['description'] as String?) ?? '';
    String taskTypeStr = (row['task_type'] as String?) ?? 'scheduled';
    int intervalSeconds = (row['interval_seconds'] as int?) ?? 0;

    // Fallback: parse old JSON value format
    if (title.isEmpty && row['value'] != null) {
      try {
        final v = row['value'] as String;
        final parsed = jsonDecode(v) as Map<String, dynamic>;
        title = parsed['title'] as String? ?? '';
        description = parsed['description'] as String? ?? '';
        taskTypeStr = parsed['taskType'] as String? ?? 'scheduled';
        intervalSeconds = parsed['intervalSeconds'] as int? ?? 0;
      } catch (_) {}
    }

    TaskType taskType;
    try {
      taskType = TaskType.values.firstWhere((t) => t.name == taskTypeStr);
    } catch (_) {
      taskType = TaskType.scheduled;
    }

    TaskStatus status;
    switch (row['status'] as String?) {
      case 'inProgress':
        status = TaskStatus.inProgress;
      case 'completed':
        status = TaskStatus.completed;
      case 'expired':
        status = TaskStatus.expired;
      default:
        status = TaskStatus.pending;
    }

    final createdAtMs = row['created_at'] as int?;
    final dueMs = row['due_time'] as int?;

    return ScheduledTask(
      id: row['id'] as String? ?? '',
      title: title,
      description: description,
      dueDate: dueMs != null ? DateTime.fromMillisecondsSinceEpoch(dueMs) : null,
      status: status,
      taskType: taskType,
      intervalSeconds: intervalSeconds,
      createdAt: createdAtMs != null ? DateTime.fromMillisecondsSinceEpoch(createdAtMs) : DateTime.now(),
    );
  }

  // ── 保存单字段（O(1) 增量更新） ──

  Future<void> setField(String type, String key, String value) async {
    await _cache.set(type, key, value);
  }

  // ── 构建系统提示词 ──

  Future<String> buildMemoryPrompt() async {
    await _cache.load();
    return _cache.toSystemPrompt();
  }

  // ── 任务 CRUD ──

  Future<ScheduledTask> addTask(ScheduledTask task) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final row = _taskToRow(task, now);
    await _cache.addTask(row);
    return _toScheduledTask(row);
  }

  Future<ScheduledTask> updateTask(ScheduledTask task) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final row = _taskToRow(task, now);
    await _cache.updateTask(row);
    return _toScheduledTask(row);
  }

  Future<void> deleteTask(String taskId) async {
    await _cache.deleteTask(taskId);
  }

  Map<String, dynamic> _taskToRow(ScheduledTask task, int now) {
    return {
      'id': task.id,
      'title': task.title,
      'description': task.description,
      'task_type': task.taskType.name,
      'interval_seconds': task.intervalSeconds,
      'due_time': task.dueDate?.millisecondsSinceEpoch,
      'status': task.status.name,
      'created_at': task.createdAt.millisecondsSinceEpoch,
      'updated_at': now,
      'is_active': 1,
    };
  }

  Future<void> expireOverdueTasks() async {
    await _cache.expireOverdueTasks();
  }
}
