import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// 前台服务：纯保活。不做任务逻辑，只为防止进程被杀。
///
/// 进程存活 → TaskExecutor Timer 持续运行 → 完整 agent 始终可用。
///
/// 保障：
///   1. 前台通知 → 系统降低 oom_adj
///   2. stopWithTask 默认 false → 划掉后服务继续
///   3. autoRunOnBoot → 重启后恢复
///   4. 电池优化豁免 → 国产手机防杀
class ForegroundService {
  static const _channelId = 'agent_alive_channel';

  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: 'Agent 运行中',
        channelDescription: '保持 Agent 后台待命，确保定时任务准时执行',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> start() async {
    if (await FlutterForegroundTask.isRunningService) return;

    final hasPermission = await FlutterForegroundTask.checkNotificationPermission();
    if (hasPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    await FlutterForegroundTask.startService(
      notificationTitle: 'MyMinimax 运行中',
      notificationText: '定时任务和后台执行已就绪',
    );
  }

  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }

  static Future<bool> isRunning() => FlutterForegroundTask.isRunningService;

  static Future<bool> requestBatteryOptimization() =>
      FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();

  static Future<bool> get canIgnoreBatteryOptimization =>
      FlutterForegroundTask.isIgnoringBatteryOptimizations;
}
