/// Shared type definitions for the orchestrator module.

/// Callback to execute a tool — matches the signature injected from chat_page.
typedef ExecuteToolFn = Future<Map<String, dynamic>> Function(
    String toolName, Map<String, dynamic> args);
