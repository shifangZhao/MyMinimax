import Flutter
import UIKit
import BackgroundTasks

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    private static let taskIdentifier = "com.myminimax.taskExecution"
    private var tappedTaskId: String?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Register BGTaskScheduler
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
                self.handleBackgroundTask(task as! BGAppRefreshTask)
            }
        }

        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        UNUserNotificationCenter.current().delegate = self

        // Check if launched from notification tap
        if let launchOptions = launchOptions,
           let notification = launchOptions[.remoteNotification] as? [String: Any] {
            // Handle if launched from notification (app was killed)
        }

        // Set up Flutter channels (wait for engine)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.setupChannels()
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    }

    // ═══════════════════════════════════════════
    // Flutter MethodChannel & EventChannel
    // ═══════════════════════════════════════════

    private func setupChannels() {
        guard let controller = window?.rootViewController as? FlutterViewController else { return }
        let messenger = controller.binaryMessenger

        let eventChannel = FlutterEventChannel(name: "com.myminimax/task_events", binaryMessenger: messenger)
        eventChannel.setStreamHandler(TaskEventStreamHandler())

        let methodChannel = FlutterMethodChannel(name: "com.myminimax/alarm", binaryMessenger: messenger)
        methodChannel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "executeTask":
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "BAD_ARGS", message: nil, details: nil))
                    return
                }
                let taskId = args["taskId"] as? String ?? ""
                let title = args["title"] as? String ?? ""
                let description = args["description"] as? String ?? ""
                let systemPrompt = args["systemPrompt"] as? String ?? ""

                AgentTaskRunner.shared.execute(
                    taskId: taskId,
                    title: title,
                    description: description,
                    systemPrompt: systemPrompt
                )
                result(true)

            case "getTappedTaskId":
                let id = self?.tappedTaskId
                self?.tappedTaskId = nil
                result(id)

            case "syncAlarms":
                let args = call.arguments as? [String: Any]
                let alarmsJson = args?["alarms"] as? String
                self?.scheduleNotifications(from: alarmsJson)
                self?.scheduleNextBackgroundTask(from: alarmsJson)
                result(true)

            case "canScheduleExactAlarms":
                result(false)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // ═══════════════════════════════════════════
    // Local Notifications (iOS precise-time trigger)
    // ═══════════════════════════════════════════

    private func scheduleNotifications(from alarmsJson: String?) {
        let center = UNUserNotificationCenter.current()
        let defaults = UserDefaults.standard

        // 同步取消旧通知（用上次存储的 ID 列表，无竞态）
        let oldIds = defaults.stringArray(forKey: "task_alarm_scheduled_ids") ?? []
        center.removePendingNotificationRequests(withIdentifiers: oldIds)

        guard let json = alarmsJson,
              let data = json.data(using: .utf8),
              let alarms = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            defaults.set([], forKey: "task_alarm_scheduled_ids")
            return
        }

        var newIds: [String] = []

        for alarm in alarms {
            guard let taskId = alarm["taskId"] as? String,
                  let title = alarm["title"] as? String,
                  let dueMs = alarm["dueMs"] as? Int64,
                  dueMs > Int64(Date().timeIntervalSince1970 * 1000) else { continue }

            let dueDate = Date(timeIntervalSince1970: Double(dueMs) / 1000.0)
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: dueDate
            )

            let content = UNMutableNotificationContent()
            content.title = "定时任务到期"
            content.body = title
            content.sound = .default
            content.userInfo = [
                "taskId": taskId,
                "taskTitle": title,
                "type": "task_alarm"
            ]

            let identifier = "task_alarm_\(taskId)"
            newIds.append(identifier)

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )
            center.add(request) { error in
                if let error = error {
                    print("[AppDelegate] Notification schedule failed: \(error)")
                }
            }
        }

        // 存储新 ID 列表，供下次同步清理
        defaults.set(newIds, forKey: "task_alarm_scheduled_ids")
    }

    // ═══════════════════════════════════════════
    // UNUserNotificationCenterDelegate
    // ═══════════════════════════════════════════

    // Notification tapped while app in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Notification tapped (any state)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if userInfo["type"] as? String == "task_alarm",
           let taskId = userInfo["taskId"] as? String {
            tappedTaskId = taskId
        }
        completionHandler()
    }

    // ═══════════════════════════════════════════
    // BGTaskScheduler
    // ═══════════════════════════════════════════

    private func scheduleNextBackgroundTask(from alarmsJson: String?) {
        guard #available(iOS 13.0, *) else { return }

        var earliestDueMs: Int64 = Int64.max

        if let json = alarmsJson,
           let data = json.data(using: .utf8),
           let alarms = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for alarm in alarms {
                if let dueMs = alarm["dueMs"] as? Int64, dueMs < earliestDueMs {
                    earliestDueMs = dueMs
                }
            }
        }

        let earliestDate: Date
        if earliestDueMs < Int64.max {
            let dueDate = Date(timeIntervalSince1970: Double(earliestDueMs) / 1000.0)
            earliestDate = dueDate.addingTimeInterval(-30)
            if earliestDate < Date() { earliestDate = Date().addingTimeInterval(60) }
        } else {
            earliestDate = Date().addingTimeInterval(15 * 60)
        }

        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = earliestDate

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[AppDelegate] BGTask submit failed: \(error)")
        }
    }

    private func handleBackgroundTask(_ task: BGAppRefreshTask) {
        let alarmsJson = UserDefaults.standard.string(forKey: "task_alarms_json")
        scheduleNextBackgroundTask(from: alarmsJson)

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        AgentTaskRunner.shared.executeDueTasks()

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            task.setTaskCompleted(success: true)
        }
    }
}

// ═══════════════════════════════════════════
// EventChannel StreamHandler
// ═══════════════════════════════════════════

class TaskEventStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        TaskResultBridge.onResult = { taskId, result in
            events(["taskId": taskId, "result": result])
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        TaskResultBridge.onResult = nil
        return nil
    }
}
