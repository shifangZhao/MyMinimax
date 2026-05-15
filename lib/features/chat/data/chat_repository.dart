import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../../../core/api/minimax_client.dart';
import '../../../core/api/json_repair.dart';
import '../../../core/storage/database_helper.dart';
import '../../../core/tools/tool_registry.dart';
import '../../../core/tools/tool_groups.dart';
import '../../../core/engine/tool_execution_handler.dart';
import '../../../core/engine/loop_monitor.dart';
import '../../../core/hooks/hook_pipeline.dart';
import '../../../core/skills/skill.dart';
import '../../../core/logging/agent_tracer.dart';
import '../../../core/engine/conversation_session.dart';
import '../../../shared/document_converter/services/pdf_ocr_bridge.dart';
import '../domain/chat_message.dart';
import '../domain/chat_conversation.dart';
import '../../tools/domain/tool.dart';

class ChatRepository {

  ChatRepository({required MinimaxClient client, required DatabaseHelper db})
      : _client = client,
        _db = db;
  final MinimaxClient _client;
  final DatabaseHelper _db;

  /// 工具定义（从 ToolRegistry 获取，不再重复维护）—— 无状态过滤版
  static List<Map<String, dynamic>> get tools => ToolRegistry.instance.anthropicSchemas;

  /// 启发式复杂度评分（0-10），用于自动建议 task_orchestrate。
  static int _heuristicComplexityScore(String userMessage) {
    int score = 0;

    // 消息长度
    if (userMessage.length > 500) score += 2;
    if (userMessage.length > 1000) score += 1; // 累加至 +3
    if (userMessage.length > 2000) score += 1; // 累加至 +4

    // 中文任务序列词
    final cnSequential = RegExp(r'先[做要]|然后|接着|再[去来]|同时|之后|最后|第[一二三四五]步|步骤[一二三四五]');
    final cnMatches = cnSequential.allMatches(userMessage).length;
    score += (cnMatches > 0 ? 1 : 0) + (cnMatches > 1 ? 1 : 0); // 最多 +2

    // 英文任务序列词
    final enSequential = RegExp(r'\bfirst\b|\bthen\b|\bnext\b|\bafter\b|\bfinally\b|\bstep\s*\d|\balso\b', caseSensitive: false);
    final enMatches = enSequential.allMatches(userMessage).length;
    score += (enMatches > 0 ? 1 : 0) + (enMatches > 1 ? 1 : 0); // 最多 +2

    // 编号列表（如 "1. xxx\n2. xxx" 或 "1) xxx 2) xxx"）
    final numberedItems = RegExp(r'(?:^|\n)\s*\d+[\.\)、]\s').allMatches(userMessage).length;
    score += numberedItems >= 3 ? 2 : (numberedItems > 0 ? 1 : 0);

    return score.clamp(0, 10);
  }

  Future<String> sendMessage({
    required String conversationId,
    required String message,
    String? imageBase64,
    String? fileName,
    String? fileType,
    String? mimeType,
    int? fileSize,
    String? extractedText,
  }) async {
    final history = await getMessages(conversationId);
    final historyForApi = history
        .where((m) => m.role != MessageRole.system)
        .map((m) => {'role': m.role.name, 'content': m.content})
        .toList();

    String response;
    if (imageBase64 != null && fileType != 'document') {
      final displayContent = message.isEmpty ? '[用户发送了一张图片]' : '[用户发送了一张图片]\n$message';

      // 先尝试离线 OCR（免费），有文字则用聊天 API，无文字才降级 Vision API
      String? ocrText;
      try {
        await PdfOcrBridge.ensureLoaded();
        final tempDir = Directory.systemTemp;
        final tempFile = File('${tempDir.path}/ocr_chat_${DateTime.now().millisecondsSinceEpoch}.png');
        await tempFile.writeAsBytes(base64Decode(imageBase64));
        final ocrResult = await PdfOcrBridge().recognizeFile(tempFile.path);
        await tempFile.delete().catchError((_) {});
        if (ocrResult.hasText) ocrText = ocrResult.text;
      } catch (_) {}

      if (ocrText != null && ocrText.trim().isNotEmpty) {
        final truncated = ocrText.length > 4000 ? '${ocrText.substring(0, 4000)}…[OCR文字过长已截断]' : ocrText;
        final ocrPrompt = message.isEmpty
            ? '用户发送了一张图片，离线OCR从图片中识别到以下文字：\n\n---\n$truncated\n---\n\n请根据这些文字内容理解并回答用户意图。如果图片中有视觉信息（图表、设计、布局等）文字无法传达需要进一步了解，请说明。'
            : '用户发送了一张图片，离线OCR从图片中识别到以下文字：\n\n---\n$truncated\n---\n\n用户的问题：$message\n\n请根据这些文字内容回答。如果图片中有视觉信息文字无法传达，请说明。';
        response = await _client.chatCollect(ocrPrompt, history: historyForApi);
      } else {
        response = await _client.vision(imageBase64, message);
      }

      await _db.addMessage(conversationId, 'user', displayContent, imageBase64: imageBase64);
      await _db.addMessage(conversationId, 'assistant', response);
    } else {
      response = await _client.chatCollect(message, history: historyForApi);
      await _db.addMessage(conversationId, 'user', message,
        fileName: fileName, fileType: fileType, mimeType: mimeType,
        fileSize: fileSize, extractedText: extractedText);
      await _db.addMessage(conversationId, 'assistant', response);
    }

    return response;
  }

  Stream<ChatMessage> sendMessageStream({
    required String conversationId,
    required String message,
    String? imageBase64,
    String? fileName,
    String? fileType,
    String? mimeType,
    int? fileSize,
    String? extractedText,
    dynamic systemPrompt,  // String (backward compat) or List<Map> (with cache_control)
    List<Map<String, String>>? history,
    bool skipSaveUserMessage = false,
    CancelToken? cancelToken,
    double temperature = 1.0,
    double topP = 0.95,
    int maxTokens = 16384,
    int thinkingBudgetTokens = 6000,
    Map<String, dynamic>? toolChoice,
  }) async* {
    if (imageBase64 != null && fileType != 'document') {
      // 先尝试离线 OCR
      String? ocrText;
      try {
        await PdfOcrBridge.ensureLoaded();
        final tempDir = Directory.systemTemp;
        final tempFile = File('${tempDir.path}/ocr_chat_${DateTime.now().millisecondsSinceEpoch}.png');
        await tempFile.writeAsBytes(base64Decode(imageBase64));
        final ocrResult = await PdfOcrBridge().recognizeFile(tempFile.path);
        await tempFile.delete().catchError((_) {});
        if (ocrResult.hasText) ocrText = ocrResult.text;
      } catch (_) {}

      String response;
      if (ocrText != null && ocrText.trim().isNotEmpty) {
        final truncated = ocrText.length > 4000 ? '${ocrText.substring(0, 4000)}…[OCR文字过长已截断]' : ocrText;
        final ocrPrompt = message.isEmpty
            ? '用户发送了一张图片，离线OCR从图片中识别到以下文字：\n\n---\n$truncated\n---\n\n请根据这些文字内容理解并回答用户意图。如果图片中有视觉信息（图表、设计、布局等）文字无法传达需要进一步了解，请说明。'
            : '用户发送了一张图片，离线OCR从图片中识别到以下文字：\n\n---\n$truncated\n---\n\n用户的问题：$message\n\n请根据这些文字内容回答。如果图片中有视觉信息文字无法传达，请说明。';
        response = await _client.chatCollect(ocrPrompt);
      } else {
        response = await _client.vision(imageBase64, message);
      }
      final msg = ChatMessage(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
        conversationId: conversationId,
        role: MessageRole.assistant,
        content: response,
        createdAt: DateTime.now(),
      );
      yield msg;
      await _db.addMessage(conversationId, 'user', '[用户发送了一张图片]$message', imageBase64: imageBase64);
      await _db.addMessage(conversationId, 'assistant', response);
      return;
    }

    if (!skipSaveUserMessage) {
      await _db.addMessage(conversationId, 'user', message,
        fileName: fileName, fileType: fileType, mimeType: mimeType,
        fileSize: fileSize, extractedText: extractedText);
    }

    String fullThinking = '';
    String fullContent = '';

    await for (final chunk in _client.chatStream(
      message,
      history: history,
      systemPrompt: systemPrompt,
      tools: tools,
      cancelToken: cancelToken,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      thinkingBudgetTokens: thinkingBudgetTokens,
      toolChoice: toolChoice,
    )) {
      if (chunk.hasThinking && chunk.thinking != null) {
        fullThinking = chunk.thinking!;
      }
      if (chunk.hasContent && chunk.content != null) {
        fullContent = chunk.content!;
      }

      // 如果是工具调用完成
      if (chunk.isToolCallFinished && chunk.toolName != null) {
        final toolMsg = ChatMessage(
          id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
          conversationId: conversationId,
          role: MessageRole.assistant,
          content: fullContent,
          createdAt: DateTime.now(),
          thinking: fullThinking.isNotEmpty ? fullThinking : null,
          toolCall: chunk.toolName,
          toolInput: chunk.toolInput,
        );
        yield toolMsg;
        continue;
      }

      // 只在有实际内容更新时 yield（避免重复）
      if (chunk.hasContent || chunk.hasThinking) {
        yield ChatMessage(
          id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
          conversationId: conversationId,
          role: MessageRole.assistant,
          content: fullContent,
          createdAt: DateTime.now(),
          thinking: fullThinking.isNotEmpty ? fullThinking : null,
        );
      }
    }

    // 不在 sendMessageStream 中自动保存，由调用方（chat_page）负责保存
    // 避免工具调用流程中产生双重保存（auto-save + chat_page 手动保存）
  }

  /// 原生 Anthropic tool_use 流式发送 —— 内部处理完整工具调用循环
  Stream<ChatMessage> sendMessageStreamNative({
    required String conversationId,
    required String message,
    required Future<ToolResult> Function(String toolName, Map<String, dynamic> args) executeTool, String? imageBase64,
    String? fileName,
    String? fileType,
    String? mimeType,
    int? fileSize,
    String? extractedText,
    dynamic systemPrompt,  // String (backward compat) or List<Map> (with cache_control)
    List<Map<String, String>>? history,
    bool skipSaveUserMessage = false,
    CancelToken? cancelToken,
    double temperature = 1.0,
    double topP = 0.95,
    int maxTokens = 16384,
    int thinkingBudgetTokens = 6000,
    Map<String, dynamic>? toolChoice,
    String? messageId,
    PauseToken? pauseToken,
    HookPipeline? hookPipeline,
    Set<String> activeSkills = const {},
    /// 恢复模式：从 checkpoint 直接加载上下文，不依赖 LLM 续写
    bool resumeFromCheckpoint = false,
  }) async* {
    if (pauseToken != null && pauseToken.isPaused) return;

    // 保存用户消息到数据库
    if (!skipSaveUserMessage) {
      await _db.addMessage(conversationId, 'user', message,
        fileName: fileName, fileType: fileType, mimeType: mimeType,
        fileSize: fileSize, extractedText: extractedText,
        );
    }

    // ─── Hook 包裹：Agent 循环层统一 intercept 所有工具调用 ───
    Future<ToolResult> executeToolWithHooks(String toolName, Map<String, dynamic> args) async {
      if (hookPipeline != null) {
        final ctx = HookContext.forToolUse(
          toolName: toolName,
          params: args,
          conversationId: conversationId,
        );
        await hookPipeline!.execute(HookEvent.beforeToolUse, ctx);
        if (ctx.isBlocked) {
          return ToolResult(
            toolName: toolName,
            success: false,
            output: '',
            error: ctx.blockReason ?? '安全策略阻止',
          );
        }
      }

      final result = await executeTool(toolName, args);

      if (hookPipeline != null) {
        if (!result.success) {
          final failCtx = HookContext(HookEvent.onToolFailure, {
            'toolName': toolName,
            'params': args,
            'error': result.error,
            'conversationId': conversationId,
          });
          await hookPipeline!.execute(HookEvent.onToolFailure, failCtx);
        }
        final afterCtx = HookContext(HookEvent.afterToolUse, {
          'toolName': toolName,
          'params': args,
          'success': result.success,
          'output': result.success ? result.output : (result.error ?? ''),
          'conversationId': conversationId,
        });
        await hookPipeline!.execute(HookEvent.afterToolUse, afterCtx);
      }

      return result;
    }

    // ─── 构建初始 API 消息列表 ───
    final apiMessages = <Map<String, dynamic>>[];

    // 恢复模式：从 context_snapshot 加载完整的 apiMessages 快照
    if (resumeFromCheckpoint && messageId != null) {
      final checkpoint = await _db.getPauseCheckpoint(messageId);
      if (checkpoint != null && checkpoint['context_data'] != null) {
        final decoded = jsonDecode(checkpoint['context_data'] as String);
        if (decoded is List) {
          for (final m in decoded) {
            if (m is Map<String, dynamic>) apiMessages.add(m);
          }
        }
      }
    } else {
      // 正常模式：从 history 构建
      final historyHasSystem = history != null && history.any((m) => m['role'] == 'system');
      if (systemPrompt != null) {
        if (systemPrompt is List) {
          // Array 格式（含 cache_control）—— 直接使用，不合并 history 中的 system 消息
          apiMessages.add({'role': 'system', 'content': systemPrompt});
          if (history != null) {
            for (final m in history) {
              if (m['role'] != 'system') {
                apiMessages.add({'role': m['role'], 'content': m['content']});
              }
            }
          }
        } else if (systemPrompt is String && systemPrompt.isNotEmpty) {
          // String 格式 —— 向后兼容旧逻辑
          if (historyHasSystem) {
            for (final m in history!) {
              if (m['role'] == 'system') {
                apiMessages.add({'role': 'system', 'content': '${m['content']}\n\n$systemPrompt'});
              } else {
                apiMessages.add({'role': m['role'], 'content': m['content']});
              }
            }
          } else {
            apiMessages.add({'role': 'system', 'content': systemPrompt});
            if (history != null) {
              for (final m in history!) {
                apiMessages.add({'role': m['role'], 'content': m['content']});
              }
            }
          }
        }
      } else if (history != null) {
        for (final m in history!) {
          apiMessages.add({'role': m['role'], 'content': m['content']});
        }
      }
      // 用户消息使用 array content 格式 + cache_control，使多轮对话历史前缀命中缓存
      apiMessages.add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': message, 'cache_control': {'type': 'ephemeral'}},
        ],
      });
    }

    final tempMsgId = messageId ?? 'native_${DateTime.now().millisecondsSinceEpoch}';
    final toolHandler = ToolExecutionHandler();
    final loopMonitor = LoopMonitor(windowSize: 30);
    const progressInterval = 5;
    const safetyLimit = 200;
    final tracer = AgentTracer(conversationId: conversationId, db: _db);

    // ─── 注入已加载 Skill 的 System Prompt ───
    // 不再插入独立 system 消息（会破坏缓存前缀），改为追加 text block 到主 system 消息。
    var _injectedSkillNames = <String>{};

    void injectLoadedSkillPrompts() {
      final sysIdx = apiMessages.indexWhere((m) => m['role'] == 'system');
      if (sysIdx < 0) return;

      final content = apiMessages[sysIdx]['content'];
      if (content is! List) return; // String 格式向后兼容，不处理

      // 需要更新的 skill 集合
      final target = activeSkills.toSet();
      if (Set<String>.from(_injectedSkillNames).containsAll(target) &&
          target.containsAll(_injectedSkillNames)) return;

      // 移除旧的 skill block（_skill 标记）
      content.removeWhere((b) => b is Map && b['_skill'] == true);

      // 重新注入当前激活的 skill
      for (final name in target) {
        final skill = SkillRegistry.instance.getSkill(name);
        if (skill != null) {
          content.add({
            'type': 'text',
            'text': '【已加载专业能力: ${skill.name}】\n${skill.systemPromptSnippet}',
            '_skill': true, // 本地标记，_syncCacheControl 中会清理
          });
        }
      }
      _injectedSkillNames = target;
    }
    injectLoadedSkillPrompts();

    // ─── 编排建议：检测复杂多步任务，引导模型使用 task_orchestrate ───
    var _orchestrationHintInjected = false;

    void injectOrchestrationHint() {
      if (_orchestrationHintInjected) return;
      final score = _heuristicComplexityScore(message);
      if (score < 4) return;

      final hint = score >= 7
          ? '\n\n此任务复杂度较高（评分$score/10）。强烈建议先调用 task_orchestrate 拆解为子任务再依次执行，避免遗漏步骤或上下文溢出。'
          : '\n\n此任务涉及多个步骤（评分$score/10）。如果子任务较多且相互依赖，建议调用 task_orchestrate 进行系统化拆解。';

      final sysIdx = apiMessages.indexWhere((m) => m['role'] == 'system');
      if (sysIdx >= 0) {
        final content = apiMessages[sysIdx]['content'];
        if (content is List) {
          // Array 格式（buildSystemContent）→ 追加为新的 text block
          (content as List).add({'type': 'text', 'text': hint});
        } else if (content is String) {
          // String 格式（向后兼容）→ 追加到字符串末尾
          apiMessages[sysIdx]['content'] = '$content$hint';
        }
      } else {
        apiMessages.insert(0, {'role': 'system', 'content': hint});
      }
      _orchestrationHintInjected = true;
    }
    injectOrchestrationHint();

    // ─── 缓存断点同步 ───
    // MiniMax 最多 4 个 cache_control 断点。在每轮 LLM 调用前清理并重设，
    // 确保: tools(1) + system static(2) + user msg(3) + 最新消息末 block(4) = 4 个。
    void syncCacheControl() {
      // Step 1: 清除所有 content block 的 cache_control + 本地标记
      for (final msg in apiMessages) {
        final c = msg['content'];
        if (c is List) {
          for (final block in c) {
            if (block is Map) {
              block.remove('cache_control');
              block.remove('_skill');
            }
          }
        }
      }

      // Step 2: 重设 3 个消息级断点
      // [a] 第一条 system 消息的第一个 content block
      final sysIdx = apiMessages.indexWhere((m) => m['role'] == 'system');
      if (sysIdx >= 0) {
        final sc = apiMessages[sysIdx]['content'];
        if (sc is List && sc.isNotEmpty) {
          (sc.first as Map)['cache_control'] = {'type': 'ephemeral'};
        }
      }

      // [b] 第一条 user 消息的第一个 content block
      final userIdx = apiMessages.indexWhere((m) => m['role'] == 'user');
      if (userIdx >= 0) {
        final uc = apiMessages[userIdx]['content'];
        if (uc is List && uc.isNotEmpty) {
          (uc.first as Map)['cache_control'] = {'type': 'ephemeral'};
        }
      }

      // [c] 最后一条消息的最后一个 content block（每轮后移，实现增量缓存）
      if (apiMessages.isNotEmpty) {
        final lc = apiMessages.last['content'];
        if (lc is List && lc.isNotEmpty) {
          (lc.last as Map)['cache_control'] = {'type': 'ephemeral'};
        }
      }
    }
    syncCacheControl();

    // ─── 工具调用循环 ───
    for (int round = 0; round < safetyLimit; round++) {
      if (cancelToken != null && cancelToken.isCancelled) break;
      if (pauseToken != null && pauseToken.isPaused) break;

      // —— LLM 流式调用 ——
      String fullThinking = '';
      String thinkingSignature = '';
      String fullText = '';
      final toolUseBlocks = <Map<String, dynamic>>[];
      bool inToolBlock = false;
      String? currentToolId;
      String? currentToolName;
      String currentToolInput = '';

      final activeTools = tools;
      await for (final chunk in _client.chatStream(
        '',
        tools: activeTools,
        directMessages: apiMessages,
        cancelToken: cancelToken,
        temperature: temperature,
        topP: topP,
        maxTokens: maxTokens,
        thinkingBudgetTokens: thinkingBudgetTokens,
        toolChoice: toolChoice,
      )) {
        if (chunk.isCacheInfo) {
          tracer.recordCacheUsage(
            cacheRead: chunk.cacheReadInputTokens,
            cacheCreate: chunk.cacheCreationInputTokens,
            cacheFresh: chunk.cacheFreshInputTokens,
          );
          final total = chunk.cacheReadInputTokens + chunk.cacheCreationInputTokens + chunk.cacheFreshInputTokens;
          if (total > 0) print('[CACHE] round=$round ${chunk.cacheHitSummary}');
          continue;
        }

        if (chunk.isReconnecting) {
          yield ChatMessage(
            id: 'reconnect_${DateTime.now().millisecondsSinceEpoch}',
            conversationId: conversationId,
            role: MessageRole.system,
            content: chunk.content ?? '🔄 正在重连...',
            createdAt: DateTime.now(),
          );
          continue;
        }

        if (chunk.hasThinking && chunk.thinking != null) fullThinking = chunk.thinking!;
        if (chunk.thinkingSignature != null) thinkingSignature = chunk.thinkingSignature!;
        if (chunk.hasContent && chunk.content != null) fullText = chunk.content!;

        if (chunk.isToolCall && chunk.toolName != null && chunk.toolUseId != null) {
          if (!inToolBlock) {
            inToolBlock = true;
            currentToolId = chunk.toolUseId;
            currentToolName = chunk.toolName;
            currentToolInput = chunk.toolInput ?? '';
          }
        }
        if (chunk.isToolCall && chunk.toolInput != null) {
          currentToolInput = chunk.toolInput!;
        }
        if (chunk.isToolCallFinished && inToolBlock && currentToolId != null) {
          toolUseBlocks.add({
            'id': currentToolId,
            'name': currentToolName ?? 'unknown',
            'input': _parseToolArgs(currentToolInput),
          });
          inToolBlock = false;
          currentToolId = null;
        }

        // 暂停检测 + 取消检测：循环内实时检测，阻断期间所有 yield
        if (pauseToken != null && pauseToken.isPaused) break;
        if (cancelToken != null && cancelToken.isCancelled) break;

        yield ChatMessage(
          id: tempMsgId,
          conversationId: conversationId,
          role: MessageRole.assistant,
          content: fullText,
          createdAt: DateTime.now(),
          thinking: fullThinking.isNotEmpty ? fullThinking : null,
          toolCall: inToolBlock ? currentToolName : null,
          toolInput: inToolBlock ? currentToolInput : null,
        );

        // 内容结束，退出本轮
        if (chunk.isContentFinished) break;
      }

      // 暂停检测：用户主动暂停时，保存 checkpoint 和 partial content，然后停止
      if (pauseToken != null && pauseToken.isPaused) {
        if (messageId != null) {
          _db.updatePartialMessage(
            messageId: messageId,
            conversationId: conversationId,
            partialContent: fullText,
            tokenOffset: 0,
            isTruncated: true,
            streamState: 'paused',
          );
        }
        break;
      }

      // HTTP 流被取消（非暂停）
      if (cancelToken != null && cancelToken.isCancelled) break;

      // —— 截断检测 ——
      if (inToolBlock && currentToolId != null && currentToolName != null) {
        toolUseBlocks.add({
          'id': currentToolId,
          'name': currentToolName,
          'input': _parseToolArgs(currentToolInput),
          '_truncated': true,
        });
        inToolBlock = false;
      }

      if (cancelToken != null && cancelToken.isCancelled) break;

      tracer.recordLlmCall(
        model: _client.model,
        round: round,
        thinkingChars: fullThinking.length,
        thinkingBudget: thinkingBudgetTokens,
        truncated: toolUseBlocks.any((b) => b['_truncated'] == true),
      );

      // —— 无工具调用：正常结束 ——
      if (toolUseBlocks.isEmpty) {
        if (fullText.isNotEmpty) {
          if (messageId != null) {
            await _db.finalizeStreamMessage(
              messageId: messageId, conversationId: conversationId,
              content: fullText,
              thinking: fullThinking.isNotEmpty ? fullThinking : null,

            );
          } else {
            await _db.addMessage(conversationId, 'assistant', fullText,
                id: tempMsgId, thinking: fullThinking.isNotEmpty ? fullThinking : null);
          }
        }
        break;
      }

      // —— 构建 assistant content blocks ——
      final assistantContent = <Map<String, dynamic>>[];
      if (fullThinking.isNotEmpty) {
        final tb = <String, dynamic>{'type': 'thinking', 'thinking': fullThinking};
        if (thinkingSignature.isNotEmpty) tb['signature'] = thinkingSignature;
        assistantContent.add(tb);
      }
      if (fullText.isNotEmpty) {
        assistantContent.add({'type': 'text', 'text': fullText});
      }
      for (final tb in toolUseBlocks) {
        assistantContent.add({
          'type': 'tool_use',
          'id': tb['id'], 'name': tb['name'], 'input': tb['input'],
        });
      }
      apiMessages.add({'role': 'assistant', 'content': assistantContent});

      // —— 上下文用量检查（不截断 thinking，思维链连续性优先） ——
      // thinking 块必须完整保留以满足 MiniMax Interleaved Thinking 的要求。
      // 当上下文用量超过 80% 阈值时，向 UI 层发出信号，
      // 由 ContextManager 的滚动摘要机制在每轮结束后处理压缩。
      if (_isContextNearLimit(apiMessages)) {
        yield ChatMessage(
          id: 'ctx_warn_${DateTime.now().millisecondsSinceEpoch}',
          conversationId: conversationId,
          role: MessageRole.system,
          content: '⚠️ 上下文用量已达 ${(_estimateApiTokens(apiMessages) / _apiContextLimit * 100).toStringAsFixed(0)}%，将在本轮结束后自动压缩。',
          createdAt: DateTime.now(),
        );
      }

      // —— 保存 assistant 文本到 DB ——
      if (messageId != null && round == 0) {
        await _db.finalizeStreamMessage(
          messageId: messageId, conversationId: conversationId,
          content: fullText,
          thinking: fullThinking.isNotEmpty ? fullThinking : null,
        );
      }
      // 中间轮次不再单独存 assistant 消息，避免加载历史时出现重复思考气泡
      // 工具调用结果已通过 tool role 消息保留完整上下文

      // —— handle skill_load / skill_unload before regular tool execution ——
      // 收集所有 meta tool 的 tool_result block，与 regular tool results 合并为一条 user 消息
      final nonActivationBlocks = <Map<String, dynamic>>[];
      final metaToolResultBlocks = <Map<String, dynamic>>[];
      for (final tb in toolUseBlocks) {
        if (tb['name'] == 'skill_load') {
          // ── LLM 自主加载 Skill ──
          final args = tb['input'] is Map
              ? Map<String, dynamic>.from(tb['input'] as Map)
              : <String, dynamic>{};
          final skillName = args['skill_name'] as String? ?? '';
          final skill = SkillRegistry.instance.getSkill(skillName);
          final buf = StringBuffer();
          if (skill != null) {
            activeSkills.add(skillName);
            SkillRegistry.instance.recordUse(skillName);
            _injectedSkillNames.add(skillName);
            // 直接追加到主 system 消息（清理旧 skill block + 重建）
            injectLoadedSkillPrompts();
            buf.writeln('Skill "$skillName" 已加载。以下为该模块的工作指引：');
            buf.writeln(skill.systemPromptSnippet);
          } else {
            buf.writeln('Skill "$skillName" 未找到。可用 skills: ${SkillRegistry.instance.enabledNames.join(", ")}');
          }
          metaToolResultBlocks.add({
            'type': 'tool_result',
            'tool_use_id': tb['id'],
            'content': buf.toString(),
          });
        } else if (tb['name'] == 'skill_unload') {
          // ── LLM 卸载 Skill ──
          final args = tb['input'] is Map
              ? Map<String, dynamic>.from(tb['input'] as Map)
              : <String, dynamic>{};
          final skillName = args['skill_name'] as String? ?? '';
          activeSkills.remove(skillName);
          _injectedSkillNames.remove(skillName);
          injectLoadedSkillPrompts();
          metaToolResultBlocks.add({
            'type': 'tool_result',
            'tool_use_id': tb['id'],
            'content': 'Skill "$skillName" 已卸载。',
          });
        } else {
          nonActivationBlocks.add(tb);
        }
      }

      // —— 执行工具（委托给 ToolExecutionHandler） ——
      final execResult = nonActivationBlocks.isEmpty
          ? const ToolExecutionResult(toolResultBlocks: [])
          : await toolHandler.executeTools(
              blocks: nonActivationBlocks,
              executeTool: executeToolWithHooks,
              loopDetector: loopMonitor.detector,
              onToolStart: (name, argsJson) {},
              onFatal: (reason) {},
            );

      // 暂停检测：用户主动暂停时，保存工具结果到 DB 后停止（保留上下文用于恢复）
      if (pauseToken != null && pauseToken.isPaused) {
        // 保存当前轮次的 assistant 内容（tool_use blocks 等）
        if (messageId != null && (fullText.isNotEmpty || fullThinking.isNotEmpty)) {
          await _db.updatePartialMessage(
            messageId: messageId,
            conversationId: conversationId,
            partialContent: fullText,
            tokenOffset: 0,
            isTruncated: true,
            streamState: 'paused',
          );
        }
        break;
      }

      // HTTP 流被取消（非暂停）
      if (cancelToken != null && cancelToken.isCancelled) {
        yield ChatMessage(
          id: 'paused_${DateTime.now().millisecondsSinceEpoch}',
          conversationId: conversationId,
          role: MessageRole.system,
          content: '⏸️ 生成已暂停，工具结果已阻断。点击继续按钮恢复。',
          createdAt: DateTime.now(),
        );
        break;
      }

      if (execResult.fatalError != null) {
        yield ChatMessage(
          id: 'efatal_${DateTime.now().millisecondsSinceEpoch}',
          conversationId: conversationId,
          role: MessageRole.system,
          content: '⚠️ ${execResult.fatalError}',
          createdAt: DateTime.now(),
        );
        await tracer.flush();
        return;
      }

      // —— 合并所有 tool_result block（meta + regular），保持一条 user 消息 ——
      final allToolResultBlocks = [
        ...metaToolResultBlocks,
        ...execResult.toolResultBlocks,
      ];

      // —— 保存工具结果到 DB ——
      for (final tb in toolUseBlocks) {
        final tr = allToolResultBlocks.firstWhere(
            (r) => r['tool_use_id'] == tb['id'],
            orElse: () => {'tool_use_id': tb['id'], 'content': ''},
          );
        final toolName = tb['name'] as String;
        final content = tr['content'] as String;
        final ok = !content.startsWith('Error:');
        await _db.addMessage(conversationId, 'tool',
            ok ? '【$toolName 执行成功】\n$content' : '【$toolName 执行失败】\n错误：$content',
            );
      }

      // —— 追加到上下文 ——
      if (allToolResultBlocks.isNotEmpty) {
        apiMessages.add({'role': 'user', 'content': allToolResultBlocks});
      }

      // —— 循环检测 ——
      final loopResult = loopMonitor.check();
      if (loopResult.hardStop != null) {
        tracer.recordLoopDetection(nudge: loopResult.hardStop!, severity: 'hard', round: round);
        await tracer.flush();
        yield ChatMessage(
          id: 'loop_hard_${DateTime.now().millisecondsSinceEpoch}',
          conversationId: conversationId,
          role: MessageRole.system,
          content: loopResult.hardStop!,
          createdAt: DateTime.now(),
        );
        return;
      }
      if (loopResult.softNudge != null) {
        tracer.recordLoopDetection(nudge: loopResult.softNudge!, severity: 'soft', round: round);
        // Merge nudge into last tool_result block to avoid consecutive user messages
        final lastUserMsg = apiMessages.last;
        final content = lastUserMsg['content'];
        if (content is List && content.isNotEmpty) {
          final lastBlock = content.last;
          if (lastBlock is Map<String, dynamic>) {
            lastBlock['content'] = '${lastBlock['content']}\n\n[SYSTEM]: ${loopResult.softNudge}';
          }
        }
      }

      // —— 同步缓存断点，下一轮 API 调用可命中本轮增量 ——
      syncCacheControl();

      // —— 进度提示 ——
      if ((round + 1) % progressInterval == 0) {
        yield ChatMessage(
          id: 'progress_${DateTime.now().millisecondsSinceEpoch}',
          conversationId: conversationId,
          role: MessageRole.system,
          content: '⏳ 已完成 ${round + 1} 轮工具调用，任务仍在进行中...',
          createdAt: DateTime.now(),
        );
      }
    }
    await tracer.flush(); // persist execution trace
  }

  /// 解析工具调用参数：先直接解析，失败则 JSON 修复
  static Map<String, dynamic> _parseToolArgs(String input) {
    if (input.isEmpty) return {};
    try {
      final decoded = jsonDecode(input);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {}
    final repaired = JsonRepair.repair(input);
    if (repaired != null) {
      try {
        final decoded = jsonDecode(repaired);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return {};
  }

  /// 估算 apiMessages 列表的 token 开销。
  /// 只做粗略估算，用于判断是否接近上下文窗口上限。
  int _estimateApiTokens(List<Map<String, dynamic>> apiMessages) {
    int totalChars = 0;
    for (final msg in apiMessages) {
      final content = msg['content'];
      if (content is String) {
        totalChars += content.length;
      } else if (content is List) {
        for (final block in content) {
          if (block is Map) {
            final text = block['text'] ?? block['thinking'] ?? '';
            if (text is String) totalChars += text.length;
            final input = block['input'];
            if (input is Map) totalChars += input.toString().length;
            final toolContent = block['content'];
            if (toolContent is String) totalChars += toolContent.length;
          }
        }
      }
    }
    // 中文 ~2 chars/token, 英文 ~4 chars/token, 取中间值 3 + JSON 结构 15% 开销
    return (totalChars / 3.0 * 1.15).round();
  }

  /// MiniMax M2.7 上下文窗口约 200K tokens，保守使用 180K。
  /// 超过此阈值时，应由上层 [ContextManager] 触发滚动摘要，
  /// 而非暴力截断 thinking（这会破坏 Interleaved Thinking 的思维链连续性）。
  static const int _apiContextLimit = 180000;
  static const double _apiContextWarnThreshold = 0.80;

  /// 检查 apiMessages 是否接近上下文窗口上限。
  /// 返回 true 表示应该触发上下文压缩（由上层
  /// [ConversationSession.contextManager] 的滚动摘要机制处理）。
  bool _isContextNearLimit(List<Map<String, dynamic>> apiMessages) {
    final estimated = _estimateApiTokens(apiMessages);
    return estimated > (_apiContextLimit * _apiContextWarnThreshold).round();
  }

  Stream<ChatMessage> streamResponse({
    required String message,
    String? systemPrompt,
    List<Map<String, String>>? history,
    List<Map<String, dynamic>>? tools,
    CancelToken? cancelToken,
    double temperature = 1.0,
    double topP = 0.95,
    int maxTokens = 16384,
    int thinkingBudgetTokens = 6000,
    Map<String, dynamic>? toolChoice,
  }) async* {
    String fullThinking = '';
    String fullContent = '';
    String? toolName;
    String? toolInput;
    bool toolFinished = false;

    await for (final chunk in _client.chatStream(message,
      history: history,
      systemPrompt: systemPrompt,
      tools: tools,
      cancelToken: cancelToken,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      thinkingBudgetTokens: thinkingBudgetTokens,
      toolChoice: toolChoice,
    )) {
      // 重连提示：显示在 UI 但不累积到 fullContent，不写入上下文
      if (chunk.isReconnecting) {
        yield ChatMessage(
          id: 'reconnect_${DateTime.now().millisecondsSinceEpoch}',
          conversationId: '',
          role: MessageRole.system,
          content: chunk.content ?? '🔄 正在重连...',
          createdAt: DateTime.now(),
        );
        continue;
      }

      if (chunk.hasThinking && chunk.thinking != null) {
        fullThinking = chunk.thinking!;
      }
      if (chunk.hasContent && chunk.content != null) {
        fullContent = chunk.content!;
      }

      // 追踪原生工具调用
      if (chunk.isToolCall) {
        toolName = chunk.toolName;
        toolInput = chunk.toolInput;
      }
      if (chunk.isToolCallFinished) {
        toolFinished = true;
      }

      yield ChatMessage(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
        conversationId: '',
        role: MessageRole.assistant,
        content: fullContent,
        createdAt: DateTime.now(),
        thinking: fullThinking.isNotEmpty ? fullThinking : null,
        toolCall: toolFinished ? toolName : null,
        toolInput: toolFinished ? toolInput : null,
      );
    }
  }

  Stream<ChatMessage> streamResponseWithTools({
    required String message,
    required Future<String> Function(String toolName, Map<String, dynamic> args) executeTool, String? systemPrompt,
    List<Map<String, String>>? history,
    CancelToken? cancelToken,
  }) async* {
    String fullThinking = '';
    String fullContent = '';
    final buffer = StringBuffer();

    await for (final chunk in _client.chatStream(message, history: history, systemPrompt: systemPrompt, cancelToken: cancelToken)) {
      if (chunk.hasThinking && chunk.thinking != null) {
        fullThinking = chunk.thinking!;
        yield ChatMessage(
          id: 'thinking_${DateTime.now().millisecondsSinceEpoch}',
          conversationId: '',
          role: MessageRole.assistant,
          content: '',
          createdAt: DateTime.now(),
          thinking: fullThinking,
        );
      }

      if (chunk.hasContent && chunk.content != null) {
        buffer.write(chunk.content);
        var content = buffer.toString();

        int toolStart;
        while ((toolStart = content.indexOf('<tool>')) != -1) {
          final beforeTool = content.substring(0, toolStart);
          if (beforeTool.isNotEmpty) {
            fullContent += beforeTool;
            yield ChatMessage(
              id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
              conversationId: '',
              role: MessageRole.assistant,
              content: fullContent,
              createdAt: DateTime.now(),
            );
          }

          content = content.substring(toolStart + 6);
          buffer.clear();
          buffer.write(content);

          final toolEnd = content.indexOf('</tool>');
          if (toolEnd != -1) {
            final toolJson = content.substring(0, toolEnd);
            content = content.substring(toolEnd + 7);
            buffer.clear();
            buffer.write(content);

            try {
              final json = jsonDecode(toolJson) as Map<String, dynamic>;
              final toolName = json['name'] as String?;
              final args = json['arguments'] as Map<String, dynamic>? ?? {};

              if (toolName != null) {
                yield ChatMessage(
                  id: 'tool_call_${DateTime.now().millisecondsSinceEpoch}',
                  conversationId: '',
                  role: MessageRole.tool,
                  content: '{"name":"$toolName","arguments":$args}',
                  createdAt: DateTime.now(),
                  fileName: toolName,
                );

                final result = await executeTool(toolName, args);
                yield ChatMessage(
                  id: 'tool_result_${DateTime.now().millisecondsSinceEpoch}',
                  conversationId: '',
                  role: MessageRole.tool,
                  content: result,
                  createdAt: DateTime.now(),
                );

                fullContent = '';
              }
            } catch (_) {
              fullContent += '<tool>$toolJson</tool>';
            }
          } else {
            break;
          }
        }

        if (content.isNotEmpty && !content.contains('</tool>')) {
          fullContent += content;
          yield ChatMessage(
            id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
            conversationId: '',
            role: MessageRole.assistant,
            content: fullContent,
            createdAt: DateTime.now(),
          );
          buffer.clear();
        }
      }

      if (chunk.isContentFinished) {
        yield ChatMessage(
          id: 'final_${DateTime.now().millisecondsSinceEpoch}',
          conversationId: '',
          role: MessageRole.assistant,
          content: fullContent,
          createdAt: DateTime.now(),
          thinking: fullThinking.isNotEmpty ? fullThinking : null,
        );
      }
    }
  }

  Future<List<ChatMessage>> getMessages(String conversationId) async {
    final msgs = await _db.getMessages(conversationId);
    return msgs.map((m) => ChatMessage(
      id: m['id'] as String,
      conversationId: m['conversation_id'] as String,
      role: MessageRole.values.firstWhere((r) => r.name == m['role']),
      content: m['content'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      isTruncated: (m['is_truncated'] as int?) == 1,
      partialContent: m['partial_content'] as String?,
      tokenOffset: (m['token_offset'] as int?) ?? 0,
      contentHash: m['content_hash'] as String?,
      messageVersion: (m['message_version'] as int?) ?? 1,
      dependsOn: m['depends_on'] as String?,
      streamState: m['stream_state'] as String? ?? 'completed',
      imageBase64: m['image_base64'] as String?,
      thinking: m['thinking'] as String?,
      fileName: m['file_name'] as String?,
      fileType: m['file_type'] as String?,
      mimeType: m['mime_type'] as String?,
      fileSize: m['file_size'] as int?,
      extractedText: m['extracted_text'] as String?,


    )).toList();
  }

  /// 回溯到指定消息：物理删除该消息及之后的所有消息
  Future<int> backtrackTo(String conversationId, String messageId) async {
    return _db.deleteMessagesFrom(conversationId, messageId);
  }

  Future<String> addMessage(String conversationId, String role, String content, {
    String? thinking,
    String? fileName,
    String? fileType,
    String? mimeType,
    int? fileSize,
    String? extractedText,
  }) =>
      _db.addMessage(conversationId, role, content, thinking: thinking,
        fileName: fileName, fileType: fileType, mimeType: mimeType,
        fileSize: fileSize, extractedText: extractedText,
        );

  Future<String> createConversation(String title, {String? id}) => _db.createConversation(title, id: id);
  Future<List<ChatConversation>> getConversations() async {
    final convs = await _db.getConversations();
    return convs.map((c) => ChatConversation(
      id: c['id'] as String,
      title: c['title'] as String,
      summary: c['summary'] as String?,

      createdAt: DateTime.fromMillisecondsSinceEpoch(c['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(c['updated_at'] as int),
    )).toList();
  }
  Future<void> deleteConversation(String id) => _db.deleteConversation(id);
  Future<void> deleteMessages(String conversationId) => _db.deleteMessagesByConversation(conversationId);

  Future<void> updateSummary(String conversationId, String summary) =>
      _db.updateConversationSummary(conversationId, summary);
  Future<String?> getSummary(String conversationId) =>
      _db.getConversationSummary(conversationId);
  Future<void> saveContext(String conversationId, {required int tokenCount, required int messageCount}) async {
    await _db.updateConversationContext(conversationId, {
      'tokenCount': tokenCount,
      'messageCount': messageCount,
      'lastActive': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<Map<String, dynamic>?> getContext(String conversationId) =>
      _db.getConversationContext(conversationId);

  Future<void> updatePartialMessage({
    required String messageId,
    required String conversationId,
    required String partialContent,
    required int tokenOffset,
    required bool isTruncated,
    required String streamState,
  }) =>
      _db.updatePartialMessage(
        messageId: messageId,
        conversationId: conversationId,
        partialContent: partialContent,
        tokenOffset: tokenOffset,
        isTruncated: isTruncated,
        streamState: streamState,
      );

  Future<void> updateMessageDependsOn(String messageId, String? dependsOn) =>
      _db.updateMessageDependsOn(messageId, dependsOn);

  Future<void> updateMessageVersion(String messageId, int version) =>
      _db.updateMessageVersion(messageId, version);

  Future<Map<String, dynamic>?> getPauseCheckpoint(String messageId) =>
      _db.getPauseCheckpoint(messageId);

  Future<void> updateConversationLastTruncated(String conversationId, String? messageId) =>
      _db.updateConversationLastTruncated(conversationId, messageId);

  Future<List<ChatMessage>> getTruncatedMessages(String conversationId) async {
    final msgs = await _db.getTruncatedMessages(conversationId);
    return msgs.map((m) => ChatMessage(
      id: m['id'] as String,
      conversationId: m['conversation_id'] as String,
      role: MessageRole.values.firstWhere((r) => r.name == m['role']),
      content: m['content'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      isTruncated: (m['is_truncated'] as int?) == 1,
      partialContent: m['partial_content'] as String?,
      tokenOffset: (m['token_offset'] as int?) ?? 0,
      contentHash: m['content_hash'] as String?,
      messageVersion: (m['message_version'] as int?) ?? 1,
      dependsOn: m['depends_on'] as String?,
      streamState: (m['stream_state'] as String?) ?? 'completed',
      imageBase64: m['image_base64'] as String?,
      thinking: m['thinking'] as String?,
      fileName: m['file_name'] as String?,
      fileType: m['file_type'] as String?,
      mimeType: m['mime_type'] as String?,
      fileSize: m['file_size'] as int?,
      extractedText: m['extracted_text'] as String?,
    )).toList();
  }
}
