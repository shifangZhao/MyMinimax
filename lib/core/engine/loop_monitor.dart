import 'tool_loop_detector.dart';

/// Result of a loop/health check after a tool-execution round.
class LoopCheckResult {

  const LoopCheckResult({this.softNudge, this.hardStop});
  final String? softNudge;
  final String? hardStop;

  bool get hasIssue => softNudge != null || hardStop != null;
}

/// Wraps [ToolLoopDetector] with a simplified interface for the agent
/// orchestrator. Call [check] after each tool-execution round.
class LoopMonitor {

  LoopMonitor({int windowSize = 30})
      : _detector = ToolLoopDetector(windowSize: windowSize);
  final ToolLoopDetector _detector;

  /// Expose the underlying detector for [ToolExecutionHandler] to record into.
  ToolLoopDetector get detector => _detector;

  /// Record a completed tool call (delegates to detector).
  void record(String name, Map<String, dynamic> args, String result) {
    _detector.record(name, args, result);
  }

  /// Call after all tools in a round have been executed and recorded.
  LoopCheckResult check() {
    final nudge = _detector.check();
    if (nudge != null) {
      if (_detector.isSeverelyLooping) {
        return const LoopCheckResult(
          hardStop: '⚠️ Agent 严重循环，已自动中断。请换个方式提问。',
        );
      }
      return LoopCheckResult(softNudge: nudge);
    }
    return const LoopCheckResult();
  }

  void reset() => _detector.reset();
}
