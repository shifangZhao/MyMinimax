import Foundation
import UserNotifications

/// Port of Android's AgentTaskService to iOS.
/// Executes AI tasks via MiniMax API in a background thread.
/// Results are saved to UserDefaults for Dart to sync.
class AgentTaskRunner {
    static let shared = AgentTaskRunner()

    private init() {}

    // ═══════════════════════════════════════════
    // Public API
    // ═══════════════════════════════════════════

    /// Execute a task (called from MethodChannel when app is in foreground)
    func execute(taskId: String, title: String, description: String, systemPrompt: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = self?.runTask(taskId: taskId, title: title, description: description, systemPrompt: systemPrompt) ?? "执行失败"
            self?.saveResult(taskId: taskId, title: title, result: result)
        }
    }

    /// Execute all due tasks from saved alarm list (called from BGTaskScheduler)
    func executeDueTasks() {
        let alarms = readAlarms()
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        for alarm in alarms {
            guard let taskId = alarm["taskId"] as? String,
                  let title = alarm["title"] as? String,
                  let dueMs = alarm["dueMs"] as? Int64,
                  dueMs <= now else { continue }

            let context = readTaskContext(taskId: taskId)
            let desc = context["taskDesc"] as? String ?? ""
            let prompt = context["systemPrompt"] as? String ?? ""

            DispatchQueue.global(qos: .utility).async { [weak self] in
                let result = self?.runTask(taskId: taskId, title: title, description: desc, systemPrompt: prompt) ?? "执行失败"
                self?.saveResult(taskId: taskId, title: title, result: result)
            }
        }
    }

    // ═══════════════════════════════════════════
    // Core execution
    // ═══════════════════════════════════════════

    private func runTask(taskId: String, title: String, description: String, systemPrompt: String) -> String {
        // 1. Read API config from UserDefaults (shared_preferences on iOS)
        let defaults = UserDefaults.standard
        let apiKey = defaults.string(forKey: "flutter.minimax_api_key") ?? ""
        let baseUrl = defaults.string(forKey: "flutter.minimax_base_url") ?? "https://api.minimaxi.com"
        let model = defaults.string(forKey: "flutter.minimax_model") ?? "MiniMax-M2.7"

        guard !apiKey.isEmpty else { return "API Key 未配置" }

        // 2. Build messages
        var messages: [[String: String]] = []
        if !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }

        var userContent = "【定时任务】\(title)"
        if !description.isEmpty {
            userContent += "\n任务说明：\(description)"
        }
        userContent += "\n\n请执行此任务。"
        messages.append(["role": "user", "content": userContent])

        // 3. Build request body
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false,
            "temperature": 0.7,
            "max_tokens": 4096
        ]

        guard let url = URL(string: "\(baseUrl)/v1/text/chatcompletion"),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return "请求构建失败"
        }

        // 4. HTTP POST (sync on background thread)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = 120

        let semaphore = DispatchSemaphore(value: 0)
        var resultText = "执行失败: 无响应"

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error = error {
                resultText = "网络错误: \(error.localizedDescription)"
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                resultText = "无效响应"
                return
            }

            guard let data = data,
                  let rawText = String(data: data, encoding: .utf8) else {
                resultText = "无法读取响应"
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                resultText = "API 错误 (\(httpResponse.statusCode)): \(String(rawText.prefix(200)))"
                return
            }

            // 5. Parse response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String, !content.isEmpty {
                resultText = content
            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let reply = json["reply"] as? String, !reply.isEmpty {
                resultText = reply
            } else {
                resultText = String(rawText.prefix(500))
            }
        }.resume()

        semaphore.wait()
        return resultText
    }

    // ═══════════════════════════════════════════
    // Persistence
    // ═══════════════════════════════════════════

    private func saveResult(taskId: String, title: String, result: String) {
        let defaults = UserDefaults.standard

        // Save to agent_results array (for Dart sync)
        var results = (defaults.array(forKey: "agent_results") as? [[String: Any]]) ?? []
        let entry: [String: Any] = [
            "type": "task_execution",
            "taskId": taskId,
            "taskTitle": title,
            "userMessage": "执行定时任务: \(title)",
            "aiResponse": result,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        results.append(entry)
        if results.count > 50 { results.removeFirst(results.count - 50) }
        defaults.set(results, forKey: "agent_results")

        // Cancel the scheduled alarm notification (already executed)
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["task_alarm_\(taskId)"]
        )

        // Try to relay result to Dart via MethodChannel (handled by AppDelegate)
        TaskResultBridge.post(taskId: taskId, result: result)

        // Show result notification
        showNotification(title: title, body: result)
    }

    private func readAlarms() -> [[String: Any]] {
        let defaults = UserDefaults.standard
        guard let json = defaults.string(forKey: "task_alarms_json"),
              let data = json.data(using: .utf8),
              let alarms = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return alarms
    }

    private func readTaskContext(taskId: String) -> [String: Any] {
        let defaults = UserDefaults.standard
        guard let json = defaults.string(forKey: "task_context_\(taskId)"),
              let data = json.data(using: .utf8),
              let context = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return context
    }

    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Agent: \(title)"
        content.body = String(body.prefix(200))
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "task_\(Int64(Date().timeIntervalSince1970 * 1000))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

/// Bridge for TaskResultRelay (cross-platform result relay).
/// Holds a closure that AppDelegate sets to invoke MethodChannel back to Dart.
struct TaskResultBridge {
    static var onResult: ((String, String) -> Void)?

    static func post(taskId: String, result: String) {
        DispatchQueue.main.async {
            onResult?(taskId, result)
        }
    }
}
