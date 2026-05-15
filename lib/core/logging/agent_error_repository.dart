import 'package:uuid/uuid.dart';
import '../storage/database_helper.dart';

/// Structured error log for queryable error tracking across sessions.
class AgentErrorRepository {

  AgentErrorRepository(this._db);
  final DatabaseHelper _db;

  Future<void> logError({
    required String conversationId,
    required String category,
    required String errorMessage,
    String? messageId,
    String? stackTrace,
    bool recoverable = false,
    bool wasRetried = false,
    bool retrySuccess = false,
  }) async {
    await _db.insertAgentError(
      id: const Uuid().v4(),
      conversationId: conversationId,
      messageId: messageId,
      category: category,
      errorMessage: errorMessage,
      stackTrace: stackTrace,
      recoverable: recoverable,
      wasRetried: wasRetried,
      retrySuccess: retrySuccess,
    );
  }

  Future<List<Map<String, dynamic>>> getRecentErrors({
    String? conversationId,
    int limit = 50,
  }) async {
    return _db.getAgentErrors(conversationId: conversationId, limit: limit);
  }

  Future<Map<String, int>> getErrorStats() async {
    return _db.getAgentErrorStats();
  }
}
