import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'memory_cache.dart';
import '../../../core/storage/database_helper.dart';
import '../../../core/api/minimax_client.dart';
import '../../../core/engine/conversation_session.dart';
import '../../../core/saf/saf_client.dart';
import '../../../core/hooks/hook_pipeline.dart';
import '../../chat/data/chat_repository.dart';
import '../../chat/data/context_builder.dart';
import '../../chat/domain/chat_message.dart';
import '../../tools/data/tool_executor.dart';
import '../../settings/data/settings_repository.dart';
import '../domain/user_memory.dart';

final taskSchedulerProvider = StateProvider<TaskScheduler?>((ref) => null);

class TaskScheduler {
  TaskScheduler({MemoryCache? cache}) : _cache = cache ?? MemoryCache.instance;
  final MemoryCache _cache;

  Timer? _nextTimer;
  bool _running = false;
  final Set<String> _firingIds = {};

  void Function(String title, String description, String result)? onTaskResultForUI;
  /// 流式进度回调：message 为累积文本，isComplete 表示是否完成
  void Function(String taskId, String title, String message, bool isComplete)? onTaskStreamUpdate;

  void reschedule() {
    if (!_running) return;
    _nextTimer?.cancel();
    _scheduleNext();
  }

  Future<void> initialize() async {
    _cache.onChange = () {
      reschedule();
    };
    await _cache.load();
  }

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

    if (closestDueMs == null) return;

    final delayMs = closestDueMs - now.millisecondsSinceEpoch;
    _nextTimer?.cancel();

    if (delayMs <= 0) {
      Timer.run(_fireDueTasks);
    } else {
      _nextTimer = Timer(Duration(milliseconds: delayMs), _fireDueTasks);
    }
  }

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

    _scheduleNext();
  }

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

      if (isCatchUp && (taskType == 'scheduled' || taskType == 'countdown')) {
        if (dueTime != null) {
          final overdue = DateTime.now().difference(dueTime);
          if (overdue.inHours >= 24) {
            debugPrint('[TaskScheduler] 任务过期超过24h，跳过: $title');
            row['status'] = 'expired';
            await _cache.updateTask(row);
            return;
          }
        }
      }

      if (taskType == 'recurring') {
        await _handleRecurring(row, intervalSeconds);
      }

      if (taskType != 'recurring') {
        row['status'] = 'inProgress';
        await _cache.updateTask(row);
      }

      debugPrint('[TaskScheduler] ${isCatchUp ? "[追赶]" : ""}触发任务: $title (类型: $taskType)');

      await _executeTask(id, title, desc);
    } catch (e) {
      debugPrint('[TaskScheduler] 任务执行失败: $e');
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

    debugPrint('[TaskScheduler] 启动追赶: 发现 ${missed.length} 个过期任务');

    for (final t in missed) {
      if (!_running) return;
      await _fireTask(t, isCatchUp: true);
    }
  }

  Future<void> _executeTask(String taskId, String title, String desc) async {
    final db = DatabaseHelper();
    final userMsg = _buildTaskUserMessage(title, desc);
    final conversationId = DatabaseHelper.taskConversationId;

    await db.ensureTaskConversation();

    try {
      final settings = SettingsRepository();
      final apiKey = await settings.getActiveApiKey();
      final baseUrl = await settings.getBaseUrl();
      final client = MinimaxClient(apiKey: apiKey, baseUrl: baseUrl);
      final chatRepo = ChatRepository(client: client, db: db);

      // 构建系统提示词
      final taskPrompt = _buildTaskSystemPrompt(title, desc);

      // 加载历史消息作为上下文
      final history = ContextBuilder.buildContext(
        messages: await chatRepo.getMessages(conversationId),
        summary: null,
      );

      // 创建取消令牌
      final cancelToken = CancelToken();

      // 创建工具执行器
      final session = ConversationSession(conversationId: conversationId);
      final safClient = SafClient();
      final hookPipeline = HookPipeline.instance;
      final executor = ToolExecutor(
        settingsRepo: settings,
        safClient: safClient,
        hookPipeline: hookPipeline,
        db: db,
      );

      final userMsgId = 'task_user_${DateTime.now().millisecondsSinceEpoch}';

      // 流式调用 — 与普通对话完全一致
      final stream = chatRepo.sendMessageStreamNative(
        conversationId: conversationId,
        message: userMsg,
        systemPrompt: taskPrompt,
        history: history,
        cancelToken: cancelToken,
        executeTool: (toolName, args) =>
            executor.execute(toolName, args,
              conversationId: conversationId,
              messageId: userMsgId),
        messageId: userMsgId,
        pauseToken: session.pauseToken,
        hookPipeline: hookPipeline,
      );

      final fullResponse = StringBuffer();
      String? lastContent;
      await for (final msg in stream) {
        if (msg.role == MessageRole.assistant && msg.content.isNotEmpty) {
          fullResponse.write(msg.content);
        }
        final currentText = fullResponse.toString();
        if (currentText != lastContent) {
          lastContent = currentText;
          onTaskStreamUpdate?.call(taskId, title, currentText, false);
        }
      }

      var response = fullResponse.toString();
      if (response.isEmpty) {
        response = '（无输出）';
      }

      // sendMessageStreamNative 内部已持久化，不重复写 DB

      final task = _cache.getTask(taskId);
      final taskType = task != null ? _parseValue(task, 'taskType') : '';
      if (taskType != 'recurring') {
        if (task != null) {
          task['status'] = 'completed';
          await _cache.updateTask(task);
        }
      }

      onTaskStreamUpdate?.call(taskId, title, response, true);
      onTaskResultForUI?.call(title, desc, response);
    } catch (e) {
      debugPrint('[TaskScheduler] AI 执行失败: $e');

      final task = _cache.getTask(taskId);
      final taskType = task != null ? _parseValue(task, 'taskType') : '';
      if (taskType != 'recurring') {
        if (task != null) {
          task['status'] = 'failed';
          await _cache.updateTask(task);
        }
      }

      onTaskResultForUI?.call(title, desc, '执行失败: $e');
    }
  }

  String _buildTaskSystemPrompt(String title, String desc) {
    final buf = StringBuffer();
    buf.write('你是一个自动化任务执行助手。你正在执行一个定时触发的任务。\n');
    buf.write('任务目标：$title\n');
    if (desc.isNotEmpty) {
      buf.write('任务详情：$desc\n');
    }
    buf.write('\n请独立完成此任务。你可以使用所有可用的工具来完成任务（浏览器、文件操作、地图等）。');
    buf.write('输出结果时不要输出经纬度数字，用地名/地址/地标描述位置。');
    buf.write('完成后请汇报执行结果。如果无法完成请说明原因。');
    return buf.toString();
  }

  String _buildTaskUserMessage(String title, String desc) {
    final buf = StringBuffer();
    if (title.isNotEmpty) buf.write('【定时任务】$title');
    if (desc.isNotEmpty) {
      if (buf.isNotEmpty) buf.write('\n');
      buf.write('任务说明：$desc');
    }
    buf.write('\n\n请执行此任务，实在完成不了就返回原因。');
    return buf.toString();
  }

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

  Future<void> onTaskChanged(ScheduledTask task) async {
    reschedule();
  }

  Future<void> onTaskDeleted(String taskId) async {
    reschedule();
  }
}