// ignore_for_file: avoid_dynamic_calls

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'safe_response.dart';

/// 流式响应的单个 chunk，包含思考和内容
class ChatStreamResponse {

  ChatStreamResponse({
    this.thinking,
    this.content,
    this.isThinkingFinished = false,
    this.isContentFinished = false,
    this.thinkingSignature,
    this.serviceTier,
    this.stopReason,
    this.toolName,
    this.toolInput,
    this.toolUseId,
    this.isToolCall = false,
    this.isToolCallFinished = false,
    this.isToolCallTruncated = false,
    this.isReconnecting = false,
    this.cacheReadInputTokens = 0,
    this.cacheCreationInputTokens = 0,
    this.cacheFreshInputTokens = 0,
    this.isCacheInfo = false,
  });
  final String? thinking;
  final String? content;
  final bool isThinkingFinished;
  final bool isContentFinished;
  // 思考签名（用于验证完整性）
  final String? thinkingSignature;
  // 服务层级
  final String? serviceTier;
  // 停止原因
  final String? stopReason;
  // 工具调用相关
  final String? toolName;
  final String? toolInput;
  final String? toolUseId;
  final bool isToolCall;
  final bool isToolCallFinished;
  // 工具调用输入被截断（未收到 content_block_stop）
  final bool isToolCallTruncated;
  // 重连状态（不计入上下文，仅用于 UI 提示）
  final bool isReconnecting;
  // 缓存性能指标（从 message_start 的 usage 中提取）
  final int cacheReadInputTokens;
  final int cacheCreationInputTokens;
  final int cacheFreshInputTokens;
  final bool isCacheInfo; // 标记这是缓存元数据 chunk，非内容

  /// 缓存命中率描述
  String get cacheHitSummary {
    final total = cacheReadInputTokens + cacheCreationInputTokens + cacheFreshInputTokens;
    if (total == 0) return '';
    final hitRate = (cacheReadInputTokens / total * 100).toStringAsFixed(1);
    final read = _formatTokens(cacheReadInputTokens);
    final create = _formatTokens(cacheCreationInputTokens);
    final fresh = _formatTokens(cacheFreshInputTokens);
    return '缓存: 命中=$read 写入=$create 新鲜=$fresh | 命中率=$hitRate%';
  }

  static String _formatTokens(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  bool get hasThinking => thinking != null && thinking!.isNotEmpty;
  bool get hasContent => content != null && content!.isNotEmpty;
  bool get hasToolCall => isToolCall && toolName != null;
}

/// 内部用：解析思考和内容的结果
class _ThinkingContentResult {

  _ThinkingContentResult({this.thinking, this.content});
  final String? thinking;
  final String? content;
}

class MinimaxClient {

  MinimaxClient({
    required this.apiKey,
    this.baseUrl = 'https://api.minimaxi.com',
    this.model = 'MiniMax-M2.7',
  }) {
    _initDio();
  }
  late Dio _dio;
  String apiKey;
  String baseUrl;
  String model;

  static bool isTokenPlanKey(String apiKey) {
    return apiKey.startsWith('sk-cp-');
  }

  static String getKeyType(String apiKey) {
    return isTokenPlanKey(apiKey) ? 'Token Plan (编码计划)' : 'Pay-as-you-go / 按量付费';
  }

  void _initDio() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 5),
      sendTimeout: const Duration(minutes: 2),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'anthropic-version': '2023-06-01',
      },
    ));
    // 调试时取消注释下面这行来查看 HTTP 请求日志：
    // _dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: false));
  }

  void updateConfig({String? apiKey, String? model, String? baseUrl}) {
    if (apiKey != null) this.apiKey = apiKey;
    if (model != null) this.model = model;
    if (baseUrl != null) this.baseUrl = baseUrl;
    _initDio();
  }

  // ============ SSE 解析器 - Anthropic Messages API 格式（支持工具调用） ============
  Stream<(ChatStreamResponse, bool)> _parseSSEStreamWithThinkingAndTools(ResponseBody responseStream) async* {
    final buffer = StringBuffer();

    String currentThinking = '';
    String currentContent = '';
    String currentToolName = '';
    String currentToolInput = '';
    String currentSignature = '';
    String? serviceTier;
    String? stopReason;
    bool inThinkingBlock = false;
    bool inToolBlock = false;
    bool contentFinished = false;

    // 用 stream transformer 处理 UTF-8，避免 emoji 等多字节字符被 chunk 边界切断
    await for (final text in responseStream.stream.cast<List<int>>().transform(utf8.decoder)) {
      buffer.write(text);

      final content = buffer.toString();
      final lines = content.split('\n');

      String lastLine = lines.removeLast();
      buffer.clear();
      buffer.write(lastLine);

      for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final fieldValue = line.substring(5).trim();
        if (fieldValue.isEmpty || fieldValue == '[DONE]') continue;

        try {
          final json = jsonDecode(fieldValue);
          final type = json['type'] as String?;

          if (type == 'message_start') {
            // 获取服务层级 + 缓存性能指标
            final message = json['message'] as Map?;
            serviceTier = message?['service_tier'] as String?;
            final usage = message?['usage'] as Map?;
            if (usage != null) {
              yield (
                ChatStreamResponse(
                  cacheReadInputTokens: (usage['cache_read_input_tokens'] as int?) ?? 0,
                  cacheCreationInputTokens: (usage['cache_creation_input_tokens'] as int?) ?? 0,
                  cacheFreshInputTokens: (usage['input_tokens'] as int?) ?? 0,
                  isCacheInfo: true,
                ),
                true,
              );
            }
          } else if (type == 'content_block_start') {
            final contentBlock = json['content_block'] as Map?;
            final blockType = contentBlock?['type'] as String?;
            if (blockType == 'thinking') {
              inThinkingBlock = true;
              if (currentThinking.isNotEmpty) {
                currentThinking += '\n\n---\n\n';
              }
              currentSignature = '';
              // 提取 content_block_start 中的初始思考文本
              final initThinking = contentBlock?['thinking'] as String?;
              if (initThinking != null && initThinking.isNotEmpty) {
                currentThinking += initThinking;
                yield (ChatStreamResponse(thinking: currentThinking), true);
              }
            } else if (blockType == 'tool_use') {
              inToolBlock = true;
              currentToolName = contentBlock?['name'] as String? ?? '';
              // 捕获 tool_use_id
              final toolUseId = contentBlock?['id'] as String?;
              // MiniMax 在 content_block_start 的 input 是空壳 {}，真正的参数走 input_json_delta
              final directInput = contentBlock?['input'];
              if (directInput is Map && directInput.isEmpty) {
                currentToolInput = '';
              } else if (directInput != null) {
                currentToolInput = directInput is String ? directInput : jsonEncode(directInput);
              } else {
                currentToolInput = '';
              }
              yield (ChatStreamResponse(
                toolName: currentToolName,
                toolUseId: toolUseId,
                toolInput: currentToolInput,
                isToolCall: true,
              ), true);
            }
          } else if (type == 'content_block_delta') {
            final delta = json['delta'] as Map?;
            if (delta == null) continue;

            final deltaType = delta['type'] as String?;
            if (deltaType == 'thinking_delta') {
              inThinkingBlock = true;
              final thinkingText = delta['thinking'] as String?;
              if (thinkingText != null) {
                currentThinking += thinkingText;
                yield (ChatStreamResponse(thinking: currentThinking), true);
              }
            } else if (deltaType == 'signature_delta') {
              // 思考签名
              final sig = delta['signature'] as String?;
              if (sig != null) {
                currentSignature = sig;
                yield (ChatStreamResponse(
                  thinking: currentThinking,
                  thinkingSignature: currentSignature,
                ), true);
              }
            } else if (deltaType == 'text_delta') {
              inThinkingBlock = false;
              final textText = delta['text'] as String?;
              if (textText != null) {
                currentContent += textText;
                yield (ChatStreamResponse(content: currentContent), true);
              }
            } else if (deltaType == 'input_json_delta') {
              // 工具参数的流式累积
              final partialJson = delta['partial_json'] as String?;
                            if (partialJson != null) {
                currentToolInput += partialJson;
                yield (ChatStreamResponse(
                  content: currentContent,
                  toolName: currentToolName,
                  toolInput: currentToolInput,
                  isToolCall: true,
                ), true);
              }
            }
          } else if (type == 'content_block_stop') {
            if (inToolBlock) {
                            yield (ChatStreamResponse(
                content: currentContent,
                toolName: currentToolName,
                toolInput: currentToolInput,
                isToolCall: true,
                isToolCallFinished: true,
              ), true);
              inToolBlock = false;
            }
          } else if (type == 'message_delta') {
            // 获取停止原因
            final delta = json['delta'] as Map?;
            stopReason = delta?['stop_reason'] as String?;
            yield (ChatStreamResponse(
              content: currentContent,
              thinking: currentThinking,
              thinkingSignature: currentSignature,
              stopReason: stopReason,
            ), true);
          } else if (type == 'message_stop') {
            contentFinished = true;
            yield (ChatStreamResponse(
              isContentFinished: true,
              isThinkingFinished: true,
              thinkingSignature: currentSignature,
              serviceTier: serviceTier,
              stopReason: stopReason,
            ), false);
          }
        } catch (e) {
            debugPrint('[SSE] parse error: $e');
          // ignore parse errors
        }
      }
    }

    // handle remaining
    final remaining = buffer.toString().trim();
    if (remaining.isNotEmpty && remaining.startsWith('data:')) {
      final fieldValue = remaining.substring(5).trim();
      if (fieldValue.isNotEmpty && fieldValue != '[DONE]') {
        try {
          final json = jsonDecode(fieldValue);
          final delta = json['delta'] as Map?;
          if (delta != null && delta['type'] == 'text_delta') {
            final textText = delta['text'] as String?;
            if (textText != null) {
              yield (ChatStreamResponse(content: currentContent + textText), false);
            }
          }
        } catch (e) {
            debugPrint('[SSE] parse error: $e');
          // ignore
        }
      }
    }
  }

  /// 从 JSON 中提取思考和内容
  // ignore: unused_element
  _ThinkingContentResult _extractThinkingAndContent(dynamic json) {
    if (json is! Map) return _ThinkingContentResult();

    final type = json['type'] as String?;
    String? thinking;
    String? content;

    if (type == 'content_block_start') {
      final contentBlock = json['content_block'] as Map?;
      if (contentBlock?['type'] == 'thinking') {
        thinking = '';
      }
    } else if (type == 'content_block_delta') {
      final delta = json['delta'] as Map?;
      if (delta != null) {
        final deltaType = delta['type'] as String?;
        if (deltaType == 'thinking_delta') {
          thinking = delta['thinking'] as String?;
        } else if (deltaType == 'text_delta') {
          content = delta['text'] as String?;
        }
      }
    }

    return _ThinkingContentResult(thinking: thinking, content: content);
  }

  // ignore: unused_element
  String? _extractContentFromChunk(dynamic json) {
    if (json is! Map) return null;

    // MiniMax 流式格式: {"type":"content_block_delta","delta":{"type":"text_delta","text":"..."}}
    final type = json['type'] as String?;
    if (type == 'content_block_delta' || type == 'text_delta') {
      final delta = json['delta'] as Map?;
      if (delta != null) {
        return delta['text'] as String?;
      }
    }

    // MiniMax 简化格式: delta.text
    final delta = json['delta'] as Map?;
    if (delta != null) {
      return delta['text'] as String?;
    }

    // OpenAI 流式格式: choices[0].delta.content
    final choices = json['choices'] as List?;
    if (choices != null && choices.isNotEmpty) {
      final deltaChoice = choices[0]['delta'] as Map?;
      if (deltaChoice != null) {
        return deltaChoice['content'] as String?;
      }
    }

    // 非流式格式: choices[0].message.content
    final message = choices?[0]['message'] as Map?;
    if (message != null) {
      return message['content'] as String?;
    }

    return null;
  }

  // ============ 文本对话 (流式) - Anthropic Messages API ============
  /// MiniMax 推荐最佳实践:
  ///   temperature=1.0, top_p=0.95, tool_choice 显式设为 auto
  /// 注意: MiniMax 不支持消息中的 image/document 类型，仅 text/tool_use/tool_result/thinking
  Stream<ChatStreamResponse> chatStream(String message, {
    List<Map<String, String>>? history,
    dynamic systemPrompt,  // String (backward compat) or List<Map> (with cache_control)
    List<Map<String, dynamic>>? tools,
    List<Map<String, dynamic>>? directMessages,
    CancelToken? cancelToken,
    // ── 可覆盖的推理参数 ──
    double temperature = 1.0,           // MiniMax 推荐 1.0，范围 (0, 1.0]
    double topP = 0.95,
    int maxTokens = 16384,
    int thinkingBudgetTokens = 6000,    // 推理预算，Agent 任务需充足思考空间
    Map<String, dynamic>? toolChoice,   // 默认 {type: 'auto'}，可设 {type: 'any'} 或 {type: 'tool', name: 'xxx'}
  }) async* {
    final messages = <Map<String, dynamic>>[];

    // 如果直接传递了消息列表（用于多轮对话），直接使用
    if (directMessages != null && directMessages.isNotEmpty) {
      messages.addAll(directMessages);
    } else {
      // 检查历史消息是否已包含 system 消息（压缩后的摘要）
      final historyHasSystem = history != null && history.any((m) => m['role'] == 'system');

      // 系统提示词：支持 String (向后兼容) 和 List<Map> (cache_control 格式)
      if (systemPrompt != null) {
        if (systemPrompt is List) {
          // Array 格式（含 cache_control）—— 直接使用
          // 忽略 history 中的 system 消息，避免合并破坏缓存前缀
          messages.add({'role': 'system', 'content': systemPrompt});
          if (history != null) {
            for (final m in history) {
              if (m['role'] != 'system') {
                messages.add(m);
              }
            }
          }
        } else if (systemPrompt is String && systemPrompt.isNotEmpty) {
          // String 格式 —— 向后兼容旧逻辑
          if (historyHasSystem) {
            final mergedHistory = <Map<String, dynamic>>[];
            for (final m in history) {
              if (m['role'] == 'system') {
                mergedHistory.add({'role': 'system', 'content': '${m['content']}\n\n$systemPrompt'});
              } else {
                mergedHistory.add(m);
              }
            }
            messages.addAll(mergedHistory);
          } else {
            messages.add({'role': 'system', 'content': systemPrompt});
            if (history != null) messages.addAll(history);
          }
        }
      } else {
        if (history != null) messages.addAll(history);
      }

      // 当前用户消息 - 使用 content 列表格式支持多模态
      if (message.isNotEmpty) {
        if (message.startsWith('data:image')) {
          // 图片消息
          messages.add({
            'role': 'user',
            'content': [
              {'type': 'text', 'text': '请描述这张图片的内容'},
              {'type': 'image', 'source': {'type': 'base64', 'media_type': 'image/jpeg', 'data': message.substring(message.indexOf(',') + 1)}}
            ]
          });
        } else {
          messages.add({'role': 'user', 'content': [{'type': 'text', 'text': message}]});
        }
      }
    }

    // 构建请求体（只需构建一次，重试时复用）
    // 注意: MiniMax 缓存前缀顺序为 tools → system → messages。
    // 如果 JSON 序列化按 key 插入顺序，messages 必须在 tools 之后写入，
    // 否则 tools 的 cache_control 断点会被 messages 的变动覆盖。
    final data = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'top_p': topP,
      'stream': true,
    };

    if (thinkingBudgetTokens > 0) {
      data['thinking'] = {'type': 'enabled', 'budget_tokens': thinkingBudgetTokens};
      debugPrint('[API] thinking enabled: budget_tokens=$thinkingBudgetTokens');
    } else {
      debugPrint('[API] thinking disabled (budget_tokens=0)');
    }

    // tools 放在 messages 之前，满足 MiniMax 前缀匹配顺序
    if (tools != null && tools.isNotEmpty) {
      // 在最后一个工具上加 cache_control，缓存所有工具定义
      final cachedTools = List<Map<String, dynamic>>.from(tools);
      final last = Map<String, dynamic>.from(cachedTools.last);
      if (!last.containsKey('cache_control')) {
        last['cache_control'] = {'type': 'ephemeral'};
        cachedTools[cachedTools.length - 1] = last;
      }
      data['tools'] = cachedTools;
      data['tool_choice'] = toolChoice ?? {'type': 'auto'};
    }

    // messages 放在最后，确保前面 tools + system 前缀稳定
    data['messages'] = messages;

    int retryCount = 0;
    const maxRetries = 10;

    while (true) {
      try {
        final response = await _dio.post<ResponseBody>(
          '/anthropic/v1/messages',
          data: data,
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: true,
          ),
        );

        final responseData = response.data;
        if (responseData == null) {
          throw DioException(
            requestOptions: response.requestOptions,
            message: 'Empty response body from API',
          );
        }
        await for (final entry in _parseSSEStreamWithThinkingAndTools(responseData)) {
          final yielded = entry.$1;
          final shouldContinue = entry.$2;
          if (!shouldContinue) break;
          yield yielded;
        }
        return; // 成功完成，退出重试循环
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) return;

        // 429 / rate-limit: exponential backoff
        final statusCode = e.response?.statusCode;
        final isRateLimited = statusCode == 429 ||
            (e.type == DioExceptionType.badResponse && statusCode == 429);

        final isServerError = statusCode != null && statusCode >= 500 && statusCode < 600;
        final isTransient = isRateLimited ||
            isServerError ||
            e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionTimeout ||
            (e.type == DioExceptionType.unknown && (e.message?.contains('Connection') == true || e.message?.contains('Socket') == true));

        if (!isTransient || retryCount >= maxRetries) {
          throw _handleDioError(e);
        }

        retryCount++;
        if (isRateLimited) {
          final delaySec = (1 << retryCount).clamp(1, 60);
          debugPrint('[API] 请求频率超限，$delaySec秒后重试 ($retryCount/$maxRetries)');
          yield ChatStreamResponse(
            content: '🔄 API 请求频率超限，$delaySec秒后自动重试... ($retryCount/$maxRetries)',
            isReconnecting: true,
          );
          await Future.delayed(Duration(seconds: delaySec));
        } else if (isServerError) {
          final delaySec = (retryCount * 3).clamp(1, 30);
          debugPrint('[API] 服务器错误 (HTTP $statusCode)，${delaySec}秒后重试 ($retryCount/$maxRetries)');
          yield ChatStreamResponse(
            content: '🔄 服务端异常 (HTTP $statusCode)，${delaySec}秒后自动重试... ($retryCount/$maxRetries)',
            isReconnecting: true,
          );
          await Future.delayed(Duration(seconds: delaySec));
        } else {
          final errMsg = _extractErrorSummary(e);
          debugPrint('[API] 流式连接中断 ($errMsg)，${retryCount * 2}秒后重试 ($retryCount/$maxRetries)');
          yield ChatStreamResponse(
            content: '🔄 网络波动（$errMsg），正在重连... ($retryCount/$maxRetries)',
            isReconnecting: true,
          );
          await Future.delayed(Duration(seconds: retryCount * 2));
        }
      } catch (e) {
        // 流式传输中途断开（SocketException 等非 DioException 错误）
        if (cancelToken != null && cancelToken.isCancelled) return;
        if (retryCount >= maxRetries) rethrow;

        retryCount++;
        final errMsg = e.toString();
        final shortMsg = errMsg.length > 60 ? '${errMsg.substring(0, 60)}...' : errMsg;
        debugPrint('[API] 流失中断 ($shortMsg)，${retryCount * 2}秒后重试 ($retryCount/$maxRetries)');
        yield ChatStreamResponse(
          content: '🔄 连接中断，${retryCount * 2}秒后重连... ($retryCount/$maxRetries)',
          isReconnecting: true,
        );
        await Future.delayed(Duration(seconds: retryCount * 2));
      }
    }
  }

  // ============ 文本对话 (非流式收集) ============
  Future<String> chatCollect(String message, {
    List<Map<String, String>>? history,
    dynamic systemPrompt,
    List<Map<String, dynamic>>? tools,
    double temperature = 1.0,
    double topP = 0.95,
    int maxTokens = 16384,
    int thinkingBudgetTokens = 6000,
    Map<String, dynamic>? toolChoice,
  }) async {
    String result = '';
    await for (final chunk in chatStream(message,
      history: history,
      systemPrompt: systemPrompt,
      tools: tools,
      temperature: temperature,
      topP: topP,
      maxTokens: maxTokens,
      thinkingBudgetTokens: thinkingBudgetTokens,
      toolChoice: toolChoice,
    )) {
      if (chunk.hasContent && chunk.content != null) {
        result = chunk.content!;
      }
    }
    return result;
  }

  // ============ Embedding ============
  /// MiniMax embedding API — 返回 1536 维 float32 向量。
  /// [type]: "db"（存储时）或 "query"（检索时）。
  Future<List<double>> embed(String text, {String type = 'query'}) async {
    try {
      final response = await _dio.post(
        '/v1/embeddings',
        data: {
          'model': 'embo-01',
          'texts': [text],
          'type': type,
        },
      );
      final vectors = response.data['vectors'] as List?;
      if (vectors == null || vectors.isEmpty) {
        throw MinimaxApiException('Embedding returned empty vectors');
      }
      final vec = vectors[0] as List;
      return vec.cast<double>();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// 批量 embedding（最多支持 texts.length <= 10）。
  Future<List<List<double>>> embedBatch(List<String> texts, {String type = 'db'}) async {
    try {
      final response = await _dio.post(
        '/v1/embeddings',
        data: {
          'model': 'embo-01',
          'texts': texts,
          'type': type,
        },
      );
      final vectors = response.data['vectors'] as List?;
      if (vectors == null) {
        throw MinimaxApiException('Embedding returned null vectors');
      }
      return vectors.cast<List>().map((v) => v.cast<double>()).toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 语音合成 T2A (流式) ============
  Stream<Map<String, dynamic>> textToAudioStream({
    required String text,
    String model = 'speech-2.8-hd',
    String voiceId = 'male-qn-qingse',
    double speed = 1.0,
    double vol = 1.0,
    int pitch = 0,
    String? emotion,
    int sampleRate = 32000,
    int bitrate = 128000,
    String format = 'mp3',
  }) async* {
    try {
      final response = await _dio.post(
        '/v1/t2a_v2',
        data: {
          'model': model,
          'text': text,
          'stream': true,
          'voice_setting': {
            'voice_id': voiceId,
            'speed': speed,
            'vol': vol,
            'pitch': pitch,
            if (emotion != null) 'emotion': emotion,
          },
          'audio_setting': {
            'sample_rate': sampleRate,
            'bitrate': bitrate,
            'format': format,
            'channel': 1,
          },
          'output_format': 'hex',
        },
        options: Options(responseType: ResponseType.stream),
      );

      final stream = response.data.stream as Stream<List<int>>;
      String buffer = '';

      await for (final chunk in stream) {
        buffer += utf8.decode(chunk);
        while (buffer.contains('\n')) {
          final newlineIdx = buffer.indexOf('\n');
          final line = buffer.substring(0, newlineIdx).trim();
          buffer = buffer.substring(newlineIdx + 1);

          if (line.isEmpty) continue;

          // SSE 格式: "data: {...}" → 去掉前缀
          final jsonStr = line.startsWith('data: ') ? line.substring(6) : line;
          if (!jsonStr.startsWith('{')) continue;

          try {
            final json = jsonDecode(jsonStr) as Map<String, dynamic>;
            final data = json['data'] as Map<String, dynamic>?;
            if (data != null) {
              yield {
                'audio': _parseString(data['audio']) ?? '',
                'status': data['status'] as int? ?? 0,
              };
            }
          } catch (_) {
            // 跳过解析失败的行
          }
        }
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 语音合成 T2A (非流式，返回 hex) ============
  Future<String> textToAudio({
    required String text,
    String model = 'speech-2.8-hd',
    String voiceId = 'male-qn-qingse',
    double speed = 1.0,
    double vol = 1.0,
    int pitch = 0,
    String? emotion,
    int sampleRate = 32000,
    int bitrate = 128000,
    String format = 'mp3',
  }) async {
    try {
      final response = await _dio.post(
        '/v1/t2a_v2',
        data: {
          'model': model,
          'text': text,
          'stream': false,
          'voice_setting': {
            'voice_id': voiceId,
            'speed': speed,
            'vol': vol,
            'pitch': pitch,
            if (emotion != null) 'emotion': emotion,
          },
          'audio_setting': {
            'sample_rate': sampleRate,
            'bitrate': bitrate,
            'format': format,
            'channel': 1,
          },
          'output_format': 'hex',
        },
      );

      final data = response.data['data'] as Map<String, dynamic>?;
      if (data == null) {
        throw MinimaxApiException('Speech synthesis failed / 语音合成失败', statusCode: 2013);
      }
      
      return data['audio'] as String? ?? '';
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  String _extractErrorSummary(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timeout / 连接超时';
      case DioExceptionType.receiveTimeout:
        return 'Response timeout / 响应超时';
      case DioExceptionType.connectionError:
        return 'Connection interrupted / 连接中断';
      default:
        return 'Network error / 网络异常';
    }
  }

  MinimaxApiException _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return MinimaxApiException('Connection timeout, please check network / 连接超时，请检查网络');
      case DioExceptionType.sendTimeout:
        return MinimaxApiException('Request send timeout / 发送请求超时');
      case DioExceptionType.receiveTimeout:
        return MinimaxApiException('Response receive timeout / 接收响应超时');
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final responseData = e.response?.data;
        final path = e.requestOptions.path;
        final (message, apiCode, hint) = _extractErrorDetails(responseData, path);
        return MinimaxApiException(message, statusCode: statusCode, apiCode: apiCode, hint: hint);
      case DioExceptionType.cancel:
        return MinimaxApiException('Request cancelled / 请求已取消');
      default:
        return MinimaxApiException('Network error: ${e.message} / 网络错误: ${e.message}');
    }
  }

  (String message, int? apiCode, String? hint) _extractErrorDetails(dynamic data, String path) {
    if (data == null) return ('Server error / 服务器错误', null, null);
    if (data is! Map) return ('Unknown error / 未知错误', null, null);

    final baseResp = data['base_resp'] as Map?;
    final apiCode = baseResp?['status_code'] as int?;
    final statusMsg = baseResp?['status_msg'] as String? ?? '';

    final error = data['error'] as Map?;
    final errorCode = error?['code'] as int? ?? apiCode;
    final errorMsg = error?['message'] as String? ?? statusMsg;

    String hint = _planHintForUrl(path);

    // 认证/授权
    if (errorCode == 1004 || errorCode == 2049) {
      return ('API Key invalid or expired / API Key 无效或已失效', errorCode, '💡 请检查 API Key 是否正确且已激活\n🔗 获取新 Key: https://platform.minimaxi.com/subscription');
    }
    if (errorCode == 401 || errorCode == 403) {
      return ('Unauthorized access, check API Key / 未授权访问，请检查 API Key', errorCode, '💡 请检查 API Key 是否正确\n🔗 获取新 Key: https://platform.minimaxi.com/subscription');
    }

    // Quota/balance/rate limit / 配额/余额/限流
    if (errorCode == 1008) {
      return ('Insufficient account balance / 账户余额不足', errorCode, '💡 请充值后重试\n🔗 充值: https://platform.minimaxi.com/subscription');
    }
    if (errorCode == 1028 || errorCode == 1030 || errorCode == 2056) {
      return ('Quota exhausted, wait for refresh or upgrade plan / 配额已用尽，请等待刷新或升级计划', errorCode, '💡 查看配额: 设置 > TokenPlan 配额\n🔗 升级计划: https://platform.minimaxi.com/subscription\n$hint');
    }
    if (errorCode == 1002 || errorCode == 2045) {
      return ('Rate limit exceeded, try again later / 请求频率超限，请稍后重试', errorCode, '💡 请降低请求频率\n$hint');
    }
    if (errorCode == 1041) {
      return ('Connection limit exceeded / 连接数超限', errorCode, '💡 请稍后重试或联系官方支持');
    }

    // Content moderation / 内容审核
    if (errorCode == 1026) {
      return ('Input triggered safety review / 输入内容触发安全审核', errorCode, '💡 请修改输入内容后重试');
    }
    if (errorCode == 1027) {
      return ('Output triggered safety review / 输出内容触发安全审核', errorCode, '💡 请修改输入内容后重试');
    }
    if (errorCode == 1039) {
      return ('Token limit exceeded: $statusMsg / Token 超限: $statusMsg', errorCode, '💡 请缩短输入内容');
    }
    if (errorCode == 1042) {
      return ('Input contains too many illegal characters / 输入包含过多非法字符', errorCode, '💡 请检查输入文本');
    }

    // Model/plan mismatch / 模型/计划不匹配
    if (errorCode == 2061) {
      final modelName = _extractModelFromPath(path, data);
      if (path.contains('/music_generation')) {
        return ('Token Plan key does not support $modelName model / Token Plan 密钥不支持 $modelName 模型', errorCode, '💡 当前模型需要 Max 计划或 Standard API Key\n🔗 升级: https://platform.minimaxi.com/subscription');
      }
      return ('Current plan does not support this model: $modelName / 当前计划不支持此模型: $modelName', errorCode, '💡 请升级到对应计划\n🔗 升级: https://platform.minimaxi.com/subscription\n$hint');
    }

    // Server side / 服务端
    if (errorCode == 1000 || errorCode == 1033) {
      return ('Service busy, try again later / 服务繁忙，请稍后重试', errorCode, '💡 如持续出现请联系官方支持');
    }
    if (errorCode == 1024 || errorCode == 500 || errorCode == 5000) {
      return ('Server internal error / 服务器内部错误', errorCode, '💡 请稍后重试');
    }

    // Voice related / 语音相关
    if (errorCode == 2037) return ('Audio duration not compliant (requires 10s~5min) / 语音时长不符合要求（需10秒~5分钟）', errorCode, '💡 请调整音频时长');
    if (errorCode == 2038) return ('Voice cloning not enabled / 语音克隆功能未启用', errorCode, '💡 请完成账户身份认证');
    if (errorCode == 2048) return ('Prompt audio too long / 提示音频过长', errorCode, '💡 请使用8秒以内的音频');
    if (errorCode == 2013 || errorCode == 20132) {
      return ('Parameter error: $statusMsg / 参数错误: $statusMsg', errorCode, '💡 请检查请求参数');
    }

    return (errorMsg.isNotEmpty ? errorMsg : 'Server error / 服务器错误', apiCode, hint.isNotEmpty ? hint : null);
  }

  String _extractModelFromPath(String path, dynamic data) {
    if (data is Map) {
      final dataObj = data['data'] as Map?;
      if (dataObj != null && dataObj.containsKey('model')) {
        return dataObj['model'] as String? ?? 'Unknown model / 未知模型';
      }
    }
    if (path.contains('/music_generation')) return 'music-2.6';
    if (path.contains('/video_generation')) return 'video-01';
    if (path.contains('/image_generation')) return 'image-01';
    if (path.contains('/t2a')) return 'speech-02';
    return 'Unknown model / 未知模型';
  }

  String _planHintForUrl(String url) {
    if (url.contains('/t2a')) return '⚠️ Speech synthesis requires Plus plan or above / 语音合成需要 Plus 计划或以上';
    if (url.contains('/image_generation')) return '⚠️ Image generation requires Plus plan or above / 图片生成需要 Plus 计划或以上';
    if (url.contains('/video_generation') || url.contains('/query/video_generation')) return '⚠️ Video generation requires Max plan or above / 视频生成需要 Max 计划或以上';
    if (url.contains('/music_generation')) return '⚠️ Music generation requires Max plan or above / 音乐生成需要 Max 计划或以上';
    return '';
  }

  // ============ 视觉理解 ============
  Future<String> vision(String imageBase64, String prompt) async {
    try {
      // 转换为 data URI 格式
      final dataUri = 'data:image/jpeg;base64,$imageBase64';
      final response = await _dio.post(
        '/v1/coding_plan/vlm',
        data: {
          'prompt': prompt,
          'image_url': dataUri,
        },
      );

      return response.data['content'] as String? ?? '';
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 图像生成 (image-01) ============
  Future<ImageGenResult> imageGenerate(String prompt, {
    String model = 'image-01',
    String ratio = '16:9',
    String? style,
    int n = 1,
    bool promptOptimizer = false,
    bool aigcWatermark = false,
  }) async {
    final data = <String, dynamic>{
      'model': model,
      'prompt': prompt,
      'aspect_ratio': ratio,
      'n': n,
      'prompt_optimizer': promptOptimizer,
      'aigc_watermark': aigcWatermark,
    };
    if (style != null) data['style'] = style;

    try {
      final response = await _dio.post('/v1/image_generation', data: data);
      final respData = response.data as Map<String, dynamic>?;
      final baseResp = respData?['base_resp'] as Map<String, dynamic>?;

      if (baseResp != null && baseResp['status_code'] != 0) {
        throw MinimaxApiException('Image generation failed: ${baseResp['status_msg'] ?? 'Unknown error / 未知错误'}');
      }

      final dataObj = respData?['data'] as Map<String, dynamic>?;

      final imageUrls = List<String>.from(dataObj?['image_urls'] ?? []);
      final base64Images = List<String>.from(dataObj?['image_base64'] ?? []);

      final metadata = respData?['metadata'] as Map<String, dynamic>?;
      final successCount = _parseInt(metadata?['success_count']);
      final failedCount = _parseInt(metadata?['failed_count']);

      return ImageGenResult(
        taskId: respData?['id'] as String?,
        imageUrls: imageUrls,
        base64Images: base64Images,
        successCount: successCount,
        failedCount: failedCount,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 图生图 ============
  Future<ImageGenResult> imageToImage({
    required String imageBase64,
    required String prompt,
    String model = 'image-01',
    String ratio = '1:1',
    String? style,
    int n = 1,
    bool promptOptimizer = false,
    bool aigcWatermark = false,
  }) async {
    try {
      final dataUrl = 'data:image/jpeg;base64,$imageBase64';
      final response = await _dio.post('/v1/image_generation', data: {
        'model': model,
        'prompt': prompt,
        'aspect_ratio': ratio,
        'n': n,
        'prompt_optimizer': promptOptimizer,
        'aigc_watermark': aigcWatermark,
        'subject_reference': [
          {
            'type': 'character',
            'image_file': dataUrl,
          }
        ],
      });

      final respData = response.data as Map<String, dynamic>?;
      final baseResp = respData?['base_resp'] as Map<String, dynamic>?;

      if (baseResp != null && baseResp['status_code'] != 0) {
        throw MinimaxApiException('Image-to-image failed: ${baseResp['status_msg'] ?? 'Unknown error / 未知错误'}');
      }

      final dataObj = respData?['data'] as Map<String, dynamic>?;
      final imageUrls = List<String>.from(dataObj?['image_urls'] ?? []);
      final base64Images = List<String>.from(dataObj?['image_base64'] ?? []);
      final metadata = respData?['metadata'] as Map<String, dynamic>?;
      final successCount = _parseInt(metadata?['success_count']);
      final failedCount = _parseInt(metadata?['failed_count']);

      return ImageGenResult(
        taskId: respData?['id'] as String?,
        imageUrls: imageUrls,
        base64Images: base64Images,
        successCount: successCount,
        failedCount: failedCount,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is double) return value.toInt();
    return 0;
  }
  Future<VideoGenResult> videoGenerate(String prompt, {
    String model = 'MiniMax-Hailuo-2.3',
    String? firstFrameImage,
    String? lastFrameImage,
    bool promptOptimizer = true,
    bool fastPretreatment = false,
    int duration = 6,
    String resolution = '768P',
    bool aigcWatermark = false,
  }) async {
    final data = <String, dynamic>{
      'model': model,
      'prompt': prompt,
      'prompt_optimizer': promptOptimizer,
      'fast_pretreatment': fastPretreatment,
      'duration': duration,
      'resolution': resolution,
      'aigc_watermark': aigcWatermark,
    };
    if (firstFrameImage != null) data['first_frame_image'] = firstFrameImage;
    if (lastFrameImage != null) data['last_frame_image'] = lastFrameImage;

    try {
      final response = await _dio.post('/v1/video_generation', data: data);
      final respData = response.data as Map<String, dynamic>?;
      final baseResp = respData?['base_resp'] as Map<String, dynamic>?;

      if (baseResp?['status_code'] != 0) {
        throw MinimaxApiException('Video generation failed: ${baseResp?['status_msg'] ?? 'Unknown error / 未知错误'}');
      }

      return VideoGenResult(
        taskId: respData?['task_id'] as String? ?? '',
        status: 'pending',
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 图生视频 ============
  Future<VideoGenResult> imageToVideo(String imageBase64, String prompt, {
    String model = 'MiniMax-Hailuo-2.3',
    bool promptOptimizer = true,
    bool fastPretreatment = false,
    int duration = 6,
    String resolution = '768P',
    bool aigcWatermark = false,
  }) async {
    try {
      final response = await _dio.post('/v1/video_generation', data: {
        'model': model,
        'prompt': prompt,
        'first_frame_image': imageBase64,
        'prompt_optimizer': promptOptimizer,
        'fast_pretreatment': fastPretreatment,
        'duration': duration,
        'resolution': resolution,
        'aigc_watermark': aigcWatermark,
      });
      final respData = response.data as Map<String, dynamic>?;
      final baseResp = respData?['base_resp'] as Map<String, dynamic>?;

      if (baseResp?['status_code'] != 0) {
        throw MinimaxApiException('Video generation failed: ${baseResp?['status_msg'] ?? 'Unknown error / 未知错误'}');
      }

      return VideoGenResult(
        taskId: respData?['task_id'] as String? ?? '',
        status: 'pending',
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 主体参考视频生成 (S2V-01) ============
  Future<VideoGenResult> subjectReferenceToVideo({
    required String subjectImageUrl,
    required String prompt,
    String model = 'S2V-01',
    bool promptOptimizer = true,
    bool aigcWatermark = false,
    String? callbackUrl,
  }) async {
    try {
      final data = <String, dynamic>{
        'model': model,
        'prompt': prompt,
        'prompt_optimizer': promptOptimizer,
        'aigc_watermark': aigcWatermark,
        'subject_reference': [
          {
            'type': 'character',
            'image': [subjectImageUrl],
          }
        ],
      };
      if (callbackUrl != null) data['callback_url'] = callbackUrl;

      final response = await _dio.post('/v1/video_generation', data: data);
      final respData = response.data as Map<String, dynamic>?;
      final baseResp = respData?['base_resp'] as Map<String, dynamic>?;

      if (baseResp?['status_code'] != 0) {
        throw MinimaxApiException('Subject reference video generation failed: ${baseResp?['status_msg'] ?? 'Unknown error / 未知错误'}');
      }

      return VideoGenResult(
        taskId: respData?['task_id'] as String? ?? '',
        status: 'pending',
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 音乐生成 ============
  Future<MusicGenResult> musicGenerate({
    required String prompt,
    String? lyrics,
    bool autoLyrics = false,
    bool isInstrumental = false,
    String model = 'music-2.6',
    String? audioUrl,
    String? audioBase64,
    bool stream = false,
    bool aigcWatermark = false,
  }) async {
    try {
      final data = <String, dynamic>{
        'model': model,
        'prompt': prompt,
        'is_instrumental': isInstrumental,
        'lyrics_optimizer': autoLyrics,
        'stream': stream,
        'aigc_watermark': aigcWatermark,
        'audio_setting': {
          'format': 'mp3',
          'sample_rate': 44100,
          'bitrate': 256000,
        },
        'output_format': 'url',
      };
      if (lyrics != null && lyrics.isNotEmpty) data['lyrics'] = lyrics;
      if (audioUrl != null) data['audio_url'] = audioUrl;
      if (audioBase64 != null) data['audio_base64'] = audioBase64;

      final response = await _dio.post(
        '/v1/music_generation',
        data: data,
        options: Options(receiveTimeout: const Duration(minutes: 5)),
      );

      final respData = response.data as Map<String, dynamic>?;
      final dataObj = respData?['data'] as Map<String, dynamic>?;
      final extraInfo = respData?['extra_info'] as Map<String, dynamic>?;

      final audioUrlResult = dataObj?['audio_url'] as String? ?? dataObj?['audio'] as String?;
      final audioBase64Result = dataObj?['audio_base64'] as String?;

      if (audioUrlResult != null || audioBase64Result != null) {
        return MusicGenResult(
          taskId: null,
          status: 'completed',
          audioUrl: audioUrlResult,
          audioBase64: audioBase64Result,
          duration: extraInfo?['music_duration'] as int?,
          sampleRate: extraInfo?['music_sample_rate'] as int?,
          bitrate: extraInfo?['bitrate'] as int?,
        );
      }

      return MusicGenResult(
        taskId: dataObj?['task_id'] as String?,
        status: 'pending',
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.receiveTimeout) {
        final data = e.response?.data as Map<String, dynamic>?;
        final dataObj = data?['data'] as Map<String, dynamic>?;
        final taskId = dataObj?['task_id'] ?? data?['task_id'];
        if (taskId != null) {
          return MusicGenResult(taskId: taskId as String?, status: 'pending');
        }
      }
      throw _handleDioError(e);
    }
  }

  // ============ 翻唱预处理 ============
  Future<CoverPreprocessResult> coverPreprocess({
    required String model,
    String? audioUrl,
    String? audioBase64,
  }) async {
    try {
      final data = <String, dynamic>{'model': model};
      if (audioUrl != null) data['audio_url'] = audioUrl;
      if (audioBase64 != null) data['audio_base64'] = audioBase64;

      final response = await _dio.post('/v1/music_cover_preprocess', data: data);
      final respData = response.data as Map<String, dynamic>?;
      final baseResp = respData?['base_resp'] as Map<String, dynamic>?;

      if (baseResp?['status_code'] != 0) {
        throw MinimaxApiException('Preprocessing failed: ${baseResp?['status_msg'] ?? 'Unknown error / 未知错误'}');
      }

      return CoverPreprocessResult(
        coverFeatureId: respData?['cover_feature_id'] as String? ?? '',
        formattedLyrics: respData?['formatted_lyrics'] as String? ?? '',
        structureResult: respData?['structure_result'] as String? ?? '',
        audioDuration: respData?['audio_duration'] as double? ?? 0,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 歌词生成 ============
  Future<LyricsGenResult> generateLyrics({
    required String mode,
    String? prompt,
    String? lyrics,
    String? title,
  }) async {
    try {
      final data = <String, dynamic>{'mode': mode};
      if (prompt != null && prompt.isNotEmpty) data['prompt'] = prompt;
      if (lyrics != null && lyrics.isNotEmpty) data['lyrics'] = lyrics;
      if (title != null && title.isNotEmpty) data['title'] = title;

      final response = await _dio.post('/v1/lyrics_generation', data: data);
      final respData = response.data as Map<String, dynamic>?;
      final baseResp = respData?['base_resp'] as Map<String, dynamic>?;

      if (baseResp?['status_code'] != 0) {
        throw MinimaxApiException('Lyrics generation failed: ${baseResp?['status_msg'] ?? 'Unknown error / 未知错误'}');
      }

      return LyricsGenResult(
        songTitle: respData?['song_title'] as String? ?? '',
        styleTags: respData?['style_tags'] as String? ?? '',
        lyrics: respData?['lyrics'] as String? ?? '',
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 语音合成 (TTS) ============
  Future<String> speechSynthesize(String text, {
    String model = 'speech-2.8-turbo',
    String voiceId = 'male-qn-qingse',
    double speed = 1.0,
    double vol = 1.0,
    int pitch = 0,
    String? emotion,
    int sampleRate = 32000,
    int bitrate = 128000,
    String format = 'mp3',
  }) async {
    try {
      final response = await _dio.post('/v1/t2a_v2', data: {
        'model': model,
        'text': text,
        'stream': false,
        'voice_setting': {
          'voice_id': voiceId,
          'speed': speed,
          'vol': vol,
          'pitch': pitch,
          if (emotion != null) 'emotion': emotion,
        },
        'audio_setting': {
          'sample_rate': sampleRate,
          'bitrate': bitrate,
          'format': format,
          'channel': 1,
        },
        'output_format': 'url',
      });

      final baseResp = response.data['base_resp'] as Map<String, dynamic>?;
      if (baseResp != null && baseResp['status_code'] != 0) {
        throw MinimaxApiException(
          'Speech synthesis failed: ${baseResp['status_msg'] ?? 'Unknown error / 未知错误'}',
          statusCode: baseResp['status_code'] as int? ?? -1,
        );
      }

      final data = response.data['data'] as Map<String, dynamic>?;
      if (data == null) {
        throw MinimaxApiException('Speech synthesis failed: no data returned / 语音合成失败: 无数据返回', statusCode: 2013);
      }

      return data['audio'] as String? ?? '';
    } on MinimaxApiException {
      rethrow;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 异步语音合成 (T2A Async) ============
  Future<SpeechAsyncResult> speechSynthesizeAsync({
    String model = 'speech-2.8-turbo',
    String? text,
    String? textFileId,
    String voiceId = 'male-qn-qingse',
    double speed = 1.0,
    double vol = 1.0,
    int pitch = 0,
    String? emotion,
    int sampleRate = 32000,
    int bitrate = 128000,
    String format = 'mp3',
    int channel = 2,
    String? languageBoost,
    Map<String, dynamic>? pronunciationDict,
    Map<String, dynamic>? voiceModify,
    bool aigcWatermark = false,
    bool englishNormalization = false,
  }) async {
    if ((text == null || text.isEmpty) && (textFileId == null || textFileId.isEmpty)) {
      throw MinimaxApiException('At least one of text or text_file_id must be provided / text 和 text_file_id 必须至少提供一个', statusCode: 2013);
    }

    try {
      final body = <String, dynamic>{
        'model': model,
        'voice_setting': {
          'voice_id': voiceId,
          'speed': speed,
          'vol': vol,
          'pitch': pitch,
          if (emotion != null) 'emotion': emotion,
          'english_normalization': englishNormalization,
        },
        'audio_setting': {
          'audio_sample_rate': sampleRate,
          'bitrate': bitrate,
          'format': format,
          'channel': channel,
        },
        'aigc_watermark': aigcWatermark,
      };

      if (text != null && text.isNotEmpty) {
        body['text'] = text;
      }
      if (textFileId != null && textFileId.isNotEmpty) {
        body['text_file_id'] = textFileId;
      }
      if (languageBoost != null && languageBoost.isNotEmpty) {
        body['language_boost'] = languageBoost;
      }
      if (pronunciationDict != null) {
        body['pronunciation_dict'] = pronunciationDict;
      }
      if (voiceModify != null) {
        body['voice_modify'] = voiceModify;
      }

      final response = await _dio.post('/v1/t2a_async_v2', data: body);

      final baseResp = response.data['base_resp'] as Map<String, dynamic>?;
      if (baseResp != null && baseResp['status_code'] != 0) {
        throw MinimaxApiException(
          'Async speech synthesis failed: ${baseResp['status_msg'] ?? 'Unknown error / 未知错误'}',
          statusCode: baseResp['status_code'] as int? ?? -1,
        );
      }

      return SpeechAsyncResult(
        taskId: _parseString(response.data['task_id']) ?? '',
        fileId: _parseFileId(response.data['file_id']),
        taskToken: _parseString(response.data['task_token']) ?? '',
        usageCharacters: response.data['usage_characters'] as int? ?? 0,
      );
    } on MinimaxApiException {
      rethrow;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 查询异步语音合成任务状态 ============
  Future<SpeechAsyncTaskStatus> getSpeechAsyncTaskStatus(String taskId) async {
    try {
      final response = await _dio.get('/v1/query/t2a_async_query_v2', queryParameters: {
        'task_id': taskId,
      });

      final data = SafeResponse.asMap(response.data);

      final baseResp = data['base_resp'] as Map<String, dynamic>?;
      if (baseResp != null && baseResp['status_code'] != 0) {
        throw MinimaxApiException(
          'Query speech task failed: ${baseResp['status_msg'] ?? 'Unknown error / 未知错误'}',
          statusCode: baseResp['status_code'] as int? ?? -1,
        );
      }

      return SpeechAsyncTaskStatus(
        taskId: _parseString(data['task_id']) ?? taskId,
        status: _parseString(data['status']) ?? 'unknown',
        fileId: _parseFileId(data['file_id']),
      );
    } on MinimaxApiException {
      rethrow;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 音色设计 (Voice Design) ============
  Future<VoiceDesignResult> voiceDesign({
    required String prompt,
    required String previewText,
    String? voiceId,
    bool aigcWatermark = false,
  }) async {
    try {
      final body = <String, dynamic>{
        'prompt': prompt,
        'preview_text': previewText,
        'aigc_watermark': aigcWatermark,
      };
      if (voiceId != null && voiceId.isNotEmpty) body['voice_id'] = voiceId;

      final response = await _dio.post('/v1/voice_design', data: body);
      final data = response.data as Map<String, dynamic>?;
      final baseResp = data?['base_resp'] as Map<String, dynamic>?;

      if (baseResp?['status_code'] != 0) {
        throw MinimaxApiException(
          'Voice design failed: ${baseResp?['status_msg'] ?? 'Unknown error / 未知错误'}',
        );
      }

      return VoiceDesignResult(
        voiceId: _parseString(data?['voice_id']) ?? '',
        trialAudioHex: _parseString(data?['trial_audio']),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 音色列表查询 ============
  Future<VoiceListResult> getVoiceListAll() async {
    try {
      final response = await _dio.post('/v1/get_voice', data: {'voice_type': 'all'});
      debugPrint('Voice API response: $response');
      final respData = response.data as Map<String, dynamic>?;
      if (respData == null) return VoiceListResult();

      final systemVoice = (respData['system_voice'] as List? ?? []).map((v) => VoiceInfo(
        voiceId: _parseString(v['voice_id']) ?? '',
        voiceName: _parseString(v['voice_name']) ?? '',
        descriptions: (v['description'] as List?)?.map((d) => d.toString()).toList() ?? [],
      )).toList();

      final clonedVoices = (respData['voice_cloning'] as List? ?? []).map((v) => VoiceInfo(
        voiceId: _parseString(v['voice_id']) ?? '',
        voiceName: _parseString(v['voice_id']) ?? '',
        descriptions: (v['description'] as List?)?.map((d) => d.toString()).toList() ?? [],
      )).toList();

      final generatedVoices = (respData['voice_generation'] as List? ?? []).map((v) => VoiceInfo(
        voiceId: _parseString(v['voice_id']) ?? '',
        voiceName: _parseString(v['voice_id']) ?? '',
        descriptions: (v['description'] as List?)?.map((d) => d.toString()).toList() ?? [],
      )).toList();

      debugPrint('Cloned voices: ${clonedVoices.length}, Generated voices: ${generatedVoices.length}');
      return VoiceListResult(
        systemVoices: systemVoice,
        clonedVoices: clonedVoices,
        generatedVoices: generatedVoices,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 删除音色 ============
  Future<void> deleteVoice(String voiceId, String voiceType) async {
    try {
      final response = await _dio.post('/v1/delete_voice', data: {
        'voice_id': voiceId,
        'voice_type': voiceType,
      });
      final data = response.data as Map<String, dynamic>?;
      final baseResp = data?['base_resp'] as Map<String, dynamic>?;
      if (baseResp?['status_code'] != 0) {
        throw MinimaxApiException('Delete failed: ${baseResp?['status_msg'] ?? 'Unknown error / 未知错误'}');
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 配额查询 ============
  Future<QuotaInfo> getQuota() async {
    try {
      // 配额接口使用 api 子域名
      final host = baseUrl.contains('minimaxi.com') ? 'https://api.minimaxi.com' : 'https://api.minimax.io';
      final quotaDio = Dio(BaseOptions(
        baseUrl: host,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Authorization': 'Bearer $apiKey'},
      ));

      final response = await quotaDio.get('/v1/token_plan/remains');
      final data = response.data;
      final remainsList = (data['model_remains'] as List?) ?? [];

      final models = remainsList.map((m) => QuotaModelInfo(
        modelName: m['model_name'] as String? ?? 'Unknown',
        remainsTime: m['remains_time'] as int? ?? 0,
        currentIntervalTotal: m['current_interval_total_count'] as int? ?? 0,
        currentIntervalUsage: m['current_interval_usage_count'] as int? ?? 0,
        currentWeeklyTotal: m['current_weekly_total_count'] as int? ?? 0,
        currentWeeklyUsage: m['current_weekly_usage_count'] as int? ?? 0,
        weeklyStartTime: m['weekly_start_time'] as int? ?? 0,
        weeklyEndTime: m['weekly_end_time'] as int? ?? 0,
      )).toList();

      return QuotaInfo(models: models);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 网络搜索 ============
  Future<SearchResult> search(String query) async {
    try {
      final response = await _dio.post('/v1/coding_plan/search', data: {'q': query});
      final data = response.data;
      final organic = (data['organic'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      return SearchResult(
        results: organic.map((item) => SearchItem(
          title: item['title'] as String? ?? '',
          link: item['link'] as String? ?? '',
          snippet: item['snippet'] as String? ?? '',
          date: item['date'] as String?,
        )).toList(),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 复刻音频上传 ============
  Future<String> uploadCloneVoiceAudio(String filePath) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
        'purpose': 'voice_clone',
      });
      final response = await _dio.post('/v1/files/upload', data: formData);
      final fileInfo = response.data['file'] as Map<String, dynamic>?;
      return fileInfo?['file_id'] as String? ?? '';
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 示例音频上传 ============
  Future<String> uploadPromptAudio(String filePath) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
        'purpose': 'prompt_audio',
      });
      final response = await _dio.post('/v1/files/upload', data: formData);
      final fileInfo = response.data['file'] as Map<String, dynamic>?;
      return fileInfo?['file_id'] as String? ?? '';
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 音色快速复刻 ============
  Future<VoiceCloneResult> voiceClone({
    required String fileId,
    required String voiceId,
    String? promptAudioFileId,
    String? promptText,
    String? text,
    String? model,
    bool needNoiseReduction = false,
    bool needVolumeNormalization = false,
    bool aigcWatermark = false,
  }) async {
    try {
      final body = <String, dynamic>{
        'file_id': fileId,
        'voice_id': voiceId,
        'need_noise_reduction': needNoiseReduction,
        'need_volume_normalization': needVolumeNormalization,
        'aigc_watermark': aigcWatermark,
      };
      if (promptAudioFileId != null && promptText != null) {
        body['clone_prompt'] = {
          'prompt_audio': promptAudioFileId,
          'prompt_text': promptText,
        };
      }
      if (text != null) body['text'] = text;
      if (model != null) body['model'] = model;

      final response = await _dio.post('/v1/voice_clone', data: body);
      final data = response.data as Map<String, dynamic>?;
      final baseResp = data?['base_resp'] as Map<String, dynamic>?;

      if (baseResp?['status_code'] != 0) {
        throw MinimaxApiException(
          'Clone failed: ${baseResp?['status_msg'] ?? 'Unknown error / 未知错误'}',
        );
      }

      return VoiceCloneResult(
        demoAudioUrl: _parseString(data?['demo_audio']) ?? '',
        inputSensitiveType: data?['input_sensitive']?['type'] as int? ?? 0,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 文件上传 ============
  Future<String> uploadFile(String filePath, String purpose) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
        'purpose': purpose,
      });
      final response = await _dio.post('/v1/files', data: formData);
      return SafeResponse.str(SafeResponse.asMap(response.data), 'file_id');
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 文件下载 ============
  Future<FileDownloadResult> downloadFile(String fileId) async {
    try {
      // 1. 先获取文件元数据和下载链接
      final metaResp = await _dio.get('/v1/files/retrieve?file_id=$fileId');
      final data = metaResp.data as Map<String, dynamic>;
      final fileObj = data['file'] as Map<String, dynamic>?;

      String? dlUrl;
      if (fileObj != null) {
        dlUrl = _parseString(fileObj['download_url'])
            ?? _parseString(fileObj['url']);
      }
      dlUrl ??= _parseString(data['download_url'])
          ?? _parseString(data['url']);

      final filename = _parseString(fileObj?['filename'])
          ?? _parseString(data['filename'])
          ?? 'download_$fileId';

      // 2. 有 URL 直接返回
      if (dlUrl != null && dlUrl.isNotEmpty) {
        return FileDownloadResult(
          fileId: _parseString(fileObj?['file_id']) ?? fileId,
          bytes: fileObj?['bytes'] as int? ?? data['bytes'] as int? ?? 0,
          createdAt: fileObj?['created_at'] as int? ?? data['created_at'] as int? ?? 0,
          filename: filename,
          purpose: _parseString(fileObj?['purpose']) ?? _parseString(data['purpose']) ?? '',
          downloadUrl: dlUrl,
        );
      }

      // 3. 没有 URL，走 retrieve_content 直接下载二进制存临时目录
      debugPrint('[downloadFile] 无 download_url，改用 retrieve_content');
      final contentResp = await _dio.get(
        '/v1/files/retrieve_content?file_id=$fileId',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = contentResp.data as List<int>;
      final dir = Directory.systemTemp;
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);
      debugPrint('[downloadFile] 文件已保存: ${file.path} (${bytes.length} bytes)');
      return FileDownloadResult(
        fileId: fileId,
        bytes: bytes.length,
        createdAt: fileObj?['created_at'] as int? ?? data['created_at'] as int? ?? 0,
        filename: filename,
        purpose: _parseString(fileObj?['purpose']) ?? _parseString(data['purpose']) ?? '',
        downloadUrl: file.path,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 文件列表 ============
  Future<List<FileInfo>> listFiles(String purpose) async {
    try {
      final response = await _dio.get('/v1/files/list', queryParameters: {'purpose': purpose});
      final data = SafeResponse.asMap(response.data);
      final files = data['files'] as List? ?? [];
      return files.map((f) => FileInfo(
        fileId: _parseString(f['file_id']) ?? '',
        bytes: f['bytes'] as int? ?? 0,
        createdAt: f['created_at'] as int? ?? 0,
        filename: _parseString(f['filename']) ?? '',
        purpose: _parseString(f['purpose']) ?? '',
      )).toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 文件删除 ============
  Future<void> deleteFile(String fileId) async {
    try {
      final response = await _dio.delete('/v1/files/delete', data: {'file_id': fileId});
      final data = SafeResponse.asMap(response.data);
      final baseResp = data['base_resp'] as Map<String, dynamic>?;
      if (baseResp != null && baseResp['status_code'] != 0) {
        throw MinimaxApiException(
          'Delete file failed: ${_parseString(baseResp['status_msg']) ?? 'Unknown error / 未知错误'}',
          statusCode: baseResp['status_code'] as int? ?? -1,
        );
      }
    } on MinimaxApiException {
      rethrow;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 视频模板生成 ============
  Future<VideoGenResult> videoTemplateGeneration({
    required String templateId,
    List<String>? textInputs,
    List<String>? mediaInputs,
    List<String>? mediaBase64Inputs,
    String? callbackUrl,
    bool aigcWatermark = false,
  }) async {
    try {
      final data = <String, dynamic>{
        'template_id': templateId,
        'aigc_watermark': aigcWatermark,
      };

      if (textInputs != null && textInputs.isNotEmpty) {
        data['text_inputs'] = textInputs.map((v) => {'value': v}).toList();
      }

      if (mediaInputs != null && mediaInputs.isNotEmpty) {
        data['media_inputs'] = mediaInputs.map((v) => {'value': v}).toList();
      }

      if (mediaBase64Inputs != null && mediaBase64Inputs.isNotEmpty) {
        final existingMedia = data['media_inputs'] as List? ?? [];
        for (final base64 in mediaBase64Inputs) {
          existingMedia.add({'value': base64});
        }
        data['media_inputs'] = existingMedia;
      }

      if (callbackUrl != null) data['callback_url'] = callbackUrl;

      final response = await _dio.post('/v1/video_template_generation', data: data);
      final respData = response.data as Map<String, dynamic>?;
      final baseResp = respData?['base_resp'] as Map<String, dynamic>?;

      if (baseResp?['status_code'] != 0) {
        throw MinimaxApiException('Video template generation failed: ${baseResp?['status_msg'] ?? 'Unknown error / 未知错误'}');
      }

      return VideoGenResult(
        taskId: respData?['task_id'] as String? ?? '',
        status: 'pending',
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ============ 查询任务状态 ============
  /// 官方文档: GET /v1/query/video_generation
  /// 响应仅包含 task_id / status / file_id / video_width / video_height / base_resp
  /// 不包含 video_url / download_url，需通过 file_id 调 /v1/files/retrieve 获取下载链接
  Future<TaskStatus> getTaskStatus(String taskId) async {
    try {
      var response = await _dio.get('/v1/query/video_generation?task_id=$taskId');
      var data = response.data;

      // 兼容旧版 { data: { ... } } 包裹
      if (data['data'] != null) {
        data = SafeResponse.mapField(data, 'data');
      }

      // 检查 base_resp 错误码（即使 HTTP 200 也可能有业务错误）
      final baseResp = data['base_resp'] as Map<String, dynamic>?;
      final statusCode = baseResp?['status_code'] as int?;
      if (statusCode != null && statusCode != 0) {
        throw MinimaxApiException(
          baseResp?['status_msg'] as String? ?? 'Query task failed / 查询任务失败',
          apiCode: statusCode,
        );
      }

      final fileId = _parseFileId(data['file_id']);

      return TaskStatus(
        taskId: taskId,
        status: _parseString(data['status']) ?? 'unknown',
        fileId: fileId,
        result: data['result'] as Map<String, dynamic>?,
        videoWidth: data['video_width'] as int?,
        videoHeight: data['video_height'] as int?,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// file_id 可能为 int（JSON number）或 String
  String? _parseString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  String? _parseFileId(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    if (v is int) return v.toString();
    return v.toString();
  }

  // ============ 查询视频模板任务状态 ============
  Future<VideoTemplateTaskStatus> getVideoTemplateTaskStatus(String taskId) async {
    try {
      var response = await _dio.get('/v1/query/video_template_generation?task_id=$taskId');
      var data = SafeResponse.asMap(response.data);

      if (data['data'] != null) {
        data = SafeResponse.mapField(data, 'data');
      }

      // 检查 base_resp 错误码
      final baseResp = data['base_resp'] as Map<String, dynamic>?;
      final statusCode = baseResp?['status_code'] as int?;
      if (statusCode != null && statusCode != 0) {
        throw MinimaxApiException(
          baseResp?['status_msg'] as String? ?? 'Query template task failed / 查询模板任务失败',
          apiCode: statusCode,
        );
      }

      return VideoTemplateTaskStatus(
        taskId: taskId,
        status: data['status'] as String? ?? 'unknown',
        videoUrl: data['video_url'] as String?,
        fileId: _parseFileId(data['file_id']),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }
}

// ============ 异常类 ============
class MinimaxApiException implements Exception {

  MinimaxApiException(this.message, {this.statusCode, this.apiCode, this.hint});
  final String message;
  final int? statusCode;
  final int? apiCode;
  final String? hint;

  @override
  String toString() {
    final buffer = StringBuffer('MinimaxApiException: $message');
    if (statusCode != null) buffer.write(' (HTTP $statusCode)');
    if (apiCode != null) buffer.write(' [Error code: $apiCode / 错误码: $apiCode]');
    if (hint != null) buffer.write('\n$hint');
    return buffer.toString();
  }
}

class QuotaExhaustedException extends MinimaxApiException {
  QuotaExhaustedException(super.message, {super.apiCode, super.hint});
}

class PlanNotSupportedException extends MinimaxApiException {
  PlanNotSupportedException(super.message, {super.apiCode, super.hint});
}

// ============ 结果模型 ============
class ImageGenResult {

  ImageGenResult({
    this.taskId,
    this.imageUrls = const [],
    this.base64Images = const [],
    this.successCount = 0,
    this.failedCount = 0,
  });
  final String? taskId;
  final List<String> imageUrls;
  final List<String> base64Images;
  final int successCount;
  final int failedCount;
}

class VideoGenResult {

  VideoGenResult({required this.taskId, this.status = 'pending'});
  final String taskId;
  final String status;
}

class MusicGenResult {

  MusicGenResult({
    this.taskId,
    this.status = 'pending',
    this.audioUrl,
    this.audioBase64,
    this.duration,
    this.sampleRate,
    this.bitrate,
  });
  final String? taskId;
  final String status;
  final String? audioUrl;
  final String? audioBase64;
  final int? duration;
  final int? sampleRate;
  final int? bitrate;
}

class CoverPreprocessResult {

  CoverPreprocessResult({
    required this.coverFeatureId,
    required this.formattedLyrics,
    required this.structureResult,
    required this.audioDuration,
  });
  final String coverFeatureId;
  final String formattedLyrics;
  final String structureResult;
  final double audioDuration;
}

class LyricsGenResult {

  LyricsGenResult({
    required this.songTitle,
    required this.styleTags,
    required this.lyrics,
  });
  final String songTitle;
  final String styleTags;
  final String lyrics;
}

class VoiceDesignResult {

  VoiceDesignResult({required this.voiceId, this.previewUrl, this.trialAudioHex});
  final String voiceId;
  final String? previewUrl;
  final String? trialAudioHex;
}

class VoiceListResult {

  VoiceListResult({
    this.systemVoices = const [],
    this.clonedVoices = const [],
    this.generatedVoices = const [],
  });
  final List<VoiceInfo> systemVoices;
  final List<VoiceInfo> clonedVoices;
  final List<VoiceInfo> generatedVoices;

  List<VoiceInfo> get allVoices => [...systemVoices, ...clonedVoices, ...generatedVoices];
}

class VoiceCloneResult {

  VoiceCloneResult({required this.demoAudioUrl, required this.inputSensitiveType});
  final String demoAudioUrl;
  final int inputSensitiveType;
}

class SpeechAsyncResult {

  SpeechAsyncResult({
    required this.taskId,
    this.fileId,
    this.taskToken = '',
    this.usageCharacters = 0,
  });
  final String taskId;
  final String? fileId;
  final String taskToken;
  final int usageCharacters;
}

class SpeechAsyncTaskStatus {

  SpeechAsyncTaskStatus({
    required this.taskId,
    required this.status,
    this.fileId,
  });
  final String taskId;
  final String status;
  final String? fileId;

  bool get isProcessing => status.toLowerCase() == 'processing';
  bool get isSuccess => status.toLowerCase() == 'success';
  bool get isFailed => status.toLowerCase() == 'failed';
  bool get isExpired => status.toLowerCase() == 'expired';
  bool get isCompleted => isSuccess || isFailed || isExpired;
}

class VoiceInfo {

  VoiceInfo({required this.voiceId, required this.voiceName, required this.descriptions});
  final String voiceId;
  final String voiceName;
  final List<String> descriptions;
}

class QuotaInfo {

  QuotaInfo({required this.models});
  final List<QuotaModelInfo> models;
}

class QuotaModelInfo {

  QuotaModelInfo({
    required this.modelName,
    required this.remainsTime,
    required this.currentIntervalTotal,
    required this.currentIntervalUsage,
    required this.currentWeeklyTotal,
    required this.currentWeeklyUsage,
    required this.weeklyStartTime,
    required this.weeklyEndTime,
  });
  final String modelName;
  final int remainsTime;
  final int currentIntervalTotal;
  final int currentIntervalUsage;
  final int currentWeeklyTotal;
  final int currentWeeklyUsage;
  final int weeklyStartTime;
  final int weeklyEndTime;

  double get usagePercent => currentIntervalTotal > 0 ? currentIntervalUsage / currentIntervalTotal : 0;
  int get remaining => currentIntervalTotal - currentIntervalUsage;
  bool get isAvailable => remaining > 0;
}

class SearchResult {

  SearchResult({required this.results});
  final List<SearchItem> results;
}

class SearchItem {

  SearchItem({required this.title, required this.link, required this.snippet, this.date});
  final String title;
  final String link;
  final String snippet;
  final String? date;
}

class TaskStatus {

  TaskStatus({
    required this.taskId,
    this.status = 'unknown',
    this.fileId,
    this.result,
    this.videoWidth,
    this.videoHeight,
  });
  final String taskId;
  final String status;
  final String? fileId;
  final Map<String, dynamic>? result; // 音乐生成等非视频任务使用
  final int? videoWidth;
  final int? videoHeight;
}

class VideoTemplateTaskStatus {

  VideoTemplateTaskStatus({
    required this.taskId,
    this.status = 'unknown',
    this.videoUrl,
    this.fileId,
  });
  final String taskId;
  final String status;
  final String? videoUrl;
  final String? fileId;
}

class FileInfo {

  FileInfo({
    required this.fileId,
    required this.bytes,
    required this.createdAt,
    required this.filename,
    required this.purpose,
  });
  final String fileId;
  final int bytes;
  final int createdAt;
  final String filename;
  final String purpose;
}

class FileDownloadResult {

  FileDownloadResult({
    required this.fileId,
    required this.bytes,
    required this.createdAt,
    required this.filename,
    required this.purpose,
    required this.downloadUrl,
  });
  final String fileId;
  final int bytes;
  final int createdAt;
  final String filename;
  final String purpose;
  final String downloadUrl;
}

// ============ 可用模型常量 ============
enum PlanRequirement { base, plus, max }

class MinimaxModels {
  static const textModels = [
    'MiniMax-M2.7',
    'MiniMax-M2.7-highspeed',
    'MiniMax-M2.5',
    'MiniMax-M2.5-highspeed',
    'MiniMax-M2.1',
    'MiniMax-M2.1-highspeed',
    'MiniMax-M2',
  ];

  static const speechModels = [
    'speech-2.8-hd',
    'speech-2.8-turbo',
    'speech-2.6-hd',
    'speech-2.6-turbo',
    'speech-02-hd',
    'speech-02-turbo',
  ];

  static const systemVoices = [
    'male-qn-qingse',
    'female-qn-qingse',
    'male-sha',
    'female-sha',
    'male-yunyang',
    'female-yunyang',
  ];

  static const videoModels = [
    'MiniMax-Hailuo-2.3-6s-768p',
    'MiniMax-Hailuo-2.3-Fast-6s-768p',
  ];

  static const imageModels = [
    'image-01',
    'image-01-live',
  ];

  static const aspectRatios = [
    '1:1',
    '16:9',
    '9:16',
    '4:3',
    '3:4',
  ];

  static PlanRequirement getPlanRequirement(String model) {
    if (speechModels.contains(model)) return PlanRequirement.plus;
    if (imageModels.contains(model)) return PlanRequirement.plus;
    if (videoModels.contains(model)) return PlanRequirement.max;
    if (model.startsWith('music')) return PlanRequirement.max;
    return PlanRequirement.base;
  }

  static String getPlanLabel(PlanRequirement plan) {
    switch (plan) {
      case PlanRequirement.base:
        return 'Basic / 基础';
      case PlanRequirement.plus:
        return 'Plus';
      case PlanRequirement.max:
        return 'Max';
    }
  }

  static String getPlanHint(String model) {
    final plan = getPlanRequirement(model);
    if (plan == PlanRequirement.base) return '';
    if (plan == PlanRequirement.plus) return '⚠️ Plus plan required / 需要 Plus 计划';
    return '⚠️ Max plan required / 需要 Max 计划';
  }
}