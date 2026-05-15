import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/engine/conversation_session.dart';
import '../../../core/phone/floating_chat_client.dart';
import '../../../core/share/share_receiver.dart';
import '../../../core/browser/browser_state.dart';
import '../../browser/presentation/browser_panel.dart';
import '../../files/presentation/file_tree_modal.dart';
import '../../../app/app.dart';
import '../../../shared/widgets/pixel_icon_button.dart';
import '../../../shared/widgets/pixel_app_bar.dart';
import '../../../shared/widgets/chat_bubble.dart';
import '../../../shared/widgets/pixel_text_field.dart';
import '../../../shared/widgets/message_action_sheet.dart';
import '../../../shared/utils/responsive.dart';
import '../../../shared/utils/file_utils.dart';
import '../../../core/api/minimax_client.dart';
import '../../../core/persona/persona_registry.dart';
import '../../../core/skills/skill.dart';
import '../../memory/data/memory_cache.dart';
import '../../memory/data/memory_consolidator.dart';
import '../../memory/data/task_scheduler.dart';
import '../../memory/presentation/task_panel.dart';
import '../../../core/asr/vosk_service.dart';
import '../../../core/permission/permission_manager.dart';
import '../../../core/storage/database_helper.dart';
import '../../../core/storage/conversation_logger.dart';
import '../../settings/data/settings_repository.dart';
import '../../tools/data/tool_executor.dart';
import '../../tools/domain/tool.dart';
import '../domain/chat_message.dart';
import '../domain/chat_conversation.dart';
import '../data/chat_repository.dart';
import '../data/context_builder.dart';
import '../data/context_manager.dart';
import '../data/prompts/summary_system.dart';
import '../data/prompts/summary_lengths.dart';
import '../../../core/engine/agent_engine_provider.dart';
import '../../../core/engine/feedback_processor.dart' show StrategyUpgrade;
import '../../../core/engine/agent_state_persistence.dart';
import '../../../core/engine/network_resilience.dart';
import '../../../core/engine/battery_aware_executor.dart';
import '../../../core/saf/saf_client.dart';
import '../../../core/engine/tool_cancel_registry.dart' hide CancelToken;
import '../../../core/orchestrator/orchestrator_engine.dart';
import '../../../core/orchestrator/models/execution_state.dart';
import '../../../core/tools/tool_registry.dart';
import '../../../core/tools/tool_groups.dart';
import '../../../core/state/session_state_machine.dart';
import '../../../core/instructor/instructor.dart' hide MessageRole;
import '../../../core/hooks/hook_pipeline.dart';
import '../../../core/logging/tool_call_logger.dart';

final minimaxClientProvider =
    StateNotifierProvider<MinimaxClientNotifier, MinimaxClient>((ref) {
  return MinimaxClientNotifier();
});

final ttsEnabledProvider = StateProvider<bool>((ref) => false);
final ttsModelProvider = StateProvider<String>((ref) => const [
      'speech-2.8-hd',
      'speech-2.8-turbo',
      'speech-2.6-hd',
      'speech-2.6-turbo',
      'speech-02-hd',
      'speech-02-turbo'
    ].first);
final ttsVoiceProvider = StateProvider<String>((ref) => 'female-qn-qingse');

class MinimaxClientNotifier extends StateNotifier<MinimaxClient> {
  MinimaxClientNotifier() : super(MinimaxClient(apiKey: ''));

  Future<void> loadFromSettings() async {
    final settings = SettingsRepository();
    var apiKey = await settings.getActiveApiKey();
    final model = await settings.getModel();
    final baseUrl = await settings.getBaseUrl();
    final activeType = await settings.getActiveApiKeyType();

    if (apiKey.isEmpty) {
      final standardKey = await settings.getApiKeyStandard();
      final tokenKey = await settings.getApiKey();
      if (activeType == 'standard' && standardKey.isNotEmpty) {
        apiKey = standardKey;
      } else if (tokenKey.isNotEmpty) {
        apiKey = tokenKey;
        await settings.setActiveApiKeyType('token');
      }
    }

    state = MinimaxClient(apiKey: apiKey, model: model, baseUrl: baseUrl);
  }

  Future<void> switchApiKey(String type) async {
    final settings = SettingsRepository();
    await settings.setActiveApiKeyType(type);
    await loadFromSettings();
  }
}

final databaseHelperProvider = Provider((ref) => DatabaseHelper());

final chatRepositoryProvider = Provider((ref) {
  final client = ref.watch(minimaxClientProvider);
  final db = ref.watch(databaseHelperProvider);
  return ChatRepository(client: client, db: db);
});

// Settings change notifier
final settingsChangedProvider =
    ChangeNotifierProvider((ref) => SettingsChangeNotifier());

/// 外部模块（如热点 Tab）写入 prompt → ChatPage 自动填入输入框
final pendingChatInputProvider = StateProvider<String?>((ref) => null);

/// Tracks which conversations have a running agent (for green spinner in drawer)
final agentSessionProvider =
    StateNotifierProvider<AgentSessionNotifier, Map<String, bool>>((ref) {
  return AgentSessionNotifier();
});

class AgentSessionNotifier extends StateNotifier<Map<String, bool>> {
  AgentSessionNotifier() : super({});

  void setGenerating(String conversationId, bool value) {
    if (value) {
      state = {...state, conversationId: true};
    } else {
      final next = Map<String, bool>.from(state);
      next.remove(conversationId);
      state = next;
    }
  }
}

class SettingsChangeNotifier extends ChangeNotifier {
  int _version = 0;
  int get version => _version;

  void notify() {
    _version++;
    notifyListeners();
  }
}

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, this.onNavigateToSettings});
  final VoidCallback? onNavigateToSettings;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with WidgetsBindingObserver {
  // ── Session management ──
  final Map<String, ConversationSession> _sessions = {};
  ConversationSession? _activeSession;
  /// Safe session accessor — returns a harmless empty session if accessed
  /// after dispose (e.g., late async callback). Prevents null crash.
  ConversationSession get _session {
    return _activeSession ?? ConversationSession(conversationId: '__disposed__');
  }

  /// 否定词 — 关键词前出现这些词时跳过匹配
  ConversationSession _ensureSession(String id) {
    return _sessions.putIfAbsent(
        id, () => ConversationSession(conversationId: id));
  }

  // ── Shared UI fields (not per-conversation) ──
  final _messageController = TextEditingController();
  final _inputFocusNode = FocusNode(skipTraversal: true);
  final _scrollController = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _audioPlayer = AudioPlayer();
  bool _isPlayingTTS = false;
  bool _userTappedInput = false;
  bool _ttsCanceled = false;
  int _ttsGeneration = 0;       // 递增计数器，用于废弃过期的 _processTtsQueue 实例
  final Set<String> _ttsSentTexts = {};  // 已送入 TTS 的文本片段，用于去重
  StreamSubscription? _ttsPlayerSubscription;
  Completer<void>? _ttsPlaybackCompleter;
  MinimaxClient? _ttsClient;  // 预热的 TTS 客户端，复用以跳过 HTTP 连接建立
  bool get _isTtsActive => _isPlayingTTS || _ttsProcessing;
  List<ChatConversation> _conversations = [];
  ChatConversation? _taskConversation;
  bool _showTaskConversations = false;
  String? _currentConversationId;
  Set<String> _interruptedConvIds =
      {}; // Conversations with interrupted messages

  // Floating chat
  bool _floatingChatActive = false;
  StreamSubscription<FloatingChatEvent>? _floatingChatSub;
  final _floatingClient = FloatingChatClient();
  bool _isConfigured = false;
  bool _isProcessingImage = false;
  final List<_AttachmentItem> _attachments = [];
  bool _attachmentsExpanded = true;
  bool get _hasPendingAttachment => _attachments.isNotEmpty;
  int _lastSettingsVersion = 0;
  static const _lensDecayMax = 2;
  static const _skillPromptCap = 3;
  static const _skillDecayMax = 3;
  static const Duration _minSaveInterval = Duration(milliseconds: 300);
  final HookPipeline _hookPipeline = HookPipeline.instance;
  final _logScrollController = ScrollController();
  final _logger = ConversationLogger();
  final NetworkResilience _networkResilience = NetworkResilience();
  StreamSubscription<NetworkStatus>? _networkSubscription;
  StreamSubscription<SessionState>? _sessionStateSubscription;

  // ── Per-conversation getters/setters (delegate to active session) ──

  List<ChatMessage> get _messages => _session.messages;
  set _messages(List<ChatMessage> v) => _session.messages = v;
  List<ChatMessage> get _visibleMessages => _session.visibleMessages;

  bool get _isLoading => _session.isLoading;
  set _isLoading(bool v) => _session.isLoading = v;

  // _isGenerating must NOT delegate through _session because _activeSession
  // can be replaced mid-send (e.g. _ensureSession returns a new instance).
  // Delegation would read from a session that was never marked generating.
  bool _isGenerating = false;
  InteractivePrompt? _interactivePrompt;
  CancelToken? _cancelTokenForNewSession;
  String? _backtrackTargetId;

  CancelToken? get _currentCancelToken => _session.cancelToken;
  set _currentCancelToken(CancelToken? v) => _session.cancelToken = v;
  StreamState get _currentStreamState => _session.streamState;
  set _currentStreamState(StreamState v) => _session.streamState = v;
  bool get _streamInterrupted => _session.streamInterrupted;
  set _streamInterrupted(bool v) => _session.streamInterrupted = v;
  PauseToken get _pauseToken => _session.pauseToken;
  Map<String, String> get _streamingContent => _session.streamingContent;

  String get _currentSummary => _session.summary;
  set _currentSummary(String v) => _session.summary = v;
  String? get _originalQuestion => _session.originalQuestion;
  set _originalQuestion(String? v) => _session.originalQuestion = v;

  Set<String> get _activeLenses => _session.activeLenses;
  set _activeLenses(Set<String> v) => _session.activeLenses = v;
  int get _lensDecayCounter => _session.lensDecayCounter;
  set _lensDecayCounter(int v) => _session.lensDecayCounter = v;
  Set<String> get _activeSkills => _session.activeSkills;
  set _activeSkills(Set<String> v) => _session.activeSkills = v;
  Map<String, int> get _skillDecayCounters => _session.skillDecayCounters;
  set _skillDecayCounters(Map<String, int> v) =>
      _session.skillDecayCounters = v;
  Set<String> get _lastInjectedSkills => _session.lastInjectedSkills;
  set _lastInjectedSkills(Set<String> v) => _session.lastInjectedSkills = v;
  Map<String, int> get _skillUsageThisTurn => _session.skillUsageThisTurn;
  set _skillUsageThisTurn(Map<String, int> v) =>
      _session.skillUsageThisTurn = v;
  bool get _suppressUserSave => _session.suppressUserSave;
  set _suppressUserSave(bool v) => _session.suppressUserSave = v;
  OptimizeData? get _optimizeResult => _session.optimizeResult;
  set _optimizeResult(OptimizeData? v) => _session.optimizeResult = v;

  SessionStateMachine get _sessionStateMachine => _session.sessionStateMachine;
  ContextManager get _contextManager => _session.contextManager;

  String? get _tokenPlanErrorMessage => _session.tokenPlanErrorMessage;
  set _tokenPlanErrorMessage(String? v) => _session.tokenPlanErrorMessage = v;

  Map<String, List<String>> get _dependencies => _session.dependencies;

  List<LogEntry> get _logs => _session.logs;

  String? get _lastTruncatedMessageId => _session.lastTruncatedMessageId;
  set _lastTruncatedMessageId(String? v) => _session.lastTruncatedMessageId = v;
  String? get _lastTruncatedContent => _session.lastTruncatedContent;
  set _lastTruncatedContent(String? v) => _session.lastTruncatedContent = v;
  DateTime? get _lastPartialSave => _session.lastPartialSave;
  set _lastPartialSave(DateTime? v) => _session.lastPartialSave = v;

  bool get _userScrolledAway => _session.userScrolledAway;
  set _userScrolledAway(bool v) => _session.userScrolledAway = v;

  // TTS per-session data (playback control is shared)
  List<String> get _ttsQueue => _session.ttsQueue;
  bool get _ttsProcessing => _session.ttsProcessing;
  set _ttsProcessing(bool v) => _session.ttsProcessing = v;
  String get _lastTtsText => _session.lastTtsText;
  set _lastTtsText(String v) => _session.lastTtsText = v;

  void _recordDependency(String baseMessageId, String dependentMessageId) {
    _session.recordDependency(baseMessageId, dependentMessageId);
  }

  void _invalidateDependentMessages(String baseMessageId) {
    _session.invalidateDependentMessages(baseMessageId);
  }

  void _onMessageCompleted(String messageId) {
    _session.onMessageCompleted(messageId);
  }

  void _transitionState(StreamState newState) {
    _session.transitionState(newState, _addLog);
  }

  void _addLog(String level, String message,
      [Object? error, StackTrace? stackTrace]) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      error: error?.toString(),
      stackTrace: stackTrace?.toString());
    _logs.insert(0, entry);
    if (_logs.length > 500) _logs.removeLast();
    _logger.log(level, message, error: error, stackTrace: stackTrace);
  }

  /// 引擎决策分析（集成输入层+决策层）
  void _analyzeEngineDecision(String input, List<Map<String, String>> history) {
    try {
      final engine = ref.read(agentEngineProvider);
      final info = engine.analyzeInput(input, history: history);
      _addLog('ENGINE',
          '优先级: ${info.priority} | 搜索: ${info.needsSearch} | 代码: ${info.needsCodeExecution}');
      _addLog('ENGINE', '推理: ${info.reasoning}');
    } catch (e) {
      print('[chat] error: \$e');
      _addLog('DEBUG', '引擎分析跳过: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _messageController.addListener(_onTextChanged);
    // 仅当用户显式点击输入框时才允许获得焦点，阻止系统自动恢复焦点导致键盘弹出
    _inputFocusNode.addListener(() {
      if (_inputFocusNode.hasFocus && !_userTappedInput) {
        _inputFocusNode.unfocus();
      }
      _userTappedInput = false;
    });
    // Create a default session so getters never return null
    _activeSession = ConversationSession(conversationId: '__default__');
    _initFloatingChat();
    _initAndLoad();
    _initNetworkResilience();
    BatteryAwareExecutor.instance.init();
    _initTaskScheduler();
    _sessionStateSubscription = _sessionStateMachine.stateStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  void _initTaskScheduler() async {
    _taskScheduler = TaskScheduler();
    await _taskScheduler!.initialize();
    _taskScheduler!.onTaskResultForUI = (title, desc, result) {
      _insertTaskResult(title, desc, result);
    };
    await _taskScheduler!.start();
    ref.read(taskSchedulerProvider.notifier).state = _taskScheduler;
  }

  void _initFloatingChat() {
    if (!FloatingChatClient.isSupported) return;
    _floatingChatSub = _floatingClient.events.listen((event) {
      switch (event.type) {
        case 'sendMessage':
          final text = event.data ?? '';
          if (text.isNotEmpty) {
            _floatingChatActive = true;
            _sendMessage(messageText: text);
          }
          break;
        case 'ballTapped':
          // User tapped the ball → panel opened, sync messages
          _floatingChatActive = true;
          _syncMessagesToPanel();
          break;
        case 'openApp':
          _floatingChatActive = false;
          _floatingClient.hideAll();
          break;
        case 'panelStateChanged':
          _floatingChatActive = event.data == 'true';
          if (_floatingChatActive) {
            _syncMessagesToPanel();
          }
          break;
      }
    });
  }

  void _syncMessagesToPanel() {
    if (_activeSession == null) return;
    final msgs = _visibleMessages
        .map((m) => {
              'role': m.role.name,
              'content': m.content,
            })
        .toList();
    _floatingClient.syncMessages(msgs);
  }

  /// 任务执行完成 → 如果正在查看任务会话，从 DB 重新加载
  Future<void> _insertTaskResult(String title, String description, String result) async {
    if (_currentConversationId == DatabaseHelper.taskConversationId) {
      await _loadMessages();
    }
  }

  void _onTextChanged() {
    // 文本变化时触发 UI 更新（更新发送按钮状态）
    setState(() {});
  }

  void _initNetworkResilience() {
    _networkResilience.init();
    _networkSubscription =
        _networkResilience.networkStatusStream.listen((status) {
      _addLog('NETWORK', '网络状态变化: ${status.name}');
      if (status == NetworkStatus.online) {
        _retryPendingOperation();
      } else {
        _handleNetworkOffline();
      }
    });
  }

  void _retryPendingOperation() {
    if (_currentStreamState == StreamState.paused) {
      _addLog('INFO', '网络恢复，尝试恢复暂停的流式响应');
    }
  }

  void _handleNetworkOffline() {
    if (_isGenerating) {
      _addLog('WARN', '网络断开，暂停生成');
    }
  }

  Future<void> _checkPendingToolState() async {
    final pendingState = await AgentStatePersistence.load();
    if (pendingState != null && mounted) {
      _addLog('INFO', '发现未完成的工具执行: ${pendingState.toolName}');
      final shouldRetry = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: PixelTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: PixelTheme.pixelBorder, width: 2)),
          title: const Row(
            children: [
              Icon(Icons.pending_actions, color: PixelTheme.primary, size: 20),
              SizedBox(width: 8),
              Text('工具执行中断',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 16)),
            ]),
          content: Text(
            '上次工具 "${pendingState.toolName}" 执行被中断。\n\n是否重试？',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('取消', style: TextStyle(fontFamily: 'monospace'))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('重试', style: TextStyle(fontFamily: 'monospace'))),
          ]));

      if (shouldRetry == true) {
        _addLog('INFO', '用户选择重试工具执行');
      } else {
        await AgentStatePersistence.clear();
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    const threshold = 50.0; // 底部阈值

    if (maxScroll - currentScroll > threshold) {
      // 用户滚到了上方，不再自动滚动
      _userScrolledAway = true;
    } else {
      // 用户滚回了底部，恢复自动滚动
      _userScrolledAway = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _messageController.dispose();
    _inputFocusNode.dispose();
    _scaffoldKey.currentState?.dispose();
    _audioPlayer.dispose();
    _ttsPlayerSubscription?.cancel();
    _floatingChatSub?.cancel();
    _networkSubscription?.cancel();
    _sessionStateSubscription?.cancel();
    _networkResilience.dispose();
    _logScrollController.dispose();
    _taskScheduler?.stop();
    _consolidationTimer?.cancel();
    
    // Cancel all active sessions
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
    _activeSession = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSettingsChanged();
      _checkPendingToolState();
      _checkSharedContent();
      // Hide floating chat when returning to app
      _floatingClient.hideAll();
      _floatingChatActive = false;
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Show floating ball when app goes to background
      if (FloatingChatClient.isSupported) {
        _floatingClient.showBall();
      }
    }
  }

  Future<void> _checkSharedContent() async {
    final shared = await ShareReceiver.getPendingShare();
    if (shared == null || !mounted) return;
    _messageController.text = shared.effectiveText ?? '';
    if (shared.hasImage && shared.imageBytes != null) {
      setState(() {
        _attachments.add(_AttachmentItem(
          type: AttachmentType.image,
          base64: base64Encode(shared.imageBytes!),
          fileName: shared.imageFileName ?? 'shared_image.jpg',
          mimeType: shared.imageMimeType ?? 'image/jpeg',
          fileSize: shared.imageSize ?? shared.imageBytes!.length));
        _attachmentsExpanded = true;
      });
    }
    if (shared.hasText || shared.hasImage) {
      _sendMessage();
    }
  }

  Future<void> _checkSettingsChanged() async {
    final settings = SettingsRepository();
    final isConfigured = await settings.isConfigured();
    final settingsNotifier = ref.read(settingsChangedProvider);

    if (settingsNotifier.version != _lastSettingsVersion ||
        _isConfigured != isConfigured) {
      _lastSettingsVersion = settingsNotifier.version;
      if (mounted) {
        setState(() => _isConfigured = isConfigured);
      }
    }
  }

  Future<void> _initAndLoad() async {
    await ref.read(minimaxClientProvider.notifier).loadFromSettings();
    MemoryCache.instance.configure(client: ref.read(minimaxClientProvider));
    _startMemoryConsolidation();
    final settings = SettingsRepository();
    final isConfigured = await settings.isConfigured();
    if (mounted) {
      setState(() => _isConfigured = isConfigured);
      await _loadConversations();
      // Fix messages left in streaming/paused state by a previous crash
      final db = ref.read(databaseHelperProvider);
      final interruptedIds = await db.fixInterruptedMessages();
      _interruptedConvIds = interruptedIds.toSet();
      if (_currentConversationId == null && _conversations.isNotEmpty) {
        _currentConversationId = _conversations.first.id;
      }
      if (_currentConversationId != null) {
        await _loadMessages();
      }
    }
  }

  Future<void> _loadConversations() async {
    final repo = ref.read(chatRepositoryProvider);
    final convs = await repo.getConversations();

    // 分离定时任务会话
    final taskConv = convs
        .where((c) => c.id == DatabaseHelper.taskConversationId)
        .firstOrNull;
    final normalConvs =
        convs.where((c) => c.id != DatabaseHelper.taskConversationId).toList();

    if (mounted) {
      setState(() {
        _taskConversation = taskConv;
        _conversations = normalConvs;
      });
    }
  }

  Future<void> _loadMessages() async {
    if (_currentConversationId == null) return;
    _activeSession = _ensureSession(_currentConversationId!);
    final repo = ref.read(chatRepositoryProvider);
    final db = ref.read(databaseHelperProvider);

    try {
      // 同时加载会话摘要和两层摘要
      final summary = await repo.getSummary(_currentConversationId!);

      // If session is still actively generating, keep in-memory messages.
      // But if the CancelToken was cancelled (stream ended in background),
      // force reload from DB since generation may have completed silently.
      final providerGenerating = ref.read(agentSessionProvider)[_currentConversationId] == true;
      final sessionGenerating = _session.isGenerating || providerGenerating;
      final isActuallyGenerating = sessionGenerating &&
          _session.cancelToken != null &&
          !_session.cancelToken!.isCancelled;
      if (!isActuallyGenerating) {
        // Ensure state is clean if generation stopped in background
        if (sessionGenerating) {
          _session.isGenerating = false;
          _session.isLoading = false;
          _session.sessionStateMachine.reset();
        }
        final msgs = await repo.getMessages(_currentConversationId!);
        debugPrint(
            '[Chat] Loaded ${msgs.length} messages for conversation $_currentConversationId');

        final Map<String, ChatMessage> uniqueMsgs = {};
        for (final msg in msgs) {
          uniqueMsgs[msg.id] = msg;
        }
        final dedupedMsgs = uniqueMsgs.values.toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        if (mounted) {
          setState(() {
            _messages = dedupedMsgs;
            _currentSummary = summary ?? '';
            // Sync UI state with session's actual generating state
            _isGenerating = _session.isGenerating;
            _isLoading = _session.isLoading;
          });
          _contextManager.loadFromMessages(dedupedMsgs);
        }
      } else {
        // Session is still generating — keep live messages, just update metadata
        if (mounted) {
          setState(() {
            _currentSummary = summary ?? '';
            // Sync UI state with session's actual generating state
            _isGenerating = _session.isGenerating;
            _isLoading = _session.isLoading;
          });
        }
      }
      final ctxData = await repo.getContext(_currentConversationId!);
      if (ctxData != null && ctxData['tokenCount'] is int) {
        final savedTokens = ctxData['tokenCount'] as int;
        if (savedTokens > 0) {
          _contextManager.currentTokens = savedTokens;
        }
      }
      _updateContextStatus();
      if (mounted) {
        _scrollToBottom();
      }
    } catch (e, stack) {
      debugPrint('[Chat] _loadMessages error: $e\n$stack');
    }
  }

  void _updateContextStatus() {
    final status = _contextManager.getStatus();
    _addLog('DEBUG', '上下文状态: ${status.description} - ${status.status}');
  }

  /// 发送消息到指定会话。conversationId 为 null 时使用当前会话。
  /// silent=true 时不在 UI 中显示消息（用于定时任务等后台执行）
  Future<void> _sendMessage(
      {String? conversationId,
      String? messageText,
      bool silent = false}) async {
    if (!_isConfigured) {
      widget.onNavigateToSettings?.call();
      return;
    }

    if (_isLoading || _isGenerating) {
      _addLog('WARN', '消息正在处理中，跳过重复发送');
      return;
    }

    final text = messageText ?? _messageController.text.trim();
    if (text.isEmpty && !_hasPendingAttachment) return;

    _stopTts();
    _lastTtsText = '';

    if (text == '/压缩') {
      _addLog('INFO', '手动触发上下文压缩');
      await _performManualCompress();
      _messageController.clear();
      return;
    }

    _messageController.clear();
    _interactivePrompt = null;
    _selectedIndices = {};

    // Determine target conversation and capture its session
    String? targetConvId = conversationId ?? _currentConversationId;
    // We don't know the conversation ID yet if it's a new one; we'll create it below

    // Save original state for silent/background mode
    final originalConversationId = _currentConversationId;
    final originalMessages = silent ? List<ChatMessage>.from(_messages) : null;

    // For silent sends, we'll use a dedicated session; for normal sends, the active session IS the target
    if (!silent && targetConvId != null) {
      _activeSession = _ensureSession(targetConvId);
    }

    // Capture the session reference that will be used throughout this method.
    // We'll resolve it fully after conversation creation below.
    ConversationSession? capturedSession;

    _sessionStateMachine.onSendStart();

    setState(() {
      _isLoading = true;
      _isGenerating = true;
      _ttsGeneration++;  // 废弃所有正在运行的 _processTtsQueue 实例
      _ttsCanceled = true;
      _ttsSentTexts.clear();
      _lastTtsText = '';
      _ttsQueue.clear();
      _ttsProcessing = false;
      _ttsPlayerSubscription?.cancel();
      _ttsPlayerSubscription = null;
      _ttsPlaybackCompleter = null;
      _audioPlayer.stop();

      _backtrackTargetId = null;
      _originalQuestion = text;
    });
    _currentCancelToken?.cancel();
    final newCancelToken = CancelToken();
    _currentCancelToken = newCancelToken;
    _cancelTokenForNewSession = newCancelToken;

    try {
      await ref.read(minimaxClientProvider.notifier).loadFromSettings();
      final repo = ref.read(chatRepositoryProvider);

      // 切换到目标会话
      if (conversationId != null) {
        _currentConversationId = conversationId;
      }
      _currentConversationId ??= await repo.createConversation(
        text.length > 20 ? '${text.substring(0, 20)}...' : text);
      if (_currentConversationId == null) {
        throw StateError('创建会话失败 / Failed to create conversation');
      }

      // Resolve the captured session
      capturedSession = _ensureSession(_currentConversationId!);
      // Sync session state — for new conversations the earlier writes
      // went to the __new__ placeholder; re-apply to the real session.
      capturedSession.isLoading = true;
      capturedSession.isGenerating = true;
      capturedSession.cancelToken = _cancelTokenForNewSession ?? capturedSession.cancelToken;
      if (!silent) {
        _activeSession = capturedSession;
      }
      ref
          .read(agentSessionProvider.notifier)
          .setGenerating(_currentConversationId!, true);
      if (_floatingChatActive) {
        _floatingClient.setGenerating(true);
      }

      // 立即添加用户消息到 UI
      final userMsgId = 'user_${DateTime.now().millisecondsSinceEpoch}';

      final attachments = List<_AttachmentItem>.from(_attachments);
      final firstAttachment = attachments.isNotEmpty ? attachments.first : null;
      final extraInfo = attachments.length > 1
          ? attachments
              .skip(1)
              .map((a) => '[附件: ${a.fileName}]${a.extractedText ?? ""}')
              .join('\n')
          : null;
      final combinedExtracted = [
        if (firstAttachment?.extractedText != null)
          firstAttachment!.extractedText!,
        if (extraInfo != null) extraInfo
      ].join('\n');

      final userMsg = ChatMessage(
        id: userMsgId,
        conversationId: _currentConversationId!,
        role: MessageRole.user,
        content: text,
        createdAt: DateTime.now(),
        imageBase64: firstAttachment?.type == AttachmentType.image
            ? firstAttachment!.base64
            : null,
        fileName: firstAttachment?.fileName,
        fileType: firstAttachment?.type == AttachmentType.document
            ? 'document'
            : (firstAttachment?.base64 != null ? 'image' : null),
        mimeType: firstAttachment?.mimeType,
        fileSize: firstAttachment?.fileSize,
        extractedText: combinedExtracted.isNotEmpty ? combinedExtracted : null);

      // 保存临时变量供后续 API 调用
      final pendingImage = firstAttachment?.type == AttachmentType.image
          ? firstAttachment!.base64
          : null;
      final pendingFileName = firstAttachment?.fileName;
      final pendingMimeType = firstAttachment?.mimeType;
      final pendingFileSize = firstAttachment?.fileSize;
      final pendingType = firstAttachment?.type ?? AttachmentType.document;
      final pendingExtractedText =
          combinedExtracted.isNotEmpty ? combinedExtracted : null;
      _attachments.clear();

      // 创建临时的 assistant 消息用于流式显示
      final tempMsgId = 'temp_${DateTime.now().millisecondsSinceEpoch + 1}';
      String fullResponse = '';

      // 将用户消息加入上下文管理器
      _contextManager.confirmMessage(userMsg);
      final preSendStatus = _contextManager.getStatus();
      _addLog('DEBUG', '发送前上下文: ${preSendStatus.description}');

      // 检查是否需要摘要（超过75%）
      if (_contextManager.needsSummary) {
        _addLog('INFO',
            '上下文使用率 ${(preSendStatus.usageRate * 100).toStringAsFixed(1)}%，即将触发自动摘要');
      }

      // 引擎决策分析（可选，用于日志/调试）
      // history在此处未定义，移至流式响应前调用

      // 立即更新 UI 显示用户消息（去重）
      if (!_messages.any((m) => m.id == userMsgId)) {
        if (!mounted) return;
        setState(() {
          _messages.add(userMsg);
        });
        _scrollToBottom();
      }

      String fullResponseContent = '';
      if (pendingImage != null && pendingType != AttachmentType.document) {
        // 视觉模式：图片+文字一起分析，注入透镜到 prompt
        final baseVisionPrompt = text.isEmpty ? '请详细描述这张图片的内容' : text;
        final visionLens = _buildPersonaLens(baseVisionPrompt, false);
        final visionPrompt = visionLens.isEmpty
            ? baseVisionPrompt
            : '$visionLens\n\n$baseVisionPrompt';
        _isGenerating = true;
        setState(() {});

        try {
          fullResponse = await repo.sendMessage(
            conversationId: _currentConversationId!,
            message: visionPrompt,
            imageBase64: pendingImage,
            fileName: pendingFileName,
            fileType: 'image',
            mimeType: pendingMimeType,
            fileSize: pendingFileSize);
          fullResponseContent = fullResponse;
        } catch (e) {
          if (e.toString().contains('Token Plan')) {
            _showTokenPlanErrorBanner('图片理解需要 Token Plan 服务');
          }
          rethrow;
        }
        // 更新 UI 添加助手消息
        if (mounted) {
          final cleanContent = _cleanSystemTags(fullResponse);
          setState(() {
            _messages.add(ChatMessage(
              id: tempMsgId,
              conversationId: _currentConversationId!,
              role: MessageRole.assistant,
              content: cleanContent,
              createdAt: DateTime.now()));
          });
        }
      } else {
        // Build the message — for documents, prepend extracted text as context
        String fullMessage = text;
        if (pendingExtractedText != null && pendingExtractedText.isNotEmpty) {
          final docCtx = '[文件: $pendingFileName]\n\n$pendingExtractedText';
          fullMessage = text.isNotEmpty ? '$text\n\n$docCtx' : docCtx;
        }

        // 构建动态上下文（排除刚添加的用户消息，因为它会作为当前消息发送）
        final settings = SettingsRepository();
        final browserTab = ref.read(browserActiveTabProvider);
        final browserTabs = ref.read(browserTabsProvider);
        // 结构化 system content（含 cache_control 断点），动态 lens 追加为独立 block
        final systemContent = silent
            ? await settings.buildTaskSystemContent()
            : await settings.buildSystemContent(
                browserTitle: browserTab?.title,
                browserUrl: browserTab?.url,
                browserTabCount: browserTabs.length,
                messageQuery: fullMessage);
        if (!silent) {
          final lensText =
              await _buildPersonaLensHybrid(fullMessage) + _buildSkillCatalog();
          if (lensText.isNotEmpty) {
            systemContent.add({'type': 'text', 'text': lensText});
          }
        }
        final systemPrompt = systemContent;  // List<Map> → dynamic
        // 如果发送到非当前会话，加载目标会话的历史
        List<ChatMessage> historyMessages;
        String summaryForHistory = _currentSummary;
        if (conversationId != null &&
            conversationId != originalConversationId) {
          final targetMsgs = await repo.getMessages(conversationId);
          historyMessages = targetMsgs;
          summaryForHistory = await repo.getSummary(conversationId) ?? '';
        } else {
          historyMessages = _messages.length > 1
              ? _messages.sublist(0, _messages.length - 1)
              : <ChatMessage>[];
        }
        final history = ContextBuilder.buildContext(
          messages: historyMessages,
          summary: summaryForHistory.isNotEmpty ? summaryForHistory : null);

        _addLog('DEBUG', 'buildContext输出: ${history.length}条');
        for (var i = 0; i < history.length; i++) {
          final m = history[i];
          final preview = m['content']!.length > 30
              ? '${m['content']!.substring(0, 30)}...'
              : m['content']!;
          _addLog('DEBUG', '  [$i] ${m['role']}: $preview');
        }

        _addLog('DEBUG',
            '系统提示词长度: ${systemPrompt.length}, 历史消息数: ${history.length}');

        // 引擎决策分析
        _analyzeEngineDecision(fullMessage, history);

        // beforeSend hook (may mask PII in message)
        final beforeSendCtx = HookContext(HookEvent.beforeSend, {
          'message': fullMessage,
          'conversationId': _currentConversationId,
        });
        await _hookPipeline.execute(HookEvent.beforeSend, beforeSendCtx);
        fullMessage = beforeSendCtx.data['message'] as String? ?? fullMessage;

        // PII 检测反馈
        if (beforeSendCtx.data['pii_masked'] == true) {
          final types =
              (beforeSendCtx.data['pii_types'] as List<dynamic>?)?.join('、') ??
                  '';
          _showSnackBar('已自动脱敏: $types', duration: const Duration(seconds: 2));
        }

        // 读取推理参数（MiniMax 最佳实践）
        final temperature = await settings.getTemperature();
        final maxTokens = await settings.getMaxTokens();
        final thinkingBudget = await settings.getThinkingBudget();
        final toolChoiceStr = await settings.getToolChoice();
        final toolChoice =
            toolChoiceStr == 'any' ? <String, dynamic>{'type': 'any'} : null;
        _addLog('INFO',
            '推理参数: temp=$temperature, maxTokens=$maxTokens, thinking=${thinkingBudget}budget, toolChoice=$toolChoiceStr');

        // 清除工具结果缓存（新一轮对话）
        ToolExecutor.clearResultCache();

        // 先保存用户消息，防止导航离开后丢失
        try {
          await repo.addMessage(
            _currentConversationId!,
            'user',
            fullMessage,
            fileName: pendingFileName,
            fileType:
                pendingType == AttachmentType.document ? 'document' : null,
            mimeType: pendingMimeType,
            fileSize: pendingFileSize,
            extractedText: pendingExtractedText);
          capturedSession!.suppressUserSave = true;
        } catch (e) {
          print('[chat] error: \$e');
          _addLog('WARN', '保存用户消息失败: $e');
        }
        // 流式获取响应（原生 tool_use —— 内部处理工具调用循环）
          // 流式获取响应（原生 tool_use —— 内部处理工具调用循环）
          // Wrap executeTool to capture the session for background execution
          final sessionRef = capturedSession;
          final stream = repo.sendMessageStreamNative(
            conversationId: _currentConversationId!,
            message: fullMessage,
            systemPrompt: systemPrompt,
            history: history,
            fileName: pendingFileName,
            fileType:
                pendingType == AttachmentType.document ? 'document' : null,
            mimeType: pendingMimeType,
            fileSize: pendingFileSize,
            extractedText: pendingExtractedText,
            cancelToken: sessionRef.cancelToken,
            
            skipSaveUserMessage: sessionRef.suppressUserSave,
            executeTool: (toolName, args) =>
                _executeToolCallNativeForSession(sessionRef, toolName, args),
            temperature: temperature,
            maxTokens: maxTokens,
            thinkingBudgetTokens: thinkingBudget,
            toolChoice: toolChoice,
            messageId: tempMsgId,
            pauseToken: sessionRef.pauseToken,
            hookPipeline: _hookPipeline,
            activeSkills: _activeSkills);

          DateTime lastUpdate = DateTime.now();
          const minInterval = Duration(milliseconds: 300);
          bool openFolderRequested = false;
          String openFolderPath = '';
          String fullThinking = ''; // 完整思考内容
          capturedSession.streamInterrupted = false;
          sessionRef.pauseToken.resume(); // 重置暂停状态
          capturedSession.transitionState(StreamState.streaming, _addLog);
          capturedSession.lastPartialSave = DateTime.now();

          _addLog('DEBUG', '开始处理流式响应');

          bool firstTokenEmitted = false;

          try {
            await for (final msg in stream) {
              // Signal first token to state machine (unlocks input once streaming confirmed)
              if (!firstTokenEmitted && (msg.content.isNotEmpty || msg.thinking != null)) {
                firstTokenEmitted = true;
                capturedSession.sessionStateMachine.onFirstToken();
              }

              final now = DateTime.now();
              final shouldUpdate = now.difference(lastUpdate) >= minInterval;

              // 累积回复内容
              fullResponseContent = msg.content;
              // 转发流式内容到悬浮窗
              if (_floatingChatActive) {
                _floatingClient.updateStreaming(msg.content);
              }
              if (msg.thinking != null) {
                fullThinking = msg.thinking!;
                // 思考阶段预热 TTS：提前建立连接，等文本到达时零延迟启动
                _prewarmTts();
              }

              // TTS: 实时语音合成 (only if user is viewing this session)
              if (_activeSession == capturedSession) {
                _feedTtsQueue(fullResponseContent);
              }

              // 检测 [OPEN_FOLDER] 标记（只在消息末尾才触发）
              if (!openFolderRequested &&
                  msg.content.contains('[OPEN_FOLDER]')) {
                final folderMatch =
                    RegExp(r'\[OPEN_FOLDER\]\s*(.+)').firstMatch(msg.content);
                if (folderMatch != null) {
                  final matchEnd = folderMatch.end;
                  final contentEnd = msg.content.trimRight().length;
                  if (matchEnd >= contentEnd) {
                    openFolderPath = folderMatch.group(1)?.trim() ?? '';
                    openFolderRequested = true;
                    _addLog('INFO', '检测到打开文件夹请求: $openFolderPath');
                  }
                }
              }

              if (!mounted) break;

              // conversationId 可能已被压缩等操作清除
              if (_currentConversationId == null) {
                _addLog('WARN', 'conversationId 为空，中断流式处理');
                break;
              }

              final existingIndex =
                  capturedSession.messages.indexWhere((m) => m.id == tempMsgId);

              final streamingMsg = ChatMessage(
                id: tempMsgId,
                conversationId: _currentConversationId!,
                role: MessageRole.assistant,
                content: msg.content,
                createdAt: DateTime.now(),
                thinking: msg.thinking);

              if (existingIndex >= 0) {
                capturedSession.messages[existingIndex] = streamingMsg;
              } else {
                capturedSession.messages.add(streamingMsg);
              }

              if (shouldUpdate &&
                  mounted &&
                  _activeSession == capturedSession) {
                lastUpdate = now;
                setState(() {});
                _scrollToBottom();
              }

              // 增量保存 partial content（每 300ms 保存一次）
              if (capturedSession.lastPartialSave != null &&
                  now.difference(capturedSession.lastPartialSave!) >=
                      _minSaveInterval) {
                await repo.updatePartialMessage(
                  messageId: tempMsgId,
                  conversationId: _currentConversationId!,
                  partialContent: msg.content,
                  tokenOffset:
                      capturedSession.contextManager.estimateMessageTokens(
                    ChatMessage(
                        id: tempMsgId,
                        conversationId: _currentConversationId!,
                        role: MessageRole.assistant,
                        content: msg.content,
                        createdAt: DateTime.now())),
                  isTruncated: true,
                  streamState: StreamState.paused.name);
                capturedSession.lastTruncatedMessageId = tempMsgId;
                capturedSession.lastTruncatedContent = msg.content;
                capturedSession.lastPartialSave = now;
              }
            }
            _addLog('DEBUG', '流式响应完成');

            // 清理系统标记，避免暴露给用户
            final cleanContent = _cleanSystemTags(fullResponseContent);
            if (cleanContent != fullResponseContent) {
              final existingIndex =
                  capturedSession.messages.indexWhere((m) => m.id == tempMsgId);
              if (existingIndex >= 0) {
                capturedSession.messages[existingIndex] = capturedSession
                    .messages[existingIndex]
                    .copyWith(content: cleanContent);
              }
            }

            capturedSession.transitionState(StreamState.completed, _addLog);
            capturedSession.lastTruncatedMessageId = null;
            capturedSession.lastTruncatedContent = null;
            if (_floatingChatActive) {
              _floatingClient.streamDone();
              _floatingClient.setGenerating(false);
            }
          } catch (e, st) {
            // 暂停导致的取消：如果 streamInterrupted 已设置，说明是用户主动暂停
            if (capturedSession.streamInterrupted) {
              _addLog('INFO', '流式响应因用户暂停而中断');
              _flushTtsQueue(fullResponseContent);
              if (mounted && _activeSession == capturedSession) {
                setState(() {
                  capturedSession!.isGenerating = false;
                  _isGenerating = false;
                  _isLoading = false;
                });
              } else {
                capturedSession.isGenerating = false;
                _isGenerating = false;
                _isLoading = false;
              }
              return;
            }
            _addLog('ERROR', '流式响应异常: $e', e, st);
            capturedSession.transitionState(StreamState.failed, _addLog);
            await ref.read(minimaxClientProvider.notifier).loadFromSettings();
            // 保留部分内容，标记为失败状态让用户可以重试
            final existingIndex =
                capturedSession.messages.indexWhere((m) => m.id == tempMsgId);
            if (existingIndex >= 0 && fullResponseContent.isNotEmpty) {
              capturedSession.messages[existingIndex] =
                  capturedSession.messages[existingIndex].copyWith(
                streamState: 'failed',
                isTruncated: true);
            }
            if (mounted) {
              final errStr = e.toString();
              if (errStr.contains('连接超时') ||
                  errStr.contains('网络错误') ||
                  errStr.contains('Connection')) {
                _showError('网络连接失败，请检查网络后重试');
              } else if (errStr.contains('接收响应超时')) {
                _showError('响应超时，请重试');
              } else {
                _showError(
                    '响应异常: ${errStr.length > 60 ? '${errStr.substring(0, 60)}...' : errStr}');
              }
            }
          }

          // 如果是被中断的流式响应，跳过后续的自动处理流程
          if (capturedSession.streamInterrupted) {
            _addLog('INFO', '流式响应被中断，跳过后续处理');
            _flushTtsQueue(fullResponseContent); // TTS: flush remaining
            _interactivePrompt = null;
            _selectedIndices = {};
            if (mounted && _activeSession == capturedSession) {
              setState(() {
                capturedSession!.isGenerating = false;
                _isGenerating = false;
                _isLoading = false;
              });
            } else {
              capturedSession.isGenerating = false;
              _isGenerating = false;
              _isLoading = false;
            }
            return;
          }

          // 流式结束后，检查上下文状态
          final postStreamStatus = capturedSession.contextManager.getStatus();
          _addLog('DEBUG', '流式结束后上下文: ${postStreamStatus.description}');

          // 如果达到75%阈值，保留最近消息 + 对旧消息生成滚动摘要
          if (postStreamStatus.needsSummary &&
              capturedSession.messages.length > 4) {
            _addLog('INFO',
                '上下文使用率 ${(postStreamStatus.usageRate * 100).toStringAsFixed(1)}%，执行上下文压缩');
            await _rollingSummarize();
          }

          // 检查是否请求了打开文件夹
          if (openFolderRequested && openFolderPath.isNotEmpty) {
            _addLog('DEBUG', '打开文件夹: $openFolderPath');
            await _openFolder(openFolderPath);
          }

          // 最终更新 (only if user is still viewing this session)
          if (mounted && _activeSession == capturedSession) {
            setState(() {});
            _scrollToBottom();
          }

      // afterReceive hook + 状态机完成
      await _hookPipeline.execute(
          HookEvent.afterReceive,
          HookContext(HookEvent.afterReceive, {
            'conversationId': _currentConversationId,
            'success': !capturedSession.streamInterrupted,
          }));
      capturedSession.sessionStateMachine.onStreamDone();
      // Reset state machine to idle so input box is re-enabled
      capturedSession.sessionStateMachine.reset();

      // 记忆模块：解析 AI 回复中的 [MEM:] 标记
      _handleMemoryTags(fullResponseContent);

      // TTS: 流式结束后 flush 剩余文本 (only if user is viewing this session)
      if (_activeSession == capturedSession) {
        _flushTtsQueue(fullResponseContent);
      }

      await _loadConversations();
      }
    } finally {
      // Guard: capturedSession may be null if createConversation() failed
      if (capturedSession == null) {
        _isGenerating = false;
        _isLoading = false;
        _sessionStateMachine.reset();
        if (mounted) {
          _messageController.clear();
          _attachments.clear();
        }
        _refreshTokenQuota();
        return;
      }

      capturedSession!.suppressUserSave = false;

      // Clean up session state
      capturedSession!.isLoading = false;
      capturedSession!.isGenerating = false;
      _isGenerating = false;
      _isLoading = false;
      ref
          .read(agentSessionProvider.notifier)
          .setGenerating(capturedSession!.conversationId, false);
      capturedSession!.sessionStateMachine.reset();

      // 恢复原始会话
      if (silent && originalConversationId != null) {
        _currentConversationId = originalConversationId;
      }

      if (mounted) {
        // Only call setState if user is viewing this session
        final isActive = _activeSession == capturedSession;
        if (isActive) {
          setState(() {
            _messageController.clear();
            _attachments.clear();

            // 恢复原始消息列表
            if (silent && originalMessages != null) {
              capturedSession!.messages = originalMessages;
              // 添加简短通知
              final taskTitle =
                  text.length > 30 ? '${text.substring(0, 30)}...' : text;
              capturedSession!.messages.add(ChatMessage(
                id: 'task_notify_${DateTime.now().millisecondsSinceEpoch}',
                conversationId: _currentConversationId ?? '',
                role: MessageRole.assistant,
                content: '⏰ $taskTitle — 已完成，回复保存到定时任务记录。',
                createdAt: DateTime.now()));
            }
          });
        } else {
          _messageController.clear();
          _attachments.clear();
          if (silent && originalMessages != null) {
            capturedSession!.messages = originalMessages;
          }
        }
        if (!silent) {
          _saveContextToDb();
        }
      }
      _refreshTokenQuota();
    }
  }

  /// 刷新 token 配额
  Future<void> _refreshTokenQuota() async {
    try {
      final settings = SettingsRepository();
      final apiKey = await settings.getActiveApiKey();
      if (apiKey.isEmpty) return;

      final baseUrl = await settings.getBaseUrl();
      final client = MinimaxClient(apiKey: apiKey, baseUrl: baseUrl);
      final quota = await client.getQuota();
      if (mounted) {
        ref.read(quotaInfoProvider.notifier).setQuota(quota);
      }
    } catch (_) {}
  }

  // ============ 记忆模块 ============

  TaskScheduler? _taskScheduler;

  /// 解析 AI 回复中的 [MEM:类型:字段=值] 标记并存入记忆库。
  /// 标记由 AI 在对话中自主生成（系统提示已指导 AI 何时使用），实现显示触发。
  void _handleMemoryTags(String aiResponse) {
    final pattern = RegExp(r'\[MEM:(\w+):(\w+)=(.+?)\]');
    final matches = pattern.allMatches(aiResponse);
    if (matches.isEmpty) return;

    final cache = MemoryCache.instance;
    for (final m in matches) {
      final type = m.group(1)!;
      final key = m.group(2)!;
      final value = m.group(3)!;

      if (type == 'task') {
        final parts = value.split('|');
        final title = parts[0].trim();
        final dateStr = parts.length > 1 ? parts[1].trim() : null;
        DateTime? dueDate;
        if (dateStr != null && dateStr.isNotEmpty) {
          dueDate = DateTime.tryParse(dateStr);
        }
        cache.addTask({
          'id': 'task_${DateTime.now().microsecondsSinceEpoch}',
          'title': title,
          'description': '',
          'task_type': 'scheduled',
          'interval_seconds': 0,
          'due_time': dueDate?.millisecondsSinceEpoch,
          'status': 'pending',
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'is_active': 1,
        });
        _addLog('MEM', '任务: $title');
      } else {
        cache.set(type, key, value, source: 'ai');
        _addLog('MEM', '$type.$key = $value');
      }
    }
  }

  // ============ TTS 语音合成 (同步，用于聊天) ============

  /// 从流式文本中提取新完成的句子并加入 TTS 队列
  void _feedTtsQueue(String fullText) {
    if (!ref.read(ttsEnabledProvider)) {
      debugPrint('[TTS] _feedTtsQueue skipped: ttsEnabled=false');
      return;
    }

    // Guard: fullText may reset between tool-call rounds (chat_repository line 300),
    // while _lastTtsText persists in the session. Reset if out of sync.
    if (_lastTtsText.length > fullText.length ||
        !fullText.startsWith(_lastTtsText)) {
      _lastTtsText = '';
    }

    final newText = fullText.substring(_lastTtsText.length);
    if (newText.isEmpty) return;

    // 优先按标点切割完整句子（播报更自然），无标点时用较大阈值兜底，
    // 避免长句无标点导致 TTS 迟迟不启动。
    final punctMatch = RegExp(r'[。！？\n，；：、…]').firstMatch(newText);
    final punctEnd = punctMatch != null ? punctMatch.start + 1 : -1;
    const minLen = 30;

    int cutAt;
    if (punctEnd > 0) {
      cutAt = punctEnd;
    } else if (newText.length >= minLen) {
      cutAt = minLen;
    } else {
      return;
    }

    final chunk = newText.substring(0, cutAt).trim();
    _lastTtsText = fullText.substring(0, _lastTtsText.length + cutAt);
    if (chunk.isNotEmpty && _ttsSentTexts.add(chunk)) {
      _ttsQueue.add(chunk);
      _processTtsQueue();
    }
  }

  /// 发送剩余文本到 TTS 队列（流式结束后调用）
  void _flushTtsQueue(String fullText) {
    if (!ref.read(ttsEnabledProvider)) return;
    if (_lastTtsText.length > fullText.length ||
        !fullText.startsWith(_lastTtsText)) {
      _lastTtsText = '';
    }
    final remaining = fullText.substring(_lastTtsText.length).trim();
    if (remaining.isNotEmpty && _ttsSentTexts.add(remaining)) {
      _ttsQueue.add(remaining);
      _processTtsQueue();
    }
    _lastTtsText = '';
  }

  /// 在 LLM 思考阶段预热 TTS 客户端（跳过后续 SharedPreferences 和 HTTP 连接建立）
  void _prewarmTts() {
    final client = ref.read(minimaxClientProvider);
    if (client.apiKey.isEmpty) return;
    // API Key 变化时刷新客户端（设置页切换密钥后立即生效）
    if (_ttsClient != null &&
        _ttsClient!.apiKey == client.apiKey &&
        _ttsClient!.baseUrl == client.baseUrl) {
      return;
    }
    _ttsClient = MinimaxClient(
      apiKey: client.apiKey,
      baseUrl: client.baseUrl);
  }

  Future<void> _processTtsQueue() async {
    if (_ttsProcessing || _ttsQueue.isEmpty) return;
    _ttsProcessing = true;
    _ttsCanceled = false;
    _isPlayingTTS = true;
    final generation = _ttsGeneration;
    if (mounted) setState(() {});

    try {
      final client = _ttsClient ?? MinimaxClient(
        apiKey: ref.read(minimaxClientProvider).apiKey,
        baseUrl: ref.read(minimaxClientProvider).baseUrl);
      _ttsClient ??= client;

      if (client.apiKey.isEmpty) return;

      final ttsModel = ref.read(ttsModelProvider);
      final ttsVoice = ref.read(ttsVoiceProvider);

      while (_ttsQueue.isNotEmpty && !_ttsCanceled) {
        if (generation != _ttsGeneration) return;
        final text = _ttsQueue.removeAt(0);
        if (text.isEmpty) continue;

        // 1. 获取 TTS 音频
        final bytes = await _fetchTtsAudioBytes(client, text, ttsModel, ttsVoice);
        if (_ttsCanceled || bytes == null) continue;
        if (generation != _ttsGeneration) return;

        // 2. 等待上一段播完
        final prevCompleter = _ttsPlaybackCompleter;
        if (prevCompleter != null) {
          await prevCompleter.future.timeout(const Duration(seconds: 60));
        }
        if (_ttsCanceled || generation != _ttsGeneration) return;

        // 3. 播放当前段
        await _audioPlayer.stop();
        await _audioPlayer.play(BytesSource(bytes));

        // 4. 清理旧 completer
        if (prevCompleter != null && !prevCompleter.isCompleted) {
          prevCompleter.complete();
        }

        // 5. 为当前段创建新的完成信号，使用 onPlayerComplete（专用流，比 onPlayerStateChanged 更可靠）
        final playbackCompleter = Completer<void>();
        _ttsPlaybackCompleter = playbackCompleter;
        _ttsPlayerSubscription?.cancel();
        _ttsPlayerSubscription = _audioPlayer.onPlayerComplete.listen((_) {
          if (!playbackCompleter.isCompleted) {
            playbackCompleter.complete();
          }
        });
      }

      // 等最后一段播完
      final lastCompleter = _ttsPlaybackCompleter;
      if (lastCompleter != null) {
        await lastCompleter.future.timeout(const Duration(seconds: 60));
      }
    } catch (e) {
      debugPrint('TTS queue error: $e');
    } finally {
      _isPlayingTTS = false;
      _ttsProcessing = false;
      _ttsCanceled = false;
      _ttsPlayerSubscription?.cancel();
      _ttsPlayerSubscription = null;
      _ttsPlaybackCompleter = null;
      // 兜底：finally 执行前可能有新文本被 _flushTtsQueue 入队，
      // 而当时 _ttsProcessing 尚为 true 导致新 _processTtsQueue 被挡掉。
      // 用 microtask 延迟重试，确保队列残留项被处理。
      if (_ttsQueue.isNotEmpty && !_ttsCanceled) {
        Future.microtask(() => _processTtsQueue());
      }
      if (mounted) setState(() {});
    }
  }

  /// 辅助方法：调用 TTS API 获取完整音频字节
  Future<Uint8List?> _fetchTtsAudioBytes(
      MinimaxClient client, String text, String model, String voice) async {
    final hexChunks = <String>[];
    final stream = client.textToAudioStream(
        text: text, model: model, voiceId: voice, speed: 1.0);

    await for (final chunk in stream) {
      if (_ttsCanceled) return null;
      final audio = chunk['audio'] as String? ?? '';
      if (audio.isNotEmpty) hexChunks.add(audio);
    }

    if (hexChunks.isEmpty) return null;
    return _hexToBytes(hexChunks.join());
  }

  void _stopTts() {
    _ttsGeneration++;  // 废弃正在运行的 _processTtsQueue 实例
    _ttsCanceled = true;
    _ttsQueue.clear();
    _audioPlayer.stop();
    _isPlayingTTS = false;
    _ttsProcessing = false;
    _ttsPlaybackCompleter?.complete();
    _ttsPlaybackCompleter = null;
    if (mounted) setState(() {});
  }

  static Uint8List _hexToBytes(String hex) {
    final bytes = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      final byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (byte != null) bytes.add(byte);
    }
    return Uint8List.fromList(bytes);
  }

  Future<void> _performManualCompress() async {
    if (_currentConversationId == null) {
      _showSnackBar('请先发送一条消息');
      return;
    }

    final status = _contextManager.getStatus();
    if (_messages.length < 2) {
      _showSnackBar('消息太少，无需压缩');
      return;
    }

    // 确认压缩
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PixelTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: PixelTheme.pixelBorder, width: 2)),
        title: const Row(
          children: [
            Icon(Icons.compress, color: PixelTheme.primary, size: 20),
            SizedBox(width: 8),
            Text('🔒 上下文压缩',
                style: TextStyle(fontFamily: 'monospace', fontSize: 16)),
          ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前上下文: ${status.description}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 8),
            Text('消息数量: ${_messages.length}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 12),
            const Text('将旧消息压缩为摘要，注入上下文。消息记录永久保留不会删除。',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(fontFamily: 'monospace'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('压缩', style: TextStyle(fontFamily: 'monospace'))),
        ]));

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _isGenerating = false;
    });
    try {
      _addLog('INFO', '开始手动压缩上下文');
      await _rollingSummarize();
      final afterStatus = _contextManager.getStatus();
      _addLog('INFO', '手动压缩完成: ${afterStatus.description}');

      if (mounted) {
        _showSnackBar('压缩完成: ${afterStatus.description}');
      }
    } catch (e, st) {
      _addLog('ERROR', '手动压缩失败', e, st);
      if (mounted) {
        _showError('压缩失败: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _stopGenerating() {
    // 先暂停，阻断所有信息传给智能体
    _pauseToken.pause();
    _currentCancelToken?.cancel();
    _currentCancelToken = null;
    _streamInterrupted = true;
    _stopTts();
    if (_currentConversationId != null) {
      ref
          .read(agentSessionProvider.notifier)
          .setGenerating(_currentConversationId!, false);
    }
    _session.isGenerating = false;
    setState(() {
      _isLoading = false;
      _isGenerating = false;
    });
    _sessionStateMachine.reset();
  }

  /// 处理继续生成（断点恢复）
  Future<void> _handleResume(String truncatedMessageId) async {
    final repo = ref.read(chatRepositoryProvider);
    final truncatedMsg = _messages.firstWhere(
      (m) => m.id == truncatedMessageId,
      orElse: () => throw Exception(
          'Message not found: $truncatedMessageId / 消息不存在: $truncatedMessageId'));

    // 检查是否有依赖此消息的后续消息
    final dependentMessages = _messages
        .where(
          (m) => m.dependsOn == truncatedMessageId)
        .toList();

    if (dependentMessages.isNotEmpty) {
      // 存在依赖消息，提示用户
      final shouldResume = await _showContextConflictDialog();
      if (!shouldResume) {
        // 用户选择不恢复，清除依赖消息
        for (final dep in dependentMessages) {
          _messages.removeWhere((m) => m.id == dep.id);
        }
        setState(() {});
      }
    }

    // 构造恢复请求
    _transitionState(StreamState.resumed);

    // 加载 checkpoint 中的完整上下文（如果存在）
    final checkpoint = await repo.getPauseCheckpoint(truncatedMessageId);
    List<Map<String, String>> resumeHistory = [];

    if (checkpoint != null && checkpoint['context_data'] != null) {
      // 有 checkpoint：从 context_snapshot 加载完整 apiMessages 快照
      final decoded = jsonDecode(checkpoint['context_data'] as String);
      if (decoded is List) {
        for (final m in decoded) {
          if (m is Map<String, dynamic>) {
            resumeHistory
                .add(m.map((k, v) => MapEntry(k, v?.toString() ?? '')));
          }
        }
      }
    }

    // 简单的继续 prompt（即使有 checkpoint 也保留，用于追加新内容）
    final resumeContent = checkpoint != null
        ? '请继续输出上一次中断后的内容，保持自然衔接。'
        : '请继续输出上一次中断后的内容，保持自然衔接。\n\n--- 已生成内容 ---\n${truncatedMsg.partialContent ?? truncatedMsg.content}\n--- 结束 ---';

    // 保存用户点击继续的消息（跳过 user 消息添加，直接用 checkpoint 的 apiMessages）
    final useCheckpointMode = checkpoint != null;

    // 创建新的助手消息，标记依赖
    final newMsgId = 'resume_${DateTime.now().millisecondsSinceEpoch}';
    final resumeMsg = ChatMessage(
      id: newMsgId,
      conversationId: _currentConversationId!,
      role: MessageRole.assistant,
      content: '',
      createdAt: DateTime.now(),
      streamState: StreamState.streaming.name,
      dependsOn: truncatedMessageId,
      messageVersion: 1);

    _messages.add(resumeMsg);
    _recordDependency(truncatedMessageId, newMsgId);

    // 更新截断消息的版本
    await repo.updateMessageVersion(
        truncatedMessageId, truncatedMsg.messageVersion + 1);

    setState(() {
      _isGenerating = true;
      _isLoading = true;
    });
    _session.isGenerating = true;
    ref
        .read(agentSessionProvider.notifier)
        .setGenerating(_currentConversationId!, true);

    try {
      // 获取系统提示词
      final settings = SettingsRepository();
      final browserTabResume = ref.read(browserActiveTabProvider);
      final browserTabsResume = ref.read(browserTabsProvider);
      final systemPrompt = await settings.buildSystemContent(
        browserTitle: browserTabResume?.title,
        browserUrl: browserTabResume?.url,
        browserTabCount: browserTabsResume.length);
      final temperature = await settings.getTemperature();
      final maxTokens = await settings.getMaxTokens();
      final thinkingBudget = await settings.getThinkingBudget();
      final toolChoiceStr = await settings.getToolChoice();
      final toolChoice =
          toolChoiceStr == 'any' ? <String, dynamic>{'type': 'any'} : null;

      // 流式发送（resumeFromCheckpoint=true 时跳过 history 构建，直接用 checkpoint 的 apiMessages）
      final stream = repo.sendMessageStreamNative(
        conversationId: _currentConversationId!,
        message: useCheckpointMode ? '' : resumeContent,
        systemPrompt: systemPrompt,
        history: useCheckpointMode ? null : resumeHistory,
        
        temperature: temperature,
        maxTokens: maxTokens,
        thinkingBudgetTokens: thinkingBudget,
        executeTool: (_, __) async => const ToolResult(
            toolName: '', success: false, output: '', error: 'not available'),
        messageId: newMsgId,
        skipSaveUserMessage: true,
        resumeFromCheckpoint: useCheckpointMode,
        hookPipeline: _hookPipeline,
        activeSkills: _activeSkills);

      DateTime lastUpdate = DateTime.now();
      const minInterval = Duration(milliseconds: 50);
      String resumeFullContent = '';
      String resumeFullThinking = '';

      await for (final chunk in stream) {
        final now = DateTime.now();
        final shouldUpdate = now.difference(lastUpdate) >= minInterval;

        resumeFullContent = chunk.content;
        if (chunk.thinking != null && chunk.thinking!.isNotEmpty) {
          resumeFullThinking = chunk.thinking!;
        }

        // 更新消息内容
        final index = _messages.indexWhere((m) => m.id == newMsgId);
        if (index >= 0) {
          _messages[index] = _messages[index].copyWith(
            content: chunk.content,
            partialContent: chunk.content);
        }

        if (shouldUpdate) {
          lastUpdate = now;
          setState(() {});
          _scrollToBottom();
        }
      }

      _transitionState(StreamState.completed);
      _onMessageCompleted(newMsgId);

      // 保存恢复生成的消息到数据库
      if (resumeFullContent.isNotEmpty) {
        await repo.addMessage(
            _currentConversationId!, 'assistant', resumeFullContent,
            thinking: resumeFullThinking.isNotEmpty ? resumeFullThinking : null);
      }

      // 更新原始截断消息为已完成
      await repo.updatePartialMessage(
        messageId: truncatedMessageId,
        conversationId: _currentConversationId!,
        partialContent: truncatedMsg.partialContent ?? truncatedMsg.content,
        tokenOffset: truncatedMsg.tokenOffset,
        isTruncated: false,
        streamState: StreamState.completed.name);
      // Refresh drawer indicator — may clear the warning icon
      await _refreshInterruptedStatus();
    } catch (e) {
      print('[chat] error: \$e');
      _addLog('ERROR', '恢复生成失败', e);
      _transitionState(StreamState.failed);
      if (mounted) {
        _showError('恢复失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  /// 构建排除指定消息的上下文
  List<Map<String, String>> _buildContextWithoutTruncated(String? excludeId) {
    final result = <Map<String, String>>[];
    for (final msg in _messages) {
      if (msg.id == excludeId) continue;
      // 对于截断中的消息，优先用 partialContent；跳过空内容消息
      final content = msg.partialContent?.isNotEmpty == true
          ? msg.partialContent!
          : msg.content;
      if (content.isEmpty) continue;
      result.add({'role': msg.role.name, 'content': content});
    }
    return result;
  }

  /// 显示上下文冲突对话框
  Future<bool> _showContextConflictDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PixelTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: PixelTheme.pixelBorder, width: 2)),
        title: const Text('⚠️ 上下文冲突'),
        content: const Text(
          '检测到截断消息后有后续消息，继续生成可能会导致上下文不一致。\n\n'
          '是否清除后续消息并继续生成？',
          style: TextStyle(fontFamily: 'monospace')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('继续生成')),
        ]));
    return result ?? false;
  }

  /// Scheme 1: 工具执行确认对话框 — 改为 Overlay 叠加视图，显示在输入框上方

  /// 弹出工具菜单（文件管理、定时任务、浏览器）
  void _showToolsMenu(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? PixelTheme.darkSurface : Colors.white;
    final textColor =
        isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final iconColor =
        isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary;

    _inputFocusNode.unfocus();
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(9999, 48, 16, 0),
      color: bgColor,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          value: 'file',
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_outlined, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text('文件管理',
                  style: TextStyle(
                      fontFamily: 'monospace', fontSize: 12, color: textColor)),
            ])),
        PopupMenuItem(
          value: 'task',
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text('定时任务',
                  style: TextStyle(
                      fontFamily: 'monospace', fontSize: 12, color: textColor)),
            ])),
        PopupMenuItem(
          value: 'browser',
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.language_outlined, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text('浏览器',
                  style: TextStyle(
                      fontFamily: 'monospace', fontSize: 12, color: textColor)),
            ])),
      ]).then((value) {
      switch (value) {
        case 'file':
          FileTreeModal.show(context);
        case 'task':
          TaskPanel.show(context);
        case 'browser':
          ref.read(browserEngineActiveProvider.notifier).state = true;
          ref.read(browserPanelVisibleProvider.notifier).state = true;
      }
    });
  }

  /// 处理截断恢复按钮点击
  void _onResumeTruncation(ChatMessage message) {
    if (_isGenerating) {
      _showSnackBar('正在生成中，请稍后');
      return;
    }
    _handleResume(message.id);
  }

  /// 处理结束截断（用户选择不继续）
  void _onDismissTruncation(String messageId) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index >= 0) {
      _messages[index] = _messages[index].copyWith(
        streamState: StreamState.completed.name);
      setState(() {});
    }
    _refreshInterruptedStatus();
  }

  /// 检查当前会话是否还有中断消息，更新抽屉指示器
  Future<void> _refreshInterruptedStatus() async {
    if (_currentConversationId == null) return;
    final db = ref.read(databaseHelperProvider);
    final hasInterrupted =
        await db.hasInterruptedMessages(_currentConversationId!);
    if (!hasInterrupted) {
      _interruptedConvIds.remove(_currentConversationId!);
    }
  }

  /// 优化提示词
  Future<void> _optimizePrompt() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      _showSnackBar('请先输入内容');
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // 显示顶 部 SnackBar（处理优化中状态）
    final optimizationSnackBar = SnackBar(
      margin: const EdgeInsets.all(16),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: isDark ? PixelTheme.darkSurface : PixelTheme.surface,
      content: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(
                  isDark ? PixelTheme.darkPrimary : PixelTheme.primary))),
          const SizedBox(width: 12),
          Text(
            '正在优化提示词...',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color:
                  isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
        ]),
      duration: const Duration(seconds: 30));

    scaffoldMessenger.showSnackBar(optimizationSnackBar);

    setState(() {
      _isLoading = true;
      _isGenerating = false;
    });

    try {
      await ref.read(minimaxClientProvider.notifier).loadFromSettings();
      final client = ref.read(minimaxClientProvider);

      const optimizePrompt = '<instructions>\n'
          '改进以下提示词，使其更清晰、具体、可执行。\n'
          '保留原意和所有关键信息，不要添加用户没提到的功能或需求。\n'
          '- 模糊措辞 → 具体描述（"搞好一点" → "对齐间距，统一字体大小"）\n'
          '- 缺少约束 → 补充必要限定（范围、数量、格式、受众）\n'
          '- 结构混乱 → 拆分为清晰的步骤或要点\n'
          '- 冗长重复 → 合并同类信息，删废话\n'
          '回复规则：只输出优化后的完整文本，不加任何解释、标签、标记。\n'
          '</instructions>\n\n'
          '<content>\n'
          'TEXT_PLACEHOLDER\n'
          '</content>';

      _addLog('DEBUG', '开始优化提示词');

      var raw = await client.chatCollect(
        optimizePrompt.replaceFirst('TEXT_PLACEHOLDER', text),
        history: []);

      // 过滤思考内容（最快方法：正则移除所有<think>...</think>块）
      raw = _filterThinking(raw);

      // 移除任何残留的XML标签
      raw = raw.replaceAll(RegExp(r'<\/?[a-zA-Z][^>]*>'), '');
      // 移除优化提示词模板残留
      raw = raw.replaceAll(
          RegExp(r'\[OPTIMIZED\]|\[/OPTIM\]|\[/OPTIMIZED\]|\[TIPS\]|\[/TIPS\]'),
          '');
      raw = raw.trim();

      if (mounted && raw.isNotEmpty) {
        // 直接填充到输入框
        _messageController.text = raw;
        _messageController.selection =
            TextSelection.collapsed(offset: raw.length);

        // 隐藏处理中 SnackBar，显示成功 SnackBar
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            margin: const EdgeInsets.all(16),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor:
                isDark ? PixelTheme.darkSurface : PixelTheme.surface,
            content: Row(
              children: [
                Icon(Icons.check_circle,
                    color: isDark ? PixelTheme.darkPrimary : PixelTheme.primary,
                    size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '已填充到输入框',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: isDark
                          ? PixelTheme.darkPrimaryText
                          : PixelTheme.textPrimary))),
              ]),
            duration: const Duration(seconds: 2)));
      }
    } catch (e) {
      print('[chat] error: \$e');
      _addLog('ERROR', '优化提示词失败: $e');
      scaffoldMessenger.hideCurrentSnackBar();
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            margin: const EdgeInsets.all(16),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor:
                isDark ? const Color(0xFF2D1B1B) : const Color(0xFFFEF2F2),
            content: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: PixelTheme.error, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '优化失败: $e',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: isDark
                          ? PixelTheme.darkPrimaryText
                          : PixelTheme.textPrimary))),
              ]),
            duration: const Duration(seconds: 3)));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildConversationDrawer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;

    return Drawer(
      width: screenWidth * 0.6,
      backgroundColor: isDark ? PixelTheme.darkSurface : PixelTheme.surface,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: _ConversationDrawerContent(
        conversations: _showTaskConversations
            ? (_taskConversation != null ? [_taskConversation!] : [])
            : _conversations,
        currentConversationId: _currentConversationId,
        interruptedConvIds: _interruptedConvIds,
        showTaskMode: _showTaskConversations,
        taskConversation: _taskConversation,
        onToggleMode: () =>
            setState(() => _showTaskConversations = !_showTaskConversations),
        onSelectConversation: (conv) {
          Navigator.pop(context);
          _saveContextToDb(); // Save current context before switching away
          // NOTE: Don't cancel the old session's token — let it keep running in background
          setState(() {
            _currentConversationId = conv.id;
            _currentSummary = conv.summary ?? '';
            _userScrolledAway = false;
          });
          _logger.switchConversation(conv.id);
          _addLog('INFO', '切换到会话: ${conv.title}');
          _loadMessages(); // Creates/activates session for this conversation
        },
        onDeleteConversation: (conv) async {
          // If this conversation has a running agent, cancel it first
          final session = _sessions[conv.id];
          if (session != null && session.isGenerating) {
            session.cancelToken?.cancel();
            ref
                .read(agentSessionProvider.notifier)
                .setGenerating(conv.id, false);
          }
          _sessions.remove(conv.id);
          await ref.read(chatRepositoryProvider).deleteConversation(conv.id);
          if (_currentConversationId == conv.id) {
            if (mounted) {
              setState(() {
                _currentConversationId = null;
                _messages = [];
              });
            }
          }
          await _loadConversations();
        }));
  }

  /// Reset UI state for a fresh conversation. Does NOT cancel the old session's
  /// CancelToken — background agents keep running independently.
  void _resetChatState() {
    // Don't cancel _currentCancelToken — let background sessions keep running
    _currentCancelToken = null;
    _isLoading = false;
    _isGenerating = false;
    _currentStreamState = StreamState.idle;
    _streamInterrupted = false;
    _streamingContent.clear();
    _attachments.clear();
    _messageController.clear();
    _logs.clear();
    _contextManager.reset();
    
    
    
    _activeLenses.clear();
    _lensDecayCounter = 0;
    _activeSkills.clear();
    _skillDecayCounters.clear();
    _lastInjectedSkills.clear();
    _skillUsageThisTurn.clear();
    MemoryCache.instance.remove(_memCategory, 'active_skills');
    MemoryCache.instance.remove(_memCategory, 'skill_decay');
    ToolExecutor.clearActiveDocument();
  }

  Future<void> _saveContextToDb() async {
    if (_currentConversationId == null) return;
    try {
      final repo = ref.read(chatRepositoryProvider);
      final status = _contextManager.getStatus();
      await repo.saveContext(
        _currentConversationId!,
        tokenCount: status.usedTokens,
        messageCount: _messages.where((m) => m.role != MessageRole.tool).length);
    } catch (e) {
      print('[chat] error: \$e');
      // Silently fail — context save is best-effort, not critical
    }
  }

  Timer? _consolidationTimer;

  /// 启动记忆整合定时任务（每 12 小时）。
  void _startMemoryConsolidation() {
    _consolidationTimer?.cancel();
    final consolidator = MemoryConsolidator(MemoryCache.instance);

    // 首次启动延迟 5 分钟后执行
    Future.delayed(const Duration(minutes: 5), () async {
      try {
        final report = await consolidator.runOnce();
        _addLog('INFO', '记忆整合: $report');
      } catch (_) {}
    });

    // 后续每 12 小时执行一次
    _consolidationTimer = Timer.periodic(const Duration(hours: 12), (_) async {
      try {
        final report = await consolidator.runOnce();
        _addLog('INFO', '记忆整合: $report');
      } catch (_) {}
    });
  }

  Future<void> _newConversation() async {
    await _saveContextToDb();
    // Don't cancel old session's token — let it keep running in background
    _currentConversationId = null;
    // Create a fresh placeholder session for empty state
    _activeSession = ConversationSession(conversationId: '__new__');
    _attachments.clear();
    _messageController.clear();
    
    
    _isGenerating = false;
    MemoryCache.instance.remove(_memCategory, 'active_skills');
    MemoryCache.instance.remove(_memCategory, 'skill_decay');
    ToolExecutor.clearActiveDocument();
    setState(() {});
    _logger.switchConversation(null);
    await _loadConversations();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
        settingsChangedProvider, (prev, next) => _checkSettingsChanged());
    ref.listen(pendingChatInputProvider, (prev, next) {
      if (next != null && next.isNotEmpty) {
        _messageController.text = next;
        ref.read(pendingChatInputProvider.notifier).state = null;
      }
    });
    ref.listen<int>(navigationIndexProvider, (prev, next) {
      if (prev == 0 && next != 0) {
        _inputFocusNode.unfocus();
      }
    });
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final iconColor =
        isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary;
    final dividerColor = isDark
        ? PixelTheme.darkBorderSubtle
        : Colors.grey.withValues(alpha: 0.12);

    final browserEngineActive = ref.watch(browserEngineActiveProvider);
    final browserPanelVisible = ref.watch(browserPanelVisibleProvider);

    return Stack(children: [
      Scaffold(
        key: _scaffoldKey,
        resizeToAvoidBottomInset: false,
        drawer: _buildConversationDrawer(),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 自定义顶部栏 - 44dp 紧凑高度
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    // 菜单按钮
                    PixelTopBarButton(
                      icon: Icons.menu,
                      onTap: () {
                        _inputFocusNode.unfocus();
                        _scaffoldKey.currentState?.openDrawer();
                      },
                      iconColor: iconColor),
                    // 标题（Expanded 居中）
                    const Expanded(child: SizedBox.shrink()),
                    // 新建会话按钮
                    PixelTopBarButton(
                      icon: Icons.add,
                      onTap: _newConversation,
                      iconColor: iconColor),
                    const SizedBox(width: 4),
                    // 工具菜单（文件管理、定时任务、浏览器）
                    PixelTopBarButton(
                      icon: Icons.more_horiz,
                      onTap: () => _showToolsMenu(context),
                      iconColor: iconColor),
                    const SizedBox(width: 4),
                    // 日志按钮
                    PixelTopBarButton(
                      icon: Icons.article_outlined,
                      onTap: () => showDialog(
                        context: context,
                        builder: (ctx) => _LogDialog(
                          logs: _logs,
                          onClear: () => setState(() => _logs.clear()))),
                      iconColor: iconColor),
                  ])),
              // 底部分割线
              Divider(height: 1, thickness: 0.5, color: dividerColor),
              // API Key 未配置横幅
              if (!_isConfigured)
                _ApiKeyBanner(
                  onTap: () => widget.onNavigateToSettings?.call()),
              // Token Plan 错误横幅
              if (_tokenPlanErrorMessage != null)
                _TokenPlanBanner(
                  message: _tokenPlanErrorMessage!,
                  onDismiss: _dismissTokenPlanBanner),
              // 内容区域
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: _messages.isEmpty
                          ? _buildEmptyState()
                          : _buildMessageList()),
                    if (_interactivePrompt != null) _buildInteractiveCard(),
                    if (_isTtsActive)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: _stopTts,
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: PixelTheme.error.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.volume_off_rounded,
                                  size: 18, color: PixelTheme.error))))),
                    _buildAttachmentPreview(),
                    _buildInputArea(),
                  ])),
            ]))),
      // Persistent browser panel overlay
      if (browserEngineActive)
        Positioned(
          top: MediaQuery.of(context).size.height * 0.06,
          left: 0,
          right: 0,
          bottom: 0,
          child: PopScope(
            canPop: !browserPanelVisible,
            onPopInvokedWithResult: (didPop, _) {
              if (!browserPanelVisible || didPop) return;
              final tabs = ref.read(browserTabsProvider);
              final idx = ref.read(browserActiveTabIndexProvider);
              if (idx < tabs.length && tabs[idx].canGoBack) {
                final handler = ref.read(browserToolHandlerProvider);
                handler?.controllers[tabs[idx].id]?.goBack();
                return;
              }
              ref.read(browserPanelVisibleProvider.notifier).state = false;
            },
            child: Offstage(
              offstage: !browserPanelVisible,
              child: const BrowserPanel()))),
    ]);
  }

  String _buildPersonaLens(String userMessage, bool silent) {
    if (silent) return '';
    // 快速通道：仅关键词（用于视觉模式等同步场景）
    final personas = PersonaRegistry.detect(userMessage);
    if (personas.isEmpty) return '';
    _addLog('DEBUG', '透镜激活: ${personas.map((p) => p.lensLabel).join(' + ')}');
    return PersonaRegistry.buildLensPrompt(personas);
  }

  /// 混合透镜检测（带粘性）：同话题延续透镜，话题切才重新检测
  Future<String> _buildPersonaLensHybrid(String userMessage) async {
    // ── 粘性延续：当前话题是否延续上轮透镜 ──
    if (_activeLenses.isNotEmpty && _lensDecayCounter < _lensDecayMax) {
      final quick = PersonaRegistry.detectHybrid(userMessage);
      final quickIds = quick.map((s) => s.persona.id).toSet();
      final overlap = _activeLenses.intersection(quickIds);
      if (overlap.isNotEmpty || quick.isEmpty) {
        // 话题延续：重用上轮透镜
        _lensDecayCounter = 0;
        final personas = _activeLenses
            .map((id) => PersonaRegistry.all.firstWhere((p) => p.id == id))
            .toList();
        _addLog(
            'DEBUG', '透镜(粘): ${personas.map((p) => p.lensLabel).join(' + ')}');
        return PersonaRegistry.buildLensPrompt(personas);
      }
      // 话题切换 → 衰减
      _lensDecayCounter++;
    }

    // ── 重新检测 ──
    final scored = PersonaRegistry.detectHybrid(userMessage);
    if (scored.isEmpty) {
      _activeLenses.clear();
      _lensDecayCounter = 0;
      return '';
    }

    final first = scored.first;
    List<Persona> selected;

    if (first.confidence == LensConfidence.direct) {
      selected = scored.map((s) => s.persona).toList();
      _addLog(
          'DEBUG', '透镜(直): ${selected.map((p) => p.lensLabel).join(' + ')}');
    } else {
      _addLog('DEBUG',
          '透镜(LLM): 候选 ${scored.map((s) => s.persona.lensLabel).join(', ')}');
      try {
        final client = ref.read(minimaxClientProvider);
        final result = await _classifyLenses(client, userMessage, scored);
        if (result.isNotEmpty) {
          // Parse back to personas (result is a prompt string, extract by checking ids)
          selected = scored
              .where((s) => result.contains(s.persona.id))
              .map((s) => s.persona)
              .toList();
          if (selected.isEmpty) selected = [first.persona];
          _addLog('DEBUG',
              '透镜(LLM结果): ${selected.map((p) => p.lensLabel).join(' + ')}');
        } else {
          selected = [first.persona];
        }
      } catch (_) {
        selected = [first.persona];
      }
    }

    // 更新粘性状态
    _activeLenses = selected.map((p) => p.id).toSet();
    _lensDecayCounter = 0;
    return PersonaRegistry.buildLensPrompt(selected);
  }

  Future<String> _classifyLenses(
    MinimaxClient client,
    String userMessage,
    List<ScoredPersona> candidates) async {
    final ids = candidates.map((s) => s.persona.id).join(', ');
    final labels = candidates
        .map((s) => '${s.persona.id}(${s.persona.lensLabel})')
        .join(', ');
    final response = await client.chatCollect(
      '''从以下思维透镜中选择最适合回答这个问题的 1-2 个（只回复 id，逗号分隔，不要解释）：
$labels

用户: $userMessage
透镜:''',
      systemPrompt: '你是精准的意图分类器。只看用户问题的本质，不看表面用词。只回复 id。',
      maxTokens: 20,
      thinkingBudgetTokens: 0);

    // Parse: extract only valid persona IDs
    final resultIds = <String>{};
    for (final c in candidates) {
      if (response.contains(c.persona.id)) resultIds.add(c.persona.id);
    }
    if (resultIds.isEmpty) return '';

    final selected = candidates
        .where((s) => resultIds.contains(s.persona.id))
        .map((s) => s.persona)
        .take(2)
        .toList();
    return PersonaRegistry.buildLensPrompt(selected);
  }

  /// 技能透镜：关键词初筛 + 跨轮持久化 + 多技能竞争 + 反馈学习
  ///
  /// 1. 从 MemoryCache 恢复上轮已激活的技能（跨轮粘性）
  /// 2. 对当前消息做关键词匹配，计算评分
  /// 3. 合并活跃集 + 新匹配 → 按评分排序 → 最多注入 3 个完整提示
  /// 4. 未匹配的活跃技能累计衰减，超阈值自动失活
  /// 5. 本轮结束后检测工具调用情况，写入技能统计到 MemoryCache
  /// 构建 Skill 目录（替代旧的 _buildSkillLens 关键词匹配）。
  /// LLM 自行判断是否需要某个 Skill，需要时调用 skill_load 加载。
  String _buildSkillCatalog() {
    _restoreActiveSkillsFromMemory();

    final skills = SkillRegistry.instance.enabledSkills;
    if (skills.isEmpty) return '';

    final buf = StringBuffer();
    buf.writeln();
    buf.writeln('## 可用专业能力模块');
    buf.writeln('当你需要某个领域的专业知识时，调用 skill_load 加载对应模块。');
    buf.writeln('加载后该模块的完整工作流程和工具指引会自动注入上下文。');
    buf.writeln();
    for (final skill in skills) {
      buf.writeln('- **${skill.name}**: ${skill.description}');
    }
    buf.writeln();
    // 列出当前已加载的技能
    if (_activeSkills.isNotEmpty) {
      buf.writeln('当前已加载: ${_activeSkills.join(", ")}');
    }

    _lastInjectedSkills = Set.from(_activeSkills);
    _skillUsageThisTurn.clear();
    _persistActiveSkillsToMemory();
    return buf.toString();
  }

  // ============================================
  //  技能持久化 & 反馈 helper
  // ============================================

  static const _memCategory = 'session';

  /// 从 MemoryCache 恢复活跃技能
  void _restoreActiveSkillsFromMemory() {
    if (_activeSkills.isNotEmpty) return; // 已加载
    final raw = MemoryCache.instance.get(_memCategory, 'active_skills');
    if (raw != null && raw.isNotEmpty) {
      _activeSkills = raw.split(',').toSet();
      // 恢复衰减计数器
      final decayRaw = MemoryCache.instance.get(_memCategory, 'skill_decay');
      if (decayRaw != null && decayRaw.isNotEmpty) {
        try {
          final map = jsonDecode(decayRaw) as Map<String, dynamic>;
          _skillDecayCounters = map.map((k, v) => MapEntry(k, v as int));
        } catch (_) {}
      }
    }
  }

  /// 将活跃技能持久化到 MemoryCache
  void _persistActiveSkillsToMemory() {
    if (_activeSkills.isEmpty) {
      MemoryCache.instance.remove(_memCategory, 'active_skills');
      MemoryCache.instance.remove(_memCategory, 'skill_decay');
    } else {
      MemoryCache.instance
          .set(_memCategory, 'active_skills', _activeSkills.join(','));
      MemoryCache.instance
          .set(_memCategory, 'skill_decay', jsonEncode(_skillDecayCounters));
    }
  }

  /// 加载历史上有用的技能名集合
  Set<String> _loadHistoricallyUseful() {
    final raw = MemoryCache.instance.get('skill_stats', 'useful_names');
    if (raw != null && raw.isNotEmpty) {
      return raw.split(',').toSet();
    }
    return {};
  }

  /// 反馈：检查上轮注入的技能是否有工具被实际调用
  void _runSkillFeedback() {
    if (_lastInjectedSkills.isEmpty) return;

    for (final skillName in _lastInjectedSkills) {
      final skill = SkillRegistry.instance.getSkill(skillName);
      if (skill == null) continue;

      final used = (_skillUsageThisTurn[skillName] ?? 0) > 0;
      _updateSkillStats(skillName, used);
    }

    // 未被使用的技能加速衰减
    for (final skillName in _lastInjectedSkills) {
      if ((_skillUsageThisTurn[skillName] ?? 0) == 0) {
        _skillDecayCounters[skillName] =
            (_skillDecayCounters[skillName] ?? 0) + 1;
      }
    }
  }

  /// 更新技能统计数据到 MemoryCache
  void _updateSkillStats(String skillName, bool wasUseful) {
    final raw = MemoryCache.instance.get('skill_stats', skillName);
    int activations = 0;
    int usefulTurns = 0;
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        activations = map['activations'] as int? ?? 0;
        usefulTurns = map['usefulTurns'] as int? ?? 0;
      } catch (_) {}
    }
    activations++;
    if (wasUseful) usefulTurns++;

    MemoryCache.instance.set(
        'skill_stats',
        skillName,
        jsonEncode({
          'activations': activations,
          'usefulTurns': usefulTurns,
        }));

    // 维护有用技能名列表（usefulTurns >= activations/2）
    final usefulNames = _loadHistoricallyUseful().toList();
    if (usefulTurns >= activations / 2 && !usefulNames.contains(skillName)) {
      usefulNames.add(skillName);
      MemoryCache.instance
          .set('skill_stats', 'useful_names', usefulNames.join(','));
    }
  }

  /// 供 _executeToolCallNative 调用的工具使用追踪
  void _trackSkillToolUsage(String toolName) {
    for (final skillName in _lastInjectedSkills) {
      final skill = SkillRegistry.instance.getSkill(skillName);
      if (skill != null && skill.suggestedTools.contains(toolName)) {
        _skillUsageThisTurn[skillName] =
            (_skillUsageThisTurn[skillName] ?? 0) + 1;
      }
    }
  }

  void _trackSkillToolUsageForSession(
      ConversationSession session, String toolName) {
    for (final skillName in session.lastInjectedSkills) {
      final skill = SkillRegistry.instance.getSkill(skillName);
      if (skill != null && skill.suggestedTools.contains(toolName)) {
        session.skillUsageThisTurn[skillName] =
            (session.skillUsageThisTurn[skillName] ?? 0) + 1;
      }
    }
  }

  Widget _buildEmptyState() {
    return const SizedBox.shrink();
  }

  Widget _buildMessageList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _visibleMessages.length,
      itemBuilder: (ctx, i) {
        final msg = _visibleMessages[i];
        final isLastFromUser = i == _visibleMessages.length - 1 ||
            _visibleMessages[i + 1].role == MessageRole.user;
        final isStreaming = _isGenerating &&
            i == _visibleMessages.length - 1 &&
            msg.role == MessageRole.assistant;

        final userMessages =
            _visibleMessages.where((m) => m.role == MessageRole.user).toList();
        final isLastUserMessage = msg.role == MessageRole.user &&
            userMessages.isNotEmpty &&
            userMessages.last.id == msg.id;

        return ChatBubble(
          key: ValueKey(msg.id),
          message: msg,
          isStreaming: isStreaming,
          onBacktrack: msg.isUser ? () => _backtrackTo(msg) : null,
          isBacktrackPending: _backtrackTargetId == msg.id,
          onLongPress: null);
      });
  }

  Widget _buildAttachmentPreview() {
    if (_attachments.isEmpty && !_isProcessingImage)
      return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = _attachments.length;

    if (_isProcessingImage && _attachments.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color:
              isDark ? PixelTheme.darkHighElevated : PixelTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text('正在处理图片...',
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: isDark
                      ? PixelTheme.darkSecondaryText
                      : PixelTheme.textSecondary)),
        ]));
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? PixelTheme.darkHighElevated : PixelTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // 标题栏：可点击收缩
        InkWell(
          borderRadius: BorderRadius.vertical(
              top: count > 1 ? const Radius.circular(12) : Radius.zero,
              bottom: _attachmentsExpanded && count > 1
                  ? Radius.zero
                  : const Radius.circular(12)),
          onTap: count > 1
              ? () =>
                  setState(() => _attachmentsExpanded = !_attachmentsExpanded)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(
                  count > 1
                      ? Icons.attach_file
                      : (_attachments.first.type == AttachmentType.image
                          ? Icons.image
                          : Icons.insert_drive_file),
                  size: 18,
                  color: isDark
                      ? PixelTheme.darkSecondaryText
                      : PixelTheme.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  count > 1 ? '$count 个附件' : _attachments.first.fileName,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: isDark ? PixelTheme.darkPrimaryText : null),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
              if (count > 1)
                AnimatedRotation(
                    turns: _attachmentsExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more,
                        size: 20,
                        color: isDark
                            ? PixelTheme.darkSecondaryText
                            : PixelTheme.textSecondary))
              else
                GestureDetector(
                  onTap: () => _removeAttachment(0),
                  child: Icon(Icons.close,
                      size: 18,
                      color: isDark
                          ? PixelTheme.darkSecondaryText
                          : PixelTheme.textSecondary)),
            ]))),
        // 展开列表
        if (count > 1 && _attachmentsExpanded)
          Column(
            children: _attachments.asMap().entries.map((e) {
              final i = e.key;
              final a = e.value;
              return _buildAttachmentRow(a, i, isDark);
            }).toList()),
      ]));
  }

  Widget _buildAttachmentRow(_AttachmentItem a, int index, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(
                color: isDark ? PixelTheme.darkBorderSubtle : Colors.black12,
                width: 0.5))),
      child: Row(children: [
        if (a.type == AttachmentType.image && a.thumbnailBytes != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              a.thumbnailBytes!,
              width: 28,
              height: 28,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(Icons.broken_image,
                  size: 20,
                  color:
                      isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted))),
        ] else if (a.type == AttachmentType.image)
          Icon(Icons.broken_image,
              size: 20,
              color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)
        else
          _buildFileTypeIcon(a.mimeType),
        const SizedBox(width: 8),
        Expanded(
          child: Text(a.fileName,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: isDark
                      ? PixelTheme.darkPrimaryText
                      : PixelTheme.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis)),
        Text(a.formattedSize,
            style: TextStyle(
                fontSize: 10,
                color:
                    isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => _removeAttachment(index),
          child: Icon(Icons.close,
              size: 16,
              color: isDark
                  ? PixelTheme.darkSecondaryText
                  : PixelTheme.textSecondary)),
      ]));
  }

  Widget _buildFileTypeIcon(String mimeType) {
    IconData icon;
    Color color;
    if (mimeType == 'application/pdf') {
      icon = Icons.picture_as_pdf;
      color = Colors.red;
    } else if (mimeType.contains('spreadsheet') || mimeType == 'text/csv') {
      icon = Icons.table_chart;
      color = Colors.green;
    } else if (mimeType.contains('presentation')) {
      icon = Icons.slideshow;
      color = Colors.orange;
    } else if (mimeType.contains('wordprocessing')) {
      icon = Icons.description;
      color = Colors.blue;
    } else if (mimeType.startsWith('text/')) {
      icon = Icons.article;
      color = Colors.teal;
    } else {
      icon = Icons.insert_drive_file;
      color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: color, size: 28));
  }

  void _clearPendingAttachment() {
    setState(() => _attachments.clear());
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  /// 将编排器状态格式化为用户可见的进度文本（用在 assistant 消息气泡中）
  String _formatOrchProgress({
    required OrchestratorPhase phase,
    required String currentLabel,
    required int completedCount,
    required int totalCount,
  }) {
    switch (phase) {
      case OrchestratorPhase.assessingComplexity:
        return '分析需求…';
      case OrchestratorPhase.decomposing:
        return totalCount > 0
            ? '拆解为 $totalCount 个子任务…'
            : '拆解任务…';
      case OrchestratorPhase.executing:
        final taskInfo = currentLabel.isNotEmpty ? ' — $currentLabel' : '';
        final step = (completedCount + 1).clamp(1, totalCount);
        return '第 $step/$totalCount 步$taskInfo';
      case OrchestratorPhase.synthesizing:
        return '汇总结果…';
      case OrchestratorPhase.completed:
      case OrchestratorPhase.failed:
        return '';
    }
  }

  Widget _buildInputArea() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor =
        isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary;

    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    // 扣掉底部导航栏高度(~65dp)，消除输入框与键盘之间的间隙
    final padBottom = keyboardH > 0 ? (8 + keyboardH - 65.0).clamp(0.0, double.infinity) : 8.0;
    return Container(
      padding: EdgeInsets.fromLTRB(4, 8, 4, padBottom),
      decoration: BoxDecoration(
        color: isDark ? PixelTheme.darkBase : PixelTheme.surface,
        border: isDark
            ? const Border(
                top: BorderSide(color: PixelTheme.darkBorderSubtle, width: 1))
            : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2)),
              ]),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 主输入框区域 - 紧凑一体化设计
            GestureDetector(
              onLongPress: _messageController.text.trim().isNotEmpty
                  ? _optimizePrompt
                  : null,
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? PixelTheme.darkHighElevated
                      : PixelTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? PixelTheme.darkBorderDefault
                        : PixelTheme.pixelBorder.withValues(alpha: 0.5),
                    width: 0.5)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 主输入行
                    Row(
                      children: [
                        // 左侧"+"按钮 - 展开更多功能
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: _PlusMenuButton(
                            onCameraPressed:
                                (!_isLoading && !_sessionStateMachine.isActive)
                                    ? () => _pickImageFromCamera()
                                    : null,
                            onImagePressed:
                                (!_isLoading && !_sessionStateMachine.isActive)
                                    ? _pickImage
                                    : null,
                            onFilePressed:
                                (!_isLoading && !_sessionStateMachine.isActive)
                                    ? _pickFile
                                    : null)),
                        // 输入框
                        Expanded(
                          child: TextField(
                            focusNode: _inputFocusNode,
                            onTap: () => _userTappedInput = true,
                            controller: _messageController,
                            maxLines: 5,
                            minLines: 1,
                            enabled:
                                !_isLoading && !_sessionStateMachine.isActive,
                            textInputAction: TextInputAction.send,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              color: isDark ? PixelTheme.darkPrimaryText : null),
                            onSubmitted: (_) => _sendMessage(),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: '输入消息...',
                              hintStyle: TextStyle(
                                color: isDark
                                    ? PixelTheme.darkTextMuted
                                    : PixelTheme.textMuted,
                                fontSize: 14),
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              isDense: true,
                              suffixIcon:
                                  _messageController.text.trim().isNotEmpty
                                      ? IconButton(
                                          icon: Icon(Icons.auto_awesome,
                                              size: 18, color: iconColor),
                                          onPressed: _optimizePrompt,
                                          splashRadius: 16,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: 32, minHeight: 32))
                                      : null))),
                        // 右侧功能组
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 语音输入按钮
                            _MicButton(
                              isEnabled:
                                  !_isLoading && !_sessionStateMachine.isActive,
                              onResult: (text) {
                                if (text.isNotEmpty) {
                                  _messageController.text = text;
                                  _messageController.selection =
                                      TextSelection.fromPosition(
                                    TextPosition(offset: text.length));
                                }
                              }),
                            const SizedBox(width: 4),
                            // 发送/停止按钮
                            _SendButton(
                              isLoading: _isLoading && !_isGenerating,
                              isGenerating: _isGenerating,
                              enabled: _messageController.text.isNotEmpty ||
                                  _hasPendingAttachment,
                              onPressed: _sendMessage,
                              onStop: _stopGenerating),
                          ]),
                      ]),
                  ]))), // GestureDetector onLongPress
          ]));
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultColor =
        isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary;
    final highlightColor = isDark ? PixelTheme.darkPrimary : PixelTheme.primary;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: 22,
          color: defaultColor)));
  }

  bool _canSend() =>
      !_isLoading &&
      (_messageController.text.isNotEmpty || _hasPendingAttachment);

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut);
      }
    });
  }

  Future<void> _pickImage() async {
    try {
      final ok =
          await PermissionManager().request(context, AppPermission.storage);
      if (!ok) return;
      final picker = ImagePicker();
      final image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85);
      if (image == null) return;
      setState(() => _isProcessingImage = true);
      final bytes = await image.readAsBytes();
      final sizeError =
          FileUtils.validateFileSize(bytes.length, AttachmentType.image);
      if (sizeError != null) {
        _showError(sizeError);
        setState(() => _isProcessingImage = false);
        return;
      }
      final formatError = FileUtils.validateImageFormat(bytes);
      if (formatError != null) {
        _showError(formatError);
        setState(() => _isProcessingImage = false);
        return;
      }
      final base64 = base64Encode(bytes);
      if (!mounted) return;
      setState(() {
        _isProcessingImage = false;
        _attachments.add(_AttachmentItem(
          type: AttachmentType.image,
          base64: base64,
          fileName: image.name,
          mimeType: 'image/${image.path.split('.').last}',
          fileSize: bytes.length));
        _attachmentsExpanded = true;
      });
    } catch (e) {
      print('[chat] error: \$e');
      _showError('选取图片失败: $e');
      if (mounted) setState(() => _isProcessingImage = false);
    }
  }

  Future<void> _pickImageFromCamera() async {
    try {
      final ok =
          await PermissionManager().request(context, AppPermission.camera);
      if (!ok) return;
      final picker = ImagePicker();
      final image = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85);
      if (image == null) return;
      setState(() => _isProcessingImage = true);
      final bytes = await image.readAsBytes();
      final sizeError =
          FileUtils.validateFileSize(bytes.length, AttachmentType.image);
      if (sizeError != null) {
        _showError(sizeError);
        setState(() => _isProcessingImage = false);
        return;
      }
      final formatError = FileUtils.validateImageFormat(bytes);
      if (formatError != null) {
        _showError(formatError);
        setState(() => _isProcessingImage = false);
        return;
      }
      final base64 = base64Encode(bytes);
      if (!mounted) return;
      setState(() {
        _isProcessingImage = false;
        _attachments.add(_AttachmentItem(
          type: AttachmentType.image,
          base64: base64,
          fileName: 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
          mimeType: 'image/jpeg',
          fileSize: bytes.length));
        _attachmentsExpanded = true;
      });
    } catch (e) {
      print('[chat] error: \$e');
      _showError('拍照失败: $e');
      if (mounted) setState(() => _isProcessingImage = false);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false);
    if (result == null || result.files.isEmpty) return;

    final pickedFile = result.files.first;
    final filePath = pickedFile.path;
    if (filePath == null) return;

    final fileName = pickedFile.name;
    final fileSize = pickedFile.size;
    final mimeType = FileUtils.detectMimeType(fileName);
    final attachmentType = FileUtils.classifyFile(mimeType);

    // Validate size
    final sizeError = FileUtils.validateFileSize(fileSize, attachmentType,
        mimeType: mimeType);
    if (sizeError != null) {
      _showError(sizeError);
      return;
    }

    if (attachmentType == AttachmentType.image) {
      try {
        setState(() => _isProcessingImage = true);
        final bytes = pickedFile.bytes ?? await File(filePath).readAsBytes();
        final sizeError =
            FileUtils.validateFileSize(bytes.length, AttachmentType.image);
        if (sizeError != null) {
          _showError(sizeError);
          setState(() => _isProcessingImage = false);
          return;
        }
        final formatError = FileUtils.validateImageFormat(bytes);
        if (formatError != null) {
          _showError(formatError);
          setState(() => _isProcessingImage = false);
          return;
        }
        final base64 = base64Encode(bytes);
        if (!mounted) return;
        setState(() {
          _isProcessingImage = false;
          _attachments.add(_AttachmentItem(
            type: AttachmentType.image,
            base64: base64,
            fileName: fileName,
            mimeType: mimeType,
            fileSize: fileSize));
          _attachmentsExpanded = true;
        });
      } catch (e) {
        print('[chat] error: \$e');
        _showError('无法读取图片: $e');
        if (mounted) setState(() => _isProcessingImage = false);
      }
    } else {
      try {
        final extractedText = await FileUtils.extractText(filePath, mimeType);
        if (extractedText.trim().isEmpty) {
          _showError('文件中未找到可读文本（可能是扫描图片型 PDF 或加密文件）');
          return;
        }
        setState(() {
          _attachments.add(_AttachmentItem(
            type: AttachmentType.document,
            base64: null,
            fileName: fileName,
            mimeType: mimeType,
            fileSize: fileSize,
            extractedText: extractedText));
          _attachmentsExpanded = true;
        });
      } catch (e) {
        print('[chat] error: \$e');
        _showError('无法解析文件: $e');
      }
    }
  }

  void _showSnackBar(
    String message, {
    Color? backgroundColor,
    Color? textColor,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
    bool isError = false,
  }) {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        message,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: textColor ??
              (isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText))),
      backgroundColor: backgroundColor ??
          (isDark ? PixelTheme.darkSurface : PixelTheme.surface),
      behavior: SnackBarBehavior.floating,
      duration: duration,
      action: action,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12)));
  }

  void _showError(String message) {
    _showSnackBar(message,
        backgroundColor: PixelTheme.error,
        textColor: Colors.white,
        isError: true);
  }

  void _showTokenPlanErrorBanner(String message) {
    if (!mounted) return;
    setState(() {
      _tokenPlanErrorMessage = message;
    });
  }

  void _dismissTokenPlanBanner() {
    setState(() {
      _tokenPlanErrorMessage = null;
    });
  }

  /// Handle browser lifecycle actions (activate / close).
  /// Returns null if the caller should proceed to normal tool execution.
  /// Returns a ToolResult if the lifecycle was resolved here.
  Future<ToolResult?> _handleBrowserLifecycle(
      String toolName, Map<String, dynamic> args) async {
    if (!toolName.startsWith('browser_')) return null;

    final handler = ref.read(browserToolHandlerProvider);

    // ── Browser not initialized ──
    if (handler == null) {
      if (toolName == 'browser_open_tab' || toolName == 'browser_load_html') {
        ref.read(browserEngineActiveProvider.notifier).state = true;
        ref.read(browserPanelVisibleProvider.notifier).state = true;
        for (int i = 0; i < 30; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (!mounted || ref.read(browserToolHandlerProvider) != null) break;
        }
        return null; // proceed to executor
      }
      if (toolName == 'browser_close_tab') {
        return const ToolResult(
          toolName: 'browser_close_tab',
          success: true,
          output: 'Browser is already closed.');
      }
      return ToolResult(
        toolName: toolName,
        success: false,
        output: '',
        error: 'Browser not initialized. Use browser_open_tab first.');
    }

    // ── Browser active: close on last tab hides the panel ──
    if (toolName == 'browser_close_tab') {
      final tabs = ref.read(browserTabsProvider);
      bool isLastTab = false;
      final tabId = args['tabId'] as String?;
      if (tabId != null) {
        final idx = tabs.indexWhere((t) => t.id == tabId);
        isLastTab = idx >= 0 && tabs.length <= 1;
      } else {
        isLastTab = tabs.length <= 1 && tabs.isNotEmpty;
      }
      if (isLastTab) {
        ref.read(browserPanelVisibleProvider.notifier).state = false;
        return const ToolResult(
          toolName: 'browser_close_tab',
          success: true,
          output: 'Browser panel hidden (only tab remained).');
      }
    }

    return null; // proceed to executor
  }

  Future<ToolResult> _executeToolCallNative(
      String toolName, Map<String, dynamic> args) async {
    // 技能反馈追踪：记录工具调用
    _trackSkillToolUsage(toolName);

    // 浏览器生命周期
    final lifecycleResult = await _handleBrowserLifecycle(toolName, args);
    if (lifecycleResult != null) return lifecycleResult;

    // Build executor with full integrations
    final db = ref.read(databaseHelperProvider);
    final executor = ToolExecutor(
      settingsRepo: SettingsRepository(),
      hookPipeline: _hookPipeline,
      toolLogger: ToolCallLogger(db),
      db: db);
    // Inject browser tool handler and backend
    executor.setBrowserToolHandler(ref.read(browserToolHandlerProvider));
    executor.setBrowserBackend(ref.read(browserBackendProvider));
    try {
      _sessionStateMachine.onToolExecutionStart();
      final result = await executor.execute(
        toolName,
        args,
        conversationId: _currentConversationId);
      _sessionStateMachine.onToolExecutionComplete(result.success);
      return result;
    } catch (e) {
      print('[chat] error: \$e');
      return ToolResult(
          toolName: toolName, success: false, output: '', error: e.toString());
    }
  }

  /// Session-aware variant of _executeToolCallNative — uses the captured session
  /// directly so background agent execution doesn't corrupt the active session.
  Future<ToolResult> _executeToolCallNativeForSession(
      ConversationSession session,
      String toolName,
      Map<String, dynamic> args) async {
    // Track skill tool usage against the session's state
    _trackSkillToolUsageForSession(session, toolName);

    // 浏览器生命周期
    final lifecycleResult = await _handleBrowserLifecycle(toolName, args);
    if (lifecycleResult != null) return lifecycleResult;

    final db = ref.read(databaseHelperProvider);
    final executor = ToolExecutor(
      settingsRepo: SettingsRepository(),
      hookPipeline: _hookPipeline,
      toolLogger: ToolCallLogger(db),
      db: db);
    executor.setBrowserToolHandler(ref.read(browserToolHandlerProvider));
    executor.setBrowserBackend(ref.read(browserBackendProvider));
    try {
      session.sessionStateMachine.onToolExecutionStart();

      // ── 编排器工具：智能体自主调用复杂任务编排 ──
      if (toolName == 'task_orchestrate') {
        final userRequest = args['userRequest'] as String? ?? '';
        final projectContext = args['projectContext'] as String?;
        final conversationContext = args['conversationContext'] as String?;

        if (userRequest.isEmpty) {
          return ToolResult(
            toolName: toolName,
            success: false,
            output: '',
            error: 'userRequest 参数不能为空');
        }

        final orchestrator = OrchestratorEngine(
          client: ref.read(minimaxClientProvider));
        // 创建临时消息 ID，用于实时显示编排进度
        final progressMsgId = 'orch_progress_${DateTime.now().millisecondsSinceEpoch}';

        String? finalResult;
        String? finalError;

        try {
          // 插入初始进度消息到消息列表
          if (mounted) {
            session.messages.add(ChatMessage(
              id: progressMsgId,
              conversationId: _currentConversationId!,
              role: MessageRole.assistant,
              content: '分析需求…',
              createdAt: DateTime.now()));
            setState(() {});
            _scrollToBottom();
          }

          await for (final state in orchestrator.orchestrate(
            userRequest: userRequest,
            requestId: _currentConversationId!,
            executeTool: (name, args) async {
              final tr =
                  await _executeToolCallNativeForSession(session, name, args);
              return {
                'success': tr.success,
                'output': tr.output,
                'error': tr.error,
              };
            },
            projectContext: projectContext,
            conversationContext: conversationContext)) {
            // 实时更新进度文本（用消息气泡样式显示）
            if (mounted) {
              final total = state.graph?.nodes.length ?? 0;
              String currentLabel = '';
              if (state.currentTaskId != null && state.graph != null) {
                final node = state.graph!.nodes
                    .where((n) => n.id == state.currentTaskId)
                    .firstOrNull;
                currentLabel = node?.label ?? '';
              }

              final progressText = _formatOrchProgress(
                phase: state.phase,
                currentLabel: currentLabel,
                completedCount: state.completedTasks.length,
                totalCount: total);

              final idx = session.messages.indexWhere((m) => m.id == progressMsgId);
              if (idx >= 0) {
                session.messages[idx] = session.messages[idx].copyWith(content: progressText);
                if (_activeSession == session) {
                  setState(() {});
                  _scrollToBottom();
                }
              }
            }

            if (state.phase == OrchestratorPhase.completed) {
              finalResult = state.partialResult;
            } else if (state.phase == OrchestratorPhase.failed) {
              finalError = state.errorMessage ?? '编排失败';
            }
          }
        } catch (e) {
          print('[chat] error: \$e');
          finalError = e.toString();
        } finally {
          // 编排结束，移除临时进度消息
          if (mounted) {
            session.messages.removeWhere((m) => m.id == progressMsgId);
            if (_activeSession == session) {
              setState(() {});
            }
          }
        }

        if (finalError != null) {
          return ToolResult(
            toolName: toolName,
            success: false,
            output: '',
            error: finalError);
        }

        return ToolResult(
          toolName: toolName,
          success: true,
          output: finalResult ?? '');
      }

      final result = await executor.execute(
        toolName,
        args,
        conversationId: _currentConversationId,
        pauseToken: session.pauseToken);
      if (result.interactive != null && mounted) {
        _interactivePrompt = result.interactive;
      }
      session.sessionStateMachine.onToolExecutionComplete(result.success);
      return result;
    } catch (e) {
      print('[chat] error: \$e');
      return ToolResult(
          toolName: toolName, success: false, output: '', error: e.toString());
    }
  }

  // ─── Backtrack section removed ───────────────────────────────


  Set<int> _selectedIndices = {};

  void _onInteractiveToggle(int index) {
    final prompt = _interactivePrompt;
    if (prompt == null) return;

    setState(() {
      if (prompt.multiSelect) {
        if (_selectedIndices.contains(index)) {
          _selectedIndices.remove(index);
        } else {
          _selectedIndices.add(index);
        }
      } else {
        _selectedIndices = {index};
      }
    });
  }

  void _onInteractiveConfirm() {
    final prompt = _interactivePrompt;
    if (prompt == null || _selectedIndices.isEmpty) return;

    final selection = _selectedIndices
        .map((i) => prompt.options[i])
        .join(', ');
    _interactivePrompt = null;
    _selectedIndices = {};
    if (mounted) setState(() {});
    _messageController.text = selection;
    _sendMessage();
  }

  void _onInteractiveDismiss() {
    _interactivePrompt = null;
    _selectedIndices = {};
    if (mounted) setState(() {});
  }

  Widget _buildInteractiveCard() {
    final prompt = _interactivePrompt!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? PixelTheme.darkSurface : PixelTheme.surface;
    final textColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final secondaryColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary;
    final hasSelection = _selectedIndices.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: PixelTheme.primary.withValues(alpha: 0.35),
          width: 1.5),
        boxShadow: [
          BoxShadow(
            color: PixelTheme.primary.withValues(alpha: isDark ? 0.12 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2)),
        ]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                prompt.multiSelect ? Icons.checklist : Icons.help_outline,
                size: 18,
                color: PixelTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  prompt.question,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: textColor))),
              if (prompt.multiSelect)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '多选',
                    style: TextStyle(
                      fontSize: 11,
                      color: PixelTheme.primary.withValues(alpha: 0.7),
                      fontFamily: 'monospace'))),
              GestureDetector(
                onTap: _onInteractiveDismiss,
                child: Icon(Icons.close, size: 16, color: secondaryColor)),
            ]),
          const SizedBox(height: 12),
          ...List.generate(prompt.options.length, (i) {
            final opt = prompt.options[i];
            final selected = _selectedIndices.contains(i);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _onInteractiveToggle(i),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: selected ? PixelTheme.primary : textColor,
                    backgroundColor: selected
                        ? PixelTheme.primary.withValues(alpha: isDark ? 0.15 : 0.06)
                        : Colors.transparent,
                    side: BorderSide(
                      color: selected
                          ? PixelTheme.primary
                          : (isDark ? PixelTheme.darkBorderDefault : PixelTheme.border),
                      width: selected ? 1.5 : 1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14)),
                  child: Row(
                    children: [
                      Icon(
                        prompt.multiSelect
                            ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
                            : (selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                        size: 18,
                        color: selected ? PixelTheme.primary : secondaryColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          opt,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal),
                          textAlign: TextAlign.left)),
                    ]))));
          }),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _onInteractiveDismiss,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: secondaryColor,
                    side: BorderSide(color: isDark ? PixelTheme.darkBorderDefault : PixelTheme.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('取消', style: TextStyle(fontFamily: 'monospace')))),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: hasSelection ? _onInteractiveConfirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PixelTheme.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: PixelTheme.primary.withValues(alpha: 0.35),
                    disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0),
                  child: Text(
                    hasSelection ? '确认${prompt.multiSelect ? " (${_selectedIndices.length})" : ""}' : '请选择',
                    style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)))),
            ]),
        ]));
  }

  // ─── Message Actions (long-press) ──────────────────────────

  Future<void> _backtrackTo(ChatMessage msg) async {
    if (_currentConversationId == null || _isGenerating) return;

    // 第一击：选中状态
    if (_backtrackTargetId != msg.id) {
      _backtrackTargetId = msg.id;
      if (mounted) setState(() {});
      return;
    }

    // 第二击：执行回溯
    final repo = ref.read(chatRepositoryProvider);
    await repo.backtrackTo(_currentConversationId!, msg.id);

    // 回填消息文本到输入框
    _messageController.text = msg.content;

    // 强制清除生成状态
    _session.isGenerating = false;
    _session.generationActive = false;
    _session.cancelToken = null;
    ref.read(agentSessionProvider.notifier).state[_currentConversationId!] = false;
    _isGenerating = false;
    _isLoading = false;

    // 直接就地移除消息，不依赖 _loadMessages() 的复杂状态检查
    final targetIdx = _session.messages.indexWhere((m) => m.id == msg.id);
    if (targetIdx >= 0) {
      _session.messages.removeRange(targetIdx, _session.messages.length);
    }

    _backtrackTargetId = null;
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _onMessageLongPress(ChatMessage msg, bool isLastUserMessage) {
    HapticFeedback.mediumImpact();
    MessageActionSheet.show(
      context: context,
      message: msg,
      isLastUserMessage: isLastUserMessage,
      onAction: (action) => _handleMessageAction(action, msg));
  }

  Future<void> _handleMessageAction(
      MessageAction action, ChatMessage msg) async {
    if (_currentConversationId == null) return;
    // 流式响应期间阻止会触发 _loadMessages 的操作（防止内存消息列表被不完整的 DB 状态覆盖）
    if (_isGenerating && action != MessageAction.copy) {
      _showSnackBar('正在生成回复，请稍后再试', duration: const Duration(seconds: 2));
      return;
    }
    switch (action) {
      case MessageAction.edit:
        break;
      case MessageAction.retry:
        break;
      case MessageAction.delete:
        break;
      case MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: msg.content));
        break;
      case MessageAction.branch:
        break;
      case MessageAction.backtrack:
        await _backtrackTo(msg);
        break;
    }
  }



  /// 滚动摘要：保留最近 N 条完整消息，旧消息生成摘要后删除
  Future<void> _rollingSummarize() async {
    const keepRecent = 10;
    final repo = ref.read(chatRepositoryProvider);

    // 按时间排序
    final sorted = List<ChatMessage>.from(_messages)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    if (sorted.length <= keepRecent) return;

    final oldMessages = sorted.sublist(0, sorted.length - keepRecent);
    final recentMessages = sorted.sublist(sorted.length - keepRecent);

    // 对旧消息生成摘要
    final toSummarize =
        oldMessages.where((m) => m.role != MessageRole.tool).toList();
    if (toSummarize.isNotEmpty) {
      await _generateAndSaveSummary(toSummarize);
    }

    // 保留最近消息（旧消息已在 DB 永久保留，以摘要形式参与上下文）
    _messages = recentMessages;

    // 重新计算上下文 token
    _contextManager.loadFromMessages(_messages);

    // 持久化
    await _saveContextToDb();

    final afterStatus = _contextManager.getStatus();
    _addLog('INFO',
        '滚动压缩完成: 保留 ${recentMessages.length} 条, ${afterStatus.description}');
  }

  Future<void> _generateAndSaveSummary(
      List<ChatMessage> messagesToSummarize) async {
    if (messagesToSummarize.isEmpty) return;

    final repo = ref.read(chatRepositoryProvider);
    final client = ref.read(minimaxClientProvider);

    // 构建摘要内容
    final content = StringBuffer();
    for (final msg in messagesToSummarize) {
      content.writeln('【${msg.role.name}】: ${msg.content}');
      if (msg.thinking != null) {
        content.writeln('[思考]: ${msg.thinking}');
      }
    }

    // 用 Instructor 强制结构化输出摘要
    try {
      final instructor = Instructor.fromClient(client);
      final summarySchema = SchemaDefinition(
        name: 'generate_summary',
        description: 'Generate a concise conversation summary',
        inputSchema: {
          'type': 'object',
          'properties': {
            'summary': {
              'type': 'string',
              'description': 'Concise summary of the conversation'
            },
          },
          'required': ['summary'],
        },
        fromJson: (json) => json['summary'] as String);

      final maybe = await instructor.extract<String>(
        schema: summarySchema,
        messages: [
          Message.system(summarySystemPrompt),
          Message.user('将以下对话压缩为摘要，供后续对话参考。保留：用户意图、已完成操作、重要结论。\n\n'
              '${formatPresetLengthGuidance(_contextManager.recommendedSummaryLength)}\n\n'
              '【对话内容】\n${content.toString()}'),
        ],
        maxRetries: 1);

      final summary = maybe.isSuccess ? maybe.value : null;
      if (summary != null && summary.isNotEmpty) {
        _currentSummary = summary;
        if (_currentConversationId != null) {
          await repo.updateSummary(_currentConversationId!, summary);
        }
        _addLog('INFO', '摘要已保存: ${summary.length} 字符');
      }
    } catch (e) {
      print('[chat] error: \$e');
      _addLog('ERROR', '生成摘要失败: $e');
    }
  }

  Future<void> _openFolder(String path) async {
    try {
      await OpenFilex.open(path);
    } catch (e) {
      print('[chat] error: \$e');
      if (mounted) {
        _showError('无法打开文件夹: $e');
      }
    }
  }

  String _filterThinking(String text) {
    // 移除<think>...</think> 块
    return text.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
  }

  /// 清理遗留系统标记，避免暴露给用户
  /// [SEARCH]/[ASK] 已改为原生 tool_use，此方法仅清理向后兼容的残留标记
  String _cleanSystemTags(String text) {
    var cleaned = text;
    cleaned = cleaned.replaceAll(RegExp(r'\[MEM:\w+:[^\]]+\]'), '');
    cleaned = cleaned.replaceAll(
        RegExp(r'\[OPEN_FOLDER\]\s*.+', caseSensitive: false), '');
    // 向后兼容：清理可能残留的旧格式标记
    cleaned = cleaned.replaceAll(
        RegExp(r'\[SEARCH\]\s*.+', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(
        RegExp(r'\[ASK\][\s\S]*?(?=\[|$)', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(
        RegExp(r'\[TOOL_CALL\][\s\S]*?\[/TOOL_CALL\]', dotAll: true), '');
    cleaned = cleaned.replaceAll(
        RegExp(r'\[TOOL_RESULT\][\s\S]*?\[/TOOL_RESULT\]', dotAll: true), '');
    return cleaned.trim();
  }

  /// 移除 minimax:tool_call XML 块（AI 在工具不可用时可能输出此格式）
  String _stripThinkingFromOptimize(String text) {
    // 移除<think>...</think> 块
    var result = text;
    result = result.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    // 也移除 [TIPS]...[/TIPS] 因为优化结果可能包含它
    result = result.replaceAll(RegExp(r'\[TIPS\][\s\S]*?\[/TIPS\]'), '');
    return result.trim();
  }

  void _applyOptimizedPrompt() {
    if (_optimizeResult != null) {
      _messageController.text = _optimizeResult!.optimized;
      _messageController.selection =
          TextSelection.collapsed(offset: _optimizeResult!.optimized.length);
      setState(() => _optimizeResult = null);
    }
  }

  void _dismissOptimizeBanner() {
    setState(() => _optimizeResult = null);
  }
}

/// 优化提示词结果数据
/// 优化提示词横幅 - 可滑动消除 + 倒计时自动消失
class _OptimizePromptBanner extends StatefulWidget {
  const _OptimizePromptBanner({
    required this.optimized,
    required this.onApply,
    required this.onDismiss,
  });
  final OptimizeData optimized;
  final VoidCallback onApply;
  final VoidCallback onDismiss;

  @override
  State<_OptimizePromptBanner> createState() => _OptimizePromptBannerState();
}

class _OptimizePromptBannerState extends State<_OptimizePromptBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  bool _dismissed = false;

  static const Duration _displayDuration = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this);
    _slideAnimation = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    // 入场动画
    _controller.forward();

    // 启动倒计时
    Future.delayed(_displayDuration, () {
      if (mounted && !_dismissed) {
        _dismiss();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    _controller.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SlideTransition(
          position: _slideAnimation.drive(
            Tween(begin: const Offset(0, -1), end: Offset.zero).chain(
              CurveTween(curve: Curves.easeOut))),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: child));
      },
      child: Dismissible(
        key: const ValueKey('optimize_banner'),
        direction: DismissDirection.up,
        onDismissed: (_) => widget.onDismiss(),
        child: GestureDetector(
          onTap: () => _showDetailSheet(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [
                        PixelTheme.darkPrimary.withValues(alpha: 0.15),
                        PixelTheme.darkSecondary.withValues(alpha: 0.15)
                      ]
                    : [
                        PixelTheme.primary.withValues(alpha: 0.1),
                        PixelTheme.secondary.withValues(alpha: 0.1)
                      ]),
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? PixelTheme.darkBorderSubtle
                      : PixelTheme.pixelBorder,
                  width: 1))),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? PixelTheme.darkElevated
                          : PixelTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: isDark
                              ? PixelTheme.darkPrimary
                              : PixelTheme.primary,
                          width: 1)),
                    child: Icon(Icons.auto_fix_high,
                        size: 16,
                        color: isDark
                            ? PixelTheme.darkPrimary
                            : PixelTheme.primary)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '提示词已优化',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? PixelTheme.darkPrimaryText
                                : PixelTheme.textPrimary)),
                        const SizedBox(height: 2),
                        Text(
                          '点击查看详情 · 10秒后自动消失',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: isDark
                                ? PixelTheme.darkTextMuted
                                : PixelTheme.textMuted)),
                      ])),
                  _buildApplyButton(isDark),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: _dismiss,
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: isDark
                          ? PixelTheme.darkTextMuted
                          : PixelTheme.textMuted)),
                ]))))));
  }

  Widget _buildApplyButton(bool isDark) {
    return GestureDetector(
      onTap: () {
        _dismiss();
        widget.onApply();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: isDark
              ? PixelTheme.darkPrimaryGradient
              : PixelTheme.primaryGradient,
          borderRadius: BorderRadius.circular(16)),
        child: const Text(
          '应用',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white))));
  }

  void _showDetailSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      enableDrag: true,
      backgroundColor: isDark ? PixelTheme.darkSurface : PixelTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scrollController) {
            return Column(
              children: [
                // 拖动条
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? PixelTheme.darkBorderDefault
                        : PixelTheme.pixelBorder,
                    borderRadius: BorderRadius.circular(2))),
                // 标题
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: isDark
                              ? PixelTheme.darkPrimaryGradient
                              : PixelTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.auto_fix_high,
                            size: 20, color: Colors.white)),
                      const SizedBox(width: 12),
                      const Text(
                        '提示词优化结果',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx)),
                    ])),
                const Divider(height: 1),
                // 内容
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      // 优化后的提示词
                      const Text(
                        '优化后',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: PixelTheme.primary)),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? PixelTheme.darkCodeBlockBg
                              : PixelTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark
                                ? PixelTheme.darkBorderSubtle
                                : PixelTheme.pixelBorder)),
                        child: SelectableText(
                          widget.optimized.optimized,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: isDark
                                ? PixelTheme.darkPrimaryText
                                : PixelTheme.textPrimary,
                            height: 1.5))),
                      // 优化建议
                      if (widget.optimized.tips.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          '优化建议',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: PixelTheme.primary)),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? PixelTheme.darkElevated.withValues(alpha: 0.5)
                                : PixelTheme.surfaceVariant
                                    .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            widget.optimized.tips,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: isDark
                                  ? PixelTheme.darkSecondaryText
                                  : PixelTheme.textSecondary,
                              height: 1.6))),
                      ],
                      const SizedBox(height: 24),
                      // 应用按钮
                      SizedBox(
                        width: double.infinity,
                        child: GradientButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _dismiss();
                            widget.onApply();
                          },
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text(
                                '应用此提示词',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
                            ]))),
                    ])),
              ]);
          });
      });
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.isLoading,
    required this.enabled,
    required this.onPressed,
    this.isGenerating = false,
    this.onStop,
  });
  final bool isLoading;
  final bool isGenerating;
  final bool enabled;
  final VoidCallback? onPressed;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradient =
        isDark ? PixelTheme.darkPrimaryGradient : PixelTheme.primaryGradient;

    if (isGenerating) {
      return GestureDetector(
        onTap: onStop,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: PixelTheme.error,
            shape: BoxShape.circle),
          child: const Center(
            child: Icon(Icons.stop_rounded, size: 20, color: Colors.white))));
    }

    final bool canSend = enabled && !isLoading;

    return GestureDetector(
      onTap: canSend ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: canSend ? gradient : null,
          color: canSend
              ? null
              : (isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant),
          shape: BoxShape.circle,
          border: canSend
              ? null
              : Border.all(
                  color: isDark
                      ? PixelTheme.darkBorderDefault
                      : PixelTheme.pixelBorder,
                  width: 1)),
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)))
              : Icon(
                  Icons.send_rounded,
                  size: 20,
                  color: canSend
                      ? Colors.white
                      : (isDark
                          ? PixelTheme.darkTextMuted
                          : PixelTheme.textMuted)))));
  }
}

/// + 号菜单按钮组件
class _PlusMenuButton extends StatefulWidget {
  const _PlusMenuButton({
    this.onCameraPressed,
    this.onImagePressed,
    this.onFilePressed,
  });
  final VoidCallback? onCameraPressed;
  final VoidCallback? onImagePressed;
  final VoidCallback? onFilePressed;

  @override
  State<_PlusMenuButton> createState() => _PlusMenuButtonState();
}

class _PlusMenuButtonState extends State<_PlusMenuButton>
    with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isMenuOpen = false;

  void _toggleMenu() {
    if (_isMenuOpen) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    final overlay = Overlay.of(context);

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // 点击外部关闭菜单
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeMenu,
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent))),
          // 气泡菜单
          Positioned(
            width: 90,
            child: CompositedTransformFollower(
              link: _layerLink,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: const Offset(0, 4),
              child: _buildBubbleMenu())),
        ]));

    overlay.insert(_overlayEntry!);
    setState(() => _isMenuOpen = true);
  }

  void _closeMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    setState(() => _isMenuOpen = false);
  }

  Widget _buildBubbleMenu() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: AnimatedScale(
        scale: _isMenuOpen ? 1.0 : 0.85,
        duration: const Duration(milliseconds: 150),
        child: AnimatedOpacity(
          opacity: _isMenuOpen ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            decoration: BoxDecoration(
              color:
                  isDark ? PixelTheme.darkElevated : PixelTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? PixelTheme.darkBorderDefault
                    : PixelTheme.pixelBorder,
                width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4)),
              ]),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PixelMenuItem(
                  compact: true,
                  icon: Icons.camera_alt_outlined,
                  label: '拍照',
                  onTap: () {
                    _closeMenu();
                    widget.onCameraPressed?.call();
                  }),
                Divider(
                  height: 1,
                  color: isDark
                      ? PixelTheme.darkBorderSubtle
                      : PixelTheme.pixelBorder.withValues(alpha: 0.3)),
                PixelMenuItem(
                  compact: true,
                  icon: Icons.image_outlined,
                  label: '图片',
                  onTap: () {
                    _closeMenu();
                    widget.onImagePressed?.call();
                  }),
                Divider(
                  height: 1,
                  color: isDark
                      ? PixelTheme.darkBorderSubtle
                      : PixelTheme.pixelBorder.withValues(alpha: 0.3)),
                PixelMenuItem(
                  compact: true,
                  icon: Icons.attach_file,
                  label: '附件',
                  onTap: () {
                    _closeMenu();
                    widget.onFilePressed?.call();
                  }),
              ])))));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: _toggleMenu,
        child: AnimatedRotation(
          turns: _isMenuOpen ? 0.125 : 0, // 45度旋转
          duration: const Duration(milliseconds: 200),
          child: Icon(
            Icons.add,
            size: 22,
            color: isDark
                ? PixelTheme.darkSecondaryText
                : PixelTheme.textSecondary))));
  }
}

/// 历史对话抽屉内容组件
class _ConversationDrawerContent extends ConsumerStatefulWidget {
  const _ConversationDrawerContent({
    required this.conversations,
    required this.currentConversationId,
    required this.interruptedConvIds,
    required this.showTaskMode,
    required this.taskConversation,
    required this.onToggleMode,
    required this.onSelectConversation,
    required this.onDeleteConversation,
  });
  final List<ChatConversation> conversations;
  final String? currentConversationId;
  final Set<String> interruptedConvIds;
  final bool showTaskMode;
  final ChatConversation? taskConversation;
  final VoidCallback onToggleMode;
  final Function(ChatConversation) onSelectConversation;
  final Function(ChatConversation) onDeleteConversation;

  @override
  ConsumerState<_ConversationDrawerContent> createState() =>
      _ConversationDrawerContentState();
}

class _ConversationDrawerContentState
    extends ConsumerState<_ConversationDrawerContent> {
  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dateTime.month}/${dateTime.day}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? PixelTheme.darkPrimary : PixelTheme.primary;
    final generatingSessions = ref.watch(agentSessionProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Column(
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? PixelTheme.darkElevated
                          : PixelTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: primaryColor, width: 1)),
                    child: Icon(Icons.chat_bubble_rounded,
                        size: 20, color: primaryColor)),
                  const SizedBox(width: 14),
                  Text(
                    widget.showTaskMode ? '定时任务' : '历史对话',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? PixelTheme.darkPrimaryText
                          : PixelTheme.textPrimary)),
                ])),
            // 对话列表
            Expanded(
              child: widget.conversations.isEmpty
                  ? _buildEmptyState(showTaskMode: widget.showTaskMode)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: true,
                      itemCount: widget.conversations.length,
                      itemBuilder: (ctx, i) {
                        final conv = widget.conversations[i];
                        final isSelected =
                            conv.id == widget.currentConversationId;
                        final isGenerating =
                            generatingSessions[conv.id] == true;
                        final hasInterrupted =
                            widget.interruptedConvIds.contains(conv.id);
                        return _ConversationTile(
                          key: ValueKey(conv.id),
                          conversation: conv,
                          isSelected: isSelected,
                          isGenerating: isGenerating,
                          hasInterrupted: hasInterrupted,
                          isTaskConversation: widget.showTaskMode,
                          formatTime: _formatTime,
                          onTap: () => widget.onSelectConversation(conv),
                          onDelete: () => widget.onDeleteConversation(conv));
                      })),
            // 切换按钮
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: isDark
                            ? PixelTheme.darkBorderSubtle
                            : Colors.grey.withValues(alpha: 0.1)))),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => widget.onToggleMode(),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(children: [
                    AnimatedRotation(
                      turns: widget.showTaskMode ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        Icons.u_turn_right_rounded,
                        size: 20,
                        color: widget.showTaskMode
                            ? PixelTheme.brandBlue
                            : (isDark
                                ? PixelTheme.darkSecondaryText
                                : PixelTheme.textSecondary))),
                    const SizedBox(width: 10),
                    Text(
                      widget.showTaskMode ? '切回普通对话' : '切换到定时任务',
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? PixelTheme.darkSecondaryText
                              : PixelTheme.textSecondary)),
                    const Spacer(),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: widget.showTaskMode
                            ? PixelTheme.brandBlue
                            : (isDark
                                ? PixelTheme.darkTextMuted
                                : PixelTheme.textMuted),
                        shape: BoxShape.circle)),
                  ])))),
          ])));
  }

  Widget _buildEmptyState({bool showTaskMode = false}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            showTaskMode ? '暂无定时任务记录' : '快去和SuperMax聊天吧',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              color: PixelTheme.textSecondary)),
        ]));
  }

  // ignore: unused_element
  void _showDeleteDialog(ChatConversation conv) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PixelTheme.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PixelTheme.radiusLg)),
        title: const Text('删除对话',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: Text(
          '确定删除 "${conv.title}" 吗？\n此操作不可恢复。',
          style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消')),
          GradientButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onDeleteConversation(conv);
            },
            child: const Text('删除', style: TextStyle(color: Colors.white))),
        ]));
  }
}

/// 单个对话项组件
class _ConversationTile extends StatefulWidget {
  const _ConversationTile({
    required this.conversation,
    required this.isSelected,
    required this.formatTime,
    required this.onTap,
    required this.onDelete,
    super.key,
    this.isGenerating = false,
    this.hasInterrupted = false,
    this.isTaskConversation = false,
  });
  final ChatConversation conversation;
  final bool isSelected;
  final bool isGenerating;
  final bool hasInterrupted;
  final bool isTaskConversation;
  final String Function(DateTime) formatTime;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile>
    with SingleTickerProviderStateMixin {
  bool _pendingDelete = false;
  bool _removing = false;
  late final AnimationController _removeController;
  late final Animation<double> _removeAnimation;

  @override
  void initState() {
    super.initState();
    _removeController = AnimationController(
        duration: const Duration(milliseconds: 300), vsync: this);
    _removeAnimation =
        CurvedAnimation(parent: _removeController, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _removeController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_ConversationTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected ||
        widget.conversation.id != oldWidget.conversation.id) {
      if (_pendingDelete) {
        setState(() => _pendingDelete = false);
      }
    }
  }

  void _handleDelete() {
    if (_pendingDelete) {
      // 确认删除：播放滑出动画，完成后真正删除
      setState(() => _removing = true);
      _removeController.forward().then((_) {
        if (mounted) widget.onDelete();
      });
    } else {
      setState(() => _pendingDelete = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_removing) {
      return SizeTransition(
        sizeFactor: Tween<double>(begin: 1, end: 0).animate(_removeAnimation),
        child: FadeTransition(
          opacity: Tween<double>(begin: 1, end: 0).animate(_removeAnimation),
          child: _buildTile(isDark)));
    }

    return Dismissible(
      key: Key(widget.conversation.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        _handleDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: PixelTheme.error.withValues(alpha: 0.15),
        child: const Icon(Icons.delete_outline, color: PixelTheme.error)),
      child: _buildTile(isDark));
  }

  Widget _buildTile(bool isDark) {
    final selectedBg = isDark
        ? PixelTheme.darkPrimary.withValues(alpha: 0.1)
        : PixelTheme.primary.withValues(alpha: 0.1);
    final unselectedBg = isDark
        ? PixelTheme.darkElevated
        : PixelTheme.surfaceVariant.withValues(alpha: 0.3);
    final iconBgColor = widget.isSelected
        ? null
        : (isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant);
    final iconFgColor =
        widget.isSelected ? Colors.white : PixelTheme.textSecondaryFor(isDark);
    final titleColor = widget.isSelected
        ? PixelTheme.primaryFor(isDark)
        : PixelTheme.textPrimaryFor(isDark);
    final subtitleColor =
        _pendingDelete ? PixelTheme.error : PixelTheme.textMutedFor(isDark);
    final deleteIconColor =
        _pendingDelete ? PixelTheme.error : PixelTheme.textMutedFor(isDark);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      onTap: () {
        if (_pendingDelete) {
          setState(() => _pendingDelete = false);
        }
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: widget.isSelected ? selectedBg : unselectedBg,
          borderRadius: BorderRadius.circular(12),
          border: _pendingDelete
              ? Border.all(color: PixelTheme.error, width: 1.5)
              : (widget.isSelected
                  ? Border.all(
                      color:
                          PixelTheme.primaryFor(isDark).withValues(alpha: 0.3),
                      width: 1)
                  : null)),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: widget.isSelected
                    ? (isDark
                        ? PixelTheme.darkPrimaryGradient
                        : PixelTheme.primaryGradient)
                    : null,
                color: iconBgColor,
                borderRadius: BorderRadius.circular(10)),
              child: widget.hasInterrupted
                  ? const Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: PixelTheme.warning)
                  : Icon(
                      widget.isTaskConversation
                          ? Icons.schedule
                          : Icons.chat_bubble_rounded,
                      size: 20,
                      color: iconFgColor)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: _pendingDelete
                        ? const Text(
                            '再次点击删除',
                            key: ValueKey('delete_confirm'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: PixelTheme.error),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)
                        : Text(
                            widget.conversation.title,
                            key: const ValueKey('title'),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: widget.isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: titleColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                  const SizedBox(height: 4),
                  Text(
                    _pendingDelete
                        ? '确定要删除此对话吗？'
                        : widget.hasInterrupted
                            ? '生成中断 · ${widget.formatTime(widget.conversation.updatedAt)}'
                            : widget.formatTime(widget.conversation.updatedAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.hasInterrupted && !_pendingDelete
                          ? PixelTheme.warning
                          : subtitleColor)),
                ])),
            if (widget.isGenerating)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: PixelTheme.success))
            else
              IconButton(
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    _pendingDelete
                        ? Icons.warning_amber_rounded
                        : Icons.delete_outline,
                    key: ValueKey(_pendingDelete),
                    size: 20,
                    color: deleteIconColor)),
                onPressed: _handleDelete),
          ])));
  }
}

/// 截断检测器
// ignore: unused_element
class _TruncationDetector {
  // ignore: unused_element
  static bool isTruncated(String content) {
    if (content.isEmpty) return false;

    if (_endsWithMidSentencePunctuation(content)) return true;
    if (_hasUnclosedBrackets(content)) return true;
    if (_hasUnclosedQuotes(content)) return true;
    if (_hasUnclosedCodeBlock(content)) return true;
    if (_isIncompleteMarkdown(content)) return true;

    return false;
  }

  static bool _endsWithMidSentencePunctuation(String content) {
    final midSentencePatterns = [
      RegExp(r'[,，;；:：]$'),
      RegExp(r'[,，]\s*$'),
      RegExp(r'\.\.\.$'),
      RegExp(r'[,，]\s*\n$'),
    ];
    return midSentencePatterns.any((p) => p.hasMatch(content));
  }

  static bool _hasUnclosedBrackets(String content) {
    final brackets = {'(': ')', '[': ']', '{': '}', '<': '>'};
    final stack = <String>[];
    bool inCodeBlock = false;

    for (int i = 0; i < content.length; i++) {
      if (i + 2 < content.length && content.substring(i, i + 3) == '```') {
        inCodeBlock = !inCodeBlock;
        i += 2;
        continue;
      }
      if (inCodeBlock) continue;

      final c = content[i];
      if (brackets.containsKey(c)) {
        stack.add(c);
      } else if (brackets.containsValue(c)) {
        if (stack.isEmpty) return true;
        final last = stack.removeLast();
        if (brackets[last] != c) return true;
      }
    }
    return stack.isNotEmpty;
  }

  static bool _hasUnclosedQuotes(String content) {
    int singleQuotes = 0;
    int doubleQuotes = 0;
    bool inCode = false;

    for (int i = 0; i < content.length; i++) {
      final c = content[i];
      if (c == '`' && (i == 0 || content[i - 1] != '\\')) {
        inCode = !inCode;
        continue;
      }
      if (inCode) continue;

      if (c == "'" && (i == 0 || content[i - 1] != '\\')) singleQuotes++;
      if (c == '"' && (i == 0 || content[i - 1] != '\\')) doubleQuotes++;
    }
    return singleQuotes % 2 != 0 || doubleQuotes % 2 != 0;
  }

  static bool _hasUnclosedCodeBlock(String content) {
    final codeBlockCount = '```'.allMatches(content).length;
    return codeBlockCount % 2 != 0;
  }

  static bool _isIncompleteMarkdown(String content) {
    if (content.contains('|') && !content.contains('\n|')) return true;
    final tableRows =
        content.split('\n').where((l) => l.startsWith('|')).length;
    if (tableRows > 0 && !content.contains('---')) return true;
    return false;
  }
}

/// 日志条目
/// 日志查看对话框
class _LogDialog extends StatefulWidget {
  const _LogDialog({required this.logs, this.onClear});
  final List<LogEntry> logs;
  final VoidCallback? onClear;

  @override
  State<_LogDialog> createState() => _LogDialogState();
}

class _LogDialogState extends State<_LogDialog> {
  final _dialogScrollController = ScrollController();
  String _filterLevel = 'ALL';
  bool _showErrorDetails = false;

  List<LogEntry> get _filteredLogs {
    if (_filterLevel == 'ALL') return widget.logs;
    return widget.logs.where((l) => l.level == _filterLevel).toList();
  }

  String get _fullLogText {
    final buffer = StringBuffer();
    for (final log in _filteredLogs) {
      buffer.writeln(
          '[${log.timestamp.toIso8601String()}] [${log.level}] ${log.message}');
      if (log.error != null) buffer.writeln('  ERROR: ${log.error}');
      if (log.stackTrace != null) buffer.writeln('  STACK:\n${log.stackTrace}');
    }
    return buffer.toString();
  }

  void _copyLogs() async {
    await Clipboard.setData(ClipboardData(text: _fullLogText));
    if (mounted) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('日志已复制到剪贴板',
              style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isDark ? PixelTheme.darkSurface : PixelTheme.surface));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: isDark ? PixelTheme.darkSurface : PixelTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
            color:
                isDark ? PixelTheme.darkBorderDefault : PixelTheme.pixelBorder,
            width: 2)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏（仅操作按钮）
            Row(
              children: [
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.copy,
                      size: 18,
                      color: isDark
                          ? PixelTheme.darkSecondaryText
                          : PixelTheme.textSecondary),
                  tooltip: '复制日志',
                  onPressed: _copyLogs),
                if (widget.onClear != null)
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 18,
                        color: isDark
                            ? PixelTheme.darkSecondaryText
                            : PixelTheme.textSecondary),
                    tooltip: '清空日志',
                    onPressed: () {
                      widget.onClear?.call();
                      setState(() {});
                    }),
                IconButton(
                  icon: Icon(Icons.close,
                      size: 18,
                      color: isDark
                          ? PixelTheme.darkSecondaryText
                          : PixelTheme.textSecondary),
                  onPressed: () => Navigator.pop(context)),
              ]),
            const SizedBox(height: 12),
            // 过滤器
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('级别:',
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: isDark
                              ? PixelTheme.darkSecondaryText
                              : PixelTheme.textSecondary))),
                _buildFilterChip('ALL', isDark),
                _buildFilterChip('INFO', isDark),
                _buildFilterChip('DEBUG', isDark),
                _buildFilterChip('ERROR', isDark),
              ]),
            const SizedBox(height: 8),
            // 日志列表
            Container(
              height: 350,
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: isDark
                        ? PixelTheme.darkBorderDefault
                        : PixelTheme.pixelBorder)),
              child: _filteredLogs.isEmpty
                  ? Center(
                      child: Text('暂无日志',
                          style: TextStyle(
                              fontFamily: 'monospace',
                              color: isDark
                                  ? PixelTheme.darkTextMuted
                                  : Colors.grey)))
                  : ListView.builder(
                      cacheExtent: 100,
                      controller: _dialogScrollController,
                      padding: const EdgeInsets.all(8),
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: true,
                      itemCount: _filteredLogs.length,
                      itemBuilder: (ctx, i) {
                        final log = _filteredLogs[i];
                        return _LogItem(
                          key: ValueKey('${log.timestamp}_${log.level}_$i'),
                          log: log,
                          showErrorDetails:
                              _showErrorDetails && log.level == 'ERROR',
                          onToggleDetails: () {
                            setState(() {
                              _showErrorDetails = !_showErrorDetails;
                            });
                          },
                          onCopy: (text) {
                            Clipboard.setData(ClipboardData(text: text));
                            final isDark =
                                Theme.of(context).brightness == Brightness.dark;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('已复制',
                                    style: TextStyle(
                                        fontFamily: 'monospace', fontSize: 11)),
                                duration: const Duration(seconds: 1),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: isDark
                                    ? PixelTheme.darkSurface
                                    : PixelTheme.surface));
                          });
                      })),
          ])));
  }

  Widget _buildFilterChip(String level, bool isDark) {
    final isSelected = _filterLevel == level;
    Color chipColor;
    switch (level) {
      case 'ERROR':
        chipColor = PixelTheme.error;
        break;
      case 'DEBUG':
        chipColor = Colors.orange;
        break;
      default:
        chipColor = isDark ? PixelTheme.darkPrimary : PixelTheme.primary;
    }
    return GestureDetector(
      onTap: () => setState(() => _filterLevel = level),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? chipColor.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: isSelected
                  ? chipColor
                  : (isDark ? PixelTheme.darkBorderDefault : Colors.grey))),
        child: Text(
          level,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: isSelected
                ? chipColor
                : (isDark ? PixelTheme.darkTextMuted : Colors.grey)))));
  }
}

/// 日志项组件
class _LogItem extends StatelessWidget {
  const _LogItem({
    required this.log,
    required this.showErrorDetails,
    required this.onToggleDetails,
    required this.onCopy,
    super.key,
  });
  final LogEntry log;
  final bool showErrorDetails;
  final VoidCallback onToggleDetails;
  final void Function(String) onCopy;

  Color get _levelColor {
    switch (log.level) {
      case 'ERROR':
        return Colors.red;
      case 'WARN':
        return Colors.orange;
      case 'DEBUG':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }

  String get _timeStr {
    return '${log.timestamp.hour.toString().padLeft(2, '0')}:'
        '${log.timestamp.minute.toString().padLeft(2, '0')}:'
        '${log.timestamp.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logTextColor = isDark ? Colors.white70 : Colors.black87;
    final logTimeColor = isDark ? Colors.grey : Colors.grey.shade600;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () {
              final text = log.error != null
                  ? '${log.message}\nERROR: ${log.error}\n${log.stackTrace ?? ''}'
                  : log.message;
              onCopy(text);
            },
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              onTap: log.error != null ? onToggleDetails : null,
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: logTextColor),
                  children: [
                    TextSpan(
                      text: '[$_timeStr] ',
                      style: TextStyle(color: logTimeColor)),
                    TextSpan(
                      text: '[${log.level}] ',
                      style: TextStyle(
                          color: _levelColor, fontWeight: FontWeight.bold)),
                    TextSpan(text: log.message),
                    if (log.error != null)
                      TextSpan(
                        text: ' ▶',
                        style: TextStyle(
                            color: _levelColor, fontWeight: FontWeight.bold)),
                  ])))),
          if (showErrorDetails && log.error != null)
            Container(
              margin: const EdgeInsets.only(left: 16),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(2)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ERROR: ${log.error}',
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color:
                            isDark ? Colors.red.shade300 : Colors.red.shade700)),
                  if (log.stackTrace != null)
                    Text(
                      log.stackTrace!,
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          color: isDark
                              ? Colors.red.shade300
                              : Colors.red.shade700)),
                ])),
        ]));
  }
}

/// API Key 未配置横幅 - 气泡样式，支持滑动消失
class _ApiKeyBanner extends StatefulWidget {
  const _ApiKeyBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_ApiKeyBanner> createState() => _ApiKeyBannerState();
}

class _ApiKeyBannerState extends State<_ApiKeyBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  bool _dismissed = false;

  static const Duration _displayDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this);
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
            .animate(curved);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curved);

    _controller.forward();

    Future.delayed(_displayDuration, () {
      if (mounted && !_dismissed) {
        _dismiss();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    _controller.reverse().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: child));
      },
      child: Dismissible(
        key: const ValueKey('api_key_banner'),
        direction: DismissDirection.up,
        onDismissed: (_) => _dismiss(),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [
                        PixelTheme.warning.withValues(alpha: 0.2),
                        PixelTheme.warning.withValues(alpha: 0.1)
                      ]
                    : [
                        PixelTheme.warning.withValues(alpha: 0.15),
                        PixelTheme.warning.withValues(alpha: 0.08)
                      ]),
              border: Border(
                bottom: BorderSide(
                  color: PixelTheme.warning.withValues(alpha: 0.3),
                  width: 1))),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: PixelTheme.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: PixelTheme.warning.withValues(alpha: 0.4),
                          width: 1)),
                    child: const Icon(Icons.key_rounded,
                        size: 16, color: PixelTheme.warning)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '请配置 API Key',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? PixelTheme.darkPrimaryText
                                : PixelTheme.textPrimary)),
                        const SizedBox(height: 2),
                        Text(
                          '点击前往设置 · 5秒后自动消失',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: isDark
                                ? PixelTheme.darkTextMuted
                                : PixelTheme.textMuted)),
                      ])),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: PixelTheme.warning,
                      borderRadius: BorderRadius.circular(14)),
                    child: const Text(
                      '设置',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white))),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: _dismiss,
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: isDark
                          ? PixelTheme.darkTextMuted
                          : PixelTheme.textMuted)),
                ]))))));
  }
}

/// Token Plan 错误提示（简化版）
class _TokenPlanBanner extends StatelessWidget {
  const _TokenPlanBanner({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D1B1B) : const Color(0xFFFEF2F2),
        border: Border(
          bottom: BorderSide(
              color: PixelTheme.error.withValues(alpha: 0.3), width: 1))),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 16, color: PixelTheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: isDark
                        ? PixelTheme.darkPrimaryText
                        : PixelTheme.textPrimary))),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(Icons.close,
                  size: 18,
                  color:
                      isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
          ])));
  }
}

class _MicButton extends StatefulWidget {
  const _MicButton({required this.isEnabled, required this.onResult});
  final bool isEnabled;
  final void Function(String text) onResult;

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  final VoskService _vosk = VoskService();
  bool _isRecording = false;
  String _partialText = '';
  Timer? _silenceTimer;
  OverlayEntry? _overlayEntry;
  StreamSubscription<String>? _partialSub;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _vosk.ensureInitialized();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800));
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _partialSub?.cancel();
    _removeOverlay();
    _pulseController.dispose();
    _vosk.dispose();
    super.dispose();
  }

  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(seconds: 3), () {
      if (_isRecording) _stopRecording();
    });
  }

  void _startRecording() async {
    if (!widget.isEnabled || _isRecording) return;
    final perm =
        await PermissionManager().request(context, AppPermission.microphone);
    if (!perm) return;

    setState(() => _isRecording = true);
    _pulseController.repeat(reverse: true);
    _showOverlay();

    _partialSub = _vosk.partialResults.listen((text) {
      if (_partialText != text) {
        _partialText = text;
        if (mounted) _overlayEntry?.markNeedsBuild();
      }
      if (mounted) _resetSilenceTimer();
    });

    _vosk.startListening().catchError((_) {
      _partialSub?.cancel();
      _partialSub = null;
      if (mounted) {
        setState(() => _isRecording = false);
        _removeOverlay();
        _pulseController.stop();
        _pulseController.reset();
      }
    });

    _resetSilenceTimer();
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    _silenceTimer?.cancel();
    _partialSub?.cancel();
    _partialSub = null;
    _pulseController.stop();
    _pulseController.reset();

    setState(() => _isRecording = false);
    _removeOverlay();

    final text = await _vosk.stopListening();
    final finalText = text.isNotEmpty ? text : _partialText;
    if (finalText.isNotEmpty && mounted) {
      widget.onResult(finalText);
    }
    if (mounted) setState(() => _partialText = '');
  }

  void _showOverlay() {
    _removeOverlay();
    _overlayEntry = OverlayEntry(
      builder: (ctx) => _MicRecordingOverlay(
        partialText: _partialText,
        pulseAnimation: _pulseAnimation,
        onStop: _stopRecording));
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEnabled = widget.isEnabled;
    final color = isEnabled
        ? (isDark ? PixelTheme.darkAccent : PixelTheme.primary)
        : PixelTheme.textMuted;
    final icon = _isRecording ? Icons.stop : Icons.mic_none;

    return GestureDetector(
      onTap: isEnabled
          ? () => _isRecording ? _stopRecording() : _startRecording()
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              _isRecording ? color.withValues(alpha: 0.15) : Colors.transparent,
          border: Border.all(
            color: _isRecording ? Colors.red : color,
            width: 1.5)),
        child: Icon(icon, color: _isRecording ? Colors.red : color, size: 20)));
  }
}

class _MicRecordingOverlay extends StatelessWidget {
  const _MicRecordingOverlay({
    required this.partialText,
    required this.pulseAnimation,
    required this.onStop,
  });
  final String partialText;
  final Animation<double> pulseAnimation;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final bottomOffset = bottomInset > 0 ? bottomInset + 70 : 160.0;
    return Stack(
      children: [
        Positioned(
          left: 56,
          right: 12,
          bottom: bottomOffset,
          child: GestureDetector(
            onTap: onStop,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(20),
              color: bgColor,
              surfaceTintColor: Colors.transparent,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: pulseAnimation,
                      builder: (context, child) => Transform.scale(
                        scale: pulseAnimation.value,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red.withValues(alpha: 0.12)),
                          child: const Icon(Icons.mic,
                              color: Colors.red, size: 16)))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        partialText.isEmpty ? '正在聆听...' : partialText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: partialText.isEmpty
                              ? (isDark ? Colors.white54 : Colors.black54)
                              : textColor,
                          fontStyle: partialText.isEmpty
                              ? FontStyle.italic
                              : FontStyle.normal,
                          height: 1.2))),
                    if (partialText.isEmpty) ...[
                      const SizedBox(width: 8),
                      _WaveDot(isDark: isDark),
                    ],
                  ]))))),
      ]);
  }
}

class _WaveDot extends StatefulWidget {
  const _WaveDot({required this.isDark});
  final bool isDark;

  @override
  State<_WaveDot> createState() => _WaveDotState();
}

class _WaveDotState extends State<_WaveDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isDark ? Colors.white54 : Colors.black45;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_ctrl.value + i * 0.3) % 1.0;
            final h = 3 + 6 * (0.5 - (t - 0.5).abs() * 2);
            return Container(
              width: 2.5,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2)));
          }));
      });
  }
}

class _AttachmentItem {
  _AttachmentItem({
    required this.type,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    this.base64,
    this.extractedText,
  }) {
    if (base64 != null && base64!.isNotEmpty) {
      try {
        _cachedBytes = base64Decode(base64!);
      } catch (_) {
        _cachedBytes = null;
      }
    }
  }
  final AttachmentType type;
  final String? base64;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final String? extractedText;
  Uint8List? _cachedBytes;

  Uint8List? get thumbnailBytes => _cachedBytes;

  String get formattedSize {
    if (fileSize < 1024) return '${fileSize}B';
    if (fileSize < 1024 * 1024)
      return '${(fileSize / 1024).toStringAsFixed(1)}KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}
