/// LLM provider abstraction.
///
/// The [LlmProvider] interface decouples Instructor from any specific
/// LLM vendor. Each provider translates [CompletionRequest] to its
/// native API format and normalises responses back to [ProviderResponse]
/// / [ProviderStreamEvent].
library;

import 'dart:convert';

import '../api/minimax_client.dart';
import 'models.dart';
import 'schema.dart';

// ── Abstract interface ──

abstract class LlmProvider {
  String get providerId;
  String get defaultModel;
  bool get supportsForcedToolChoice;

  /// Send a completion request and return the full response.
  Future<ProviderResponse> complete(
    CompletionRequest request,
    SchemaDefinition schema,
  );

  /// Stream a completion, yielding partial content and tool call deltas.
  Stream<ProviderStreamEvent> streamComplete(
    CompletionRequest request,
    SchemaDefinition schema,
  );
}

// ── MiniMax provider ──

class MinimaxProvider implements LlmProvider {

  MinimaxProvider(this._client);
  final MinimaxClient _client;

  @override
  String get providerId => 'minimax';

  @override
  String get defaultModel => _client.model;

  @override
  bool get supportsForcedToolChoice => true;

  // ── complete (non-streaming collection) ──

  @override
  Future<ProviderResponse> complete(
    CompletionRequest request,
    SchemaDefinition schema,
  ) async {
    final anthropicMessages = _buildAnthropicMessages(request);

    String fullText = '';
    String fullThinking = '';
    final toolUseEntries = <String, _PendingToolUse>{};
    String? stopReason;
    String? serviceTier;

    await for (final chunk in _client.chatStream(
      '',
      systemPrompt: request.systemPrompt,
      tools: [schema.toAnthropicTool()],
      directMessages: anthropicMessages,
      temperature: request.temperature,
      topP: request.topP,
      maxTokens: request.maxTokens,
      thinkingBudgetTokens: request.thinkingBudgetTokens,
      toolChoice: schema.forceToolChoice,
    )) {
      if (chunk.isReconnecting) continue;

      // Track service tier
      if (chunk.serviceTier != null) serviceTier = chunk.serviceTier;
      if (chunk.stopReason != null) stopReason = chunk.stopReason;

      // Accumulate thinking
      if (chunk.thinking != null && chunk.thinking!.isNotEmpty) {
        fullThinking = chunk.thinking!;
      }

      // Accumulate text
      if (chunk.content != null && chunk.content!.isNotEmpty) {
        fullText = chunk.content!;
      }

      // Accumulate tool call
      if (chunk.isToolCall && chunk.toolUseId != null) {
        final entry = toolUseEntries.putIfAbsent(
          chunk.toolUseId!,
          () => _PendingToolUse(
            id: chunk.toolUseId!,
            name: chunk.toolName ?? schema.name,
          ),
        );
        if (chunk.toolInput != null) {
          entry.inputFragments.add(chunk.toolInput!);
        }
      }
    }

    // Build content blocks
    final contentBlocks = <ContentBlock>[];
    if (fullThinking.isNotEmpty) {
      contentBlocks.add(ContentBlock.thinking(fullThinking));
    }
    if (fullText.isNotEmpty) {
      contentBlocks.add(ContentBlock.text(fullText));
    }

    // Build tool calls
    final toolCalls = <ToolCallBlock>[];
    for (final entry in toolUseEntries.values) {
      final input = entry.parsedInput;
      if (input != null) {
        contentBlocks.add(ContentBlock.toolUse(
          name: entry.name,
          id: entry.id,
          input: input,
        ));
        toolCalls.add(ToolCallBlock(
          id: entry.id,
          name: entry.name,
          input: input,
        ));
      }
    }

    return ProviderResponse(
      text: fullText.isNotEmpty ? fullText : null,
      contentBlocks: contentBlocks,
      toolCalls: toolCalls,
      stopReason: stopReason,
      model: serviceTier,
    );
  }

  // ── streamComplete (streaming) ──

  @override
  Stream<ProviderStreamEvent> streamComplete(
    CompletionRequest request,
    SchemaDefinition schema,
  ) async* {
    final anthropicMessages = _buildAnthropicMessages(request);

    bool inToolBlock = false;
    String? currentToolId;
    String? currentToolName;

    await for (final chunk in _client.chatStream(
      '',
      systemPrompt: request.systemPrompt,
      tools: [schema.toAnthropicTool()],
      directMessages: anthropicMessages,
      temperature: request.temperature,
      topP: request.topP,
      maxTokens: request.maxTokens,
      thinkingBudgetTokens: request.thinkingBudgetTokens,
      toolChoice: schema.forceToolChoice,
    )) {
      if (chunk.isReconnecting) continue;

      // Text delta — only yield when not in a tool block
      if (chunk.content != null &&
          chunk.content!.isNotEmpty &&
          !chunk.isToolCall) {
        yield ProviderStreamEvent.textDelta(chunk.content!);
      }

      // Tool call start
      if (chunk.isToolCall && chunk.toolUseId != null && !inToolBlock) {
        inToolBlock = true;
        currentToolId = chunk.toolUseId;
        currentToolName = chunk.toolName ?? schema.name;
        yield ProviderStreamEvent.toolCallStart(
          name: currentToolName,
          id: currentToolId!,
        );
      }

      // Tool call delta (partial JSON)
      if (inToolBlock && chunk.toolInput != null) {
        yield ProviderStreamEvent.toolCallDelta(chunk.toolInput!);
      }

      // Tool call end — the chunk carries the complete accumulated input JSON
      if (chunk.isToolCallFinished && inToolBlock) {
        inToolBlock = false;
        Map<String, dynamic> input = {};
        try {
          if (chunk.toolInput != null && chunk.toolInput!.isNotEmpty) {
            input = jsonDecode(chunk.toolInput!) as Map<String, dynamic>;
          }
        } catch (_) {}

        yield ProviderStreamEvent.toolCallEnd(
          name: currentToolName ?? schema.name,
          id: currentToolId ?? '',
          input: input,
        );
      }
    }

    yield ProviderStreamEvent.done();
  }

  // ── Helpers ──

  /// Convert provider-agnostic [Message] list to Anthropic content
  /// block format that MinimaxClient.chatStream expects via
  /// directMessages.
  List<Map<String, dynamic>> _buildAnthropicMessages(
      CompletionRequest request) {
    final messages = <Map<String, dynamic>>[];

    // System prompt — 支持 String 和 List<Map>（含 cache_control）
    if (request.systemPrompt != null) {
      if (request.systemPrompt is List) {
        messages.add({'role': 'system', 'content': request.systemPrompt});
      } else if (request.systemPrompt is String && request.systemPrompt.isNotEmpty) {
        messages.add({'role': 'system', 'content': request.systemPrompt});
      }
    }

    for (int i = 0; i < request.messages.length; i++) {
      final msg = request.messages[i];
      final isLast = i == request.messages.length - 1;

      switch (msg.role) {
        case MessageRole.user:
          // 最后一条 user 消息的最后一个 text block 加 cache_control
          if (isLast) {
            messages.add({
              'role': 'user',
              'content': [
                {'type': 'text', 'text': msg.content, 'cache_control': {'type': 'ephemeral'}},
              ],
            });
          } else {
            messages.add({
              'role': 'user',
              'content': [
                {'type': 'text', 'text': msg.content},
              ],
            });
          }
          break;

        case MessageRole.assistant:
          if (msg.isToolUse && msg.toolName != null && msg.toolInput != null) {
            // 最后一条 tool_use 消息的 tool_use block 加 cache_control
            if (isLast) {
              messages.add({
                'role': 'assistant',
                'content': [
                  {
                    'type': 'tool_use',
                    'id': msg.toolUseId ?? 'tool_${msg.toolName}',
                    'name': msg.toolName,
                    'input': msg.toolInput,
                    'cache_control': {'type': 'ephemeral'},
                  }
                ],
              });
            } else {
              messages.add({
                'role': 'assistant',
                'content': [
                  {
                    'type': 'tool_use',
                    'id': msg.toolUseId ?? 'tool_${msg.toolName}',
                    'name': msg.toolName,
                    'input': msg.toolInput,
                  }
                ],
              });
            }
          } else if (msg.content.isNotEmpty) {
            messages.add({
              'role': 'assistant',
              'content': [
                {'type': 'text', 'text': msg.content}
              ],
            });
          } else {
            messages.add({
              'role': 'assistant',
              'content': [
                {'type': 'text', 'text': ''}
              ],
            });
          }
          break;

        case MessageRole.tool:
          // 最后一条 tool_result 的 tool_result block 加 cache_control
          if (isLast) {
            messages.add({
              'role': 'user',
              'content': [
                {
                  'type': 'tool_result',
                  'tool_use_id': msg.toolUseId ?? '',
                  'content': msg.content,
                  'cache_control': {'type': 'ephemeral'},
                }
              ],
            });
          } else {
            messages.add({
              'role': 'user',
              'content': [
                {
                  'type': 'tool_result',
                  'tool_use_id': msg.toolUseId ?? '',
                  'content': msg.content,
                }
              ],
            });
          }
          break;

        case MessageRole.system:
          messages.add({'role': 'system', 'content': msg.content});
          break;
      }
    }

    return messages;
  }
}

/// Internal accumulator for a single tool_use during streaming.
class _PendingToolUse {

  _PendingToolUse({required this.id, required this.name});
  final String id;
  final String name;
  final List<String> inputFragments = [];

  Map<String, dynamic>? get parsedInput {
    if (inputFragments.isEmpty) return null;
    final raw = inputFragments.join();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }
}
