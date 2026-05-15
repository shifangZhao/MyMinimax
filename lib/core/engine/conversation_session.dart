import 'dart:convert';
import 'package:dio/dio.dart';
import '../../features/chat/domain/chat_message.dart';
import '../../features/chat/data/context_manager.dart';
import '../state/session_state_machine.dart';

class AttachmentData {
  AttachmentData({
    required this.type,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    this.base64,
    this.extractedText,
  });
  final String type;
  final String? base64;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final String? extractedText;
  Map<String, dynamic> toJson() => {
    'type': type,
    'fileName': fileName,
    'mimeType': mimeType,
    'fileSize': fileSize,
    'base64': base64,
    'extractedText': extractedText,
  };
  factory AttachmentData.fromJson(Map<String, dynamic> json) => AttachmentData(
    type: json['type'] as String,
    fileName: json['fileName'] as String,
    mimeType: json['mimeType'] as String,
    fileSize: json['fileSize'] as int,
    base64: json['base64'] as String?,
    extractedText: json['extractedText'] as String?,
  );
}

class InputState {
  InputState({this.text = '', List<AttachmentData>? attachments, this.attachmentsExpanded = true})
      : attachments = attachments ?? [];
  String text;
  List<AttachmentData> attachments;
  bool attachmentsExpanded;
  void clear() {
    text = '';
    attachments.clear();
    attachmentsExpanded = true;
  }
}

/// 暂停令牌 - 控制智能体是否接收信息
/// 当 isPaused=true 时，sendMessageStreamNative 会阻断所有 yield
/// 只有用户发送新消息时才会 resume
class PauseToken {
  PauseToken();

  bool _isPaused = false;
  bool get isPaused => _isPaused;

  /// 暂停 - 阻断所有信息传给智能体
  void pause() {
    _isPaused = true;
  }

  /// 恢复 - 只有用户发送新消息时调用
  void resume() {
    _isPaused = false;
  }
}

class LogEntry {

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
  });
  final DateTime timestamp;
  final String level;
  final String message;
  final String? error;
  final String? stackTrace;
}

class OptimizeData {

  const OptimizeData({required this.optimized, required this.tips});
  final String optimized;
  final String tips;
}

class ConversationSession {

  ConversationSession({required this.conversationId});
  final String conversationId;

  // ── Messages ──
  List<ChatMessage> messages = [];
  List<ChatMessage> get visibleMessages =>
      messages.where((m) => m.role != MessageRole.tool).toList();

  // ── Generation state ──
  bool isLoading = false;
  bool isGenerating = false;
  /// 独立于 cancelToken 的生成活跃标志。只由生成生命周期设置/清除，
  /// 不会被 _stopGenerating 或 _loadMessages 等副作用污染。
  bool generationActive = false;
  CancelToken? cancelToken;
  StreamState streamState = StreamState.idle;
  bool streamInterrupted = false;
  final Map<String, String> streamingContent = {};
  Map<String, List<String>> dependencies = {};
  String? lastTruncatedMessageId;
  String? lastTruncatedContent;
  bool isTruncated = false;
  DateTime? lastPartialSave;

  void recordDependency(String parentId, String childId) {}
  void invalidateDependentMessages(String baseMessageId) {}
  void onMessageCompleted(String messageId) {}
  void transitionState(StreamState state, void Function(String, String, [Object?, StackTrace?]) addLog) {}

  // ── Pause token — 暂停令牌，阻断所有信息传给智能体 ──
  final pauseToken = PauseToken();

  // ── Summary / Context ──
  String summary = '';
  String? originalQuestion;
  final ContextManager contextManager = ContextManager();

  // ── Session state machine ──
  final SessionStateMachine sessionStateMachine = SessionStateMachine();

  // ── Lens / Skill state ──
  Set<String> activeLenses = {};
  int lensDecayCounter = 0;
  Set<String> activeSkills = {};
  Map<String, int> skillDecayCounters = {};
  Set<String> lastInjectedSkills = {};
  Map<String, int> skillUsageThisTurn = {};
  bool suppressUserSave = false;
  OptimizeData? optimizeResult;

  // ── Logs ──
  final List<LogEntry> logs = [];

  // ── TTS (per-session queue, but playback is shared) ──
  final List<String> ttsQueue = [];
  bool ttsProcessing = false;
  String lastTtsText = '';

  // ── Input state ──
  final InputState inputState = InputState();

  // ── UI scroll ──
  bool userScrolledAway = false;

  // ── Token Plan ──
  String? tokenPlanErrorMessage;

  // ── Helpers ──

  void dispose() {
    generationActive = false;
    cancelToken?.cancel();
    cancelToken = null;
    sessionStateMachine.dispose();
  }
}
