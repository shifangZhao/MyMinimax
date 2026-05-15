/// Provider-agnostic request / response models.
library;

import 'package:equatable/equatable.dart';

// ── Messages ──

/// Role for a chat message.
enum MessageRole { system, user, assistant, tool }

/// A single chat message in provider-agnostic format.
class Message extends Equatable { // for assistant tool_use

  const Message({
    required this.role,
    required this.content,
    this.toolUseId,
    this.toolName,
    this.toolInput,
  });

  factory Message.user(String content) =>
      Message(role: MessageRole.user, content: content);

  factory Message.system(String content) =>
      Message(role: MessageRole.system, content: content);

  factory Message.assistant(String content) =>
      Message(role: MessageRole.assistant, content: content);

  factory Message.toolResult({
    required String toolUseId,
    required String content,
  }) =>
      Message(
        role: MessageRole.tool,
        content: content,
        toolUseId: toolUseId,
      );

  factory Message.assistantToolUse({
    required String toolName,
    required String toolUseId,
    required Map<String, dynamic> input,
  }) =>
      Message(
        role: MessageRole.assistant,
        content: '',
        toolName: toolName,
        toolUseId: toolUseId,
        toolInput: input,
      );
  final MessageRole role;
  final String content;
  final String? toolUseId; // for tool_result
  final String? toolName; // for assistant tool_use
  final Map<String, dynamic>? toolInput;

  bool get isToolResult => role == MessageRole.tool;
  bool get isToolUse => role == MessageRole.assistant && toolName != null;

  @override
  List<Object?> get props => [role, content, toolUseId, toolName, toolInput];
}

// ── Content Blocks ──

/// Type discriminator for content blocks.
enum ContentBlockType { text, thinking, toolUse, toolResult }

/// A single content block within an assistant message.
class ContentBlock extends Equatable {

  const ContentBlock({
    required this.type,
    this.text,
    this.thinking,
    this.toolName,
    this.toolUseId,
    this.toolInput,
  });

  factory ContentBlock.text(String text) => ContentBlock(
        type: ContentBlockType.text,
        text: text,
      );

  factory ContentBlock.thinking(String thinking) => ContentBlock(
        type: ContentBlockType.thinking,
        thinking: thinking,
      );

  factory ContentBlock.toolUse({
    required String name,
    required String id,
    required Map<String, dynamic> input,
  }) =>
      ContentBlock(
        type: ContentBlockType.toolUse,
        toolName: name,
        toolUseId: id,
        toolInput: input,
      );

  factory ContentBlock.toolResult({
    required String toolUseId,
    required String content,
  }) =>
      ContentBlock(
        type: ContentBlockType.toolResult,
        toolUseId: toolUseId,
        text: content,
      );
  final ContentBlockType type;
  final String? text;
  final String? thinking;
  final String? toolName;
  final String? toolUseId;
  final Map<String, dynamic>? toolInput;

  @override
  List<Object?> get props => [type, text, thinking, toolName, toolUseId, toolInput];
}

// ── Tool Call Block (returned from Provider) ──

/// A tool call extracted from a provider response.
class ToolCallBlock extends Equatable {

  const ToolCallBlock({
    required this.id,
    required this.name,
    required this.input,
  });
  final String id;
  final String name;
  final Map<String, dynamic> input;

  @override
  List<Object?> get props => [id, name, input];
}

// ── Request ──

/// Unified completion request, provider-agnostic.
class CompletionRequest extends Equatable {

  const CompletionRequest({
    required this.messages,
    this.systemPrompt,
    this.toolChoice,
    this.temperature = 1.0,
    this.topP = 0.95,
    this.maxTokens = 16384,
    this.thinkingBudgetTokens = 0,
  });
  final List<Message> messages;
  final dynamic systemPrompt; // String or List<Map> (with cache_control)
  final Map<String, dynamic>? toolChoice;
  final double temperature;
  final double topP;
  final int maxTokens;
  final int thinkingBudgetTokens;

  @override
  List<Object?> get props =>
      [messages, systemPrompt, toolChoice, temperature, topP, maxTokens, thinkingBudgetTokens];
}

// ── Response ──

/// Unified completion response, provider-agnostic.
class ProviderResponse extends Equatable {

  const ProviderResponse({
    this.text,
    this.contentBlocks = const [],
    this.toolCalls = const [],
    this.stopReason,
    this.model,
  });
  final String? text;
  final List<ContentBlock> contentBlocks;
  final List<ToolCallBlock> toolCalls;
  final String? stopReason;
  final String? model;

  bool get hasToolCalls => toolCalls.isNotEmpty;

  ToolCallBlock? get firstToolCall =>
      toolCalls.isNotEmpty ? toolCalls.first : null;

  @override
  List<Object?> get props => [text, contentBlocks, toolCalls, stopReason, model];
}

// ── Streaming Events ──

/// Event types during streaming completion.
enum StreamEventType {
  textDelta,
  thinkingDelta,
  toolCallStart,
  toolCallDelta,
  toolCallEnd,
  done,
  error,
}

/// A streaming event from the provider.
class ProviderStreamEvent extends Equatable {

  const ProviderStreamEvent({
    required this.type,
    this.text,
    this.thinking,
    this.toolName,
    this.toolUseId,
    this.partialJson,
    this.error,
  });

  factory ProviderStreamEvent.textDelta(String text) => ProviderStreamEvent(
        type: StreamEventType.textDelta,
        text: text,
      );

  factory ProviderStreamEvent.thinkingDelta(String thinking) =>
      ProviderStreamEvent(
        type: StreamEventType.thinkingDelta,
        thinking: thinking,
      );

  factory ProviderStreamEvent.toolCallStart({
    required String name,
    required String id,
  }) =>
      ProviderStreamEvent(
        type: StreamEventType.toolCallStart,
        toolName: name,
        toolUseId: id,
      );

  factory ProviderStreamEvent.toolCallDelta(String partialJson) =>
      ProviderStreamEvent(
        type: StreamEventType.toolCallDelta,
        partialJson: partialJson,
      );

  factory ProviderStreamEvent.toolCallEnd({
    required String name,
    required String id,
    required Map<String, dynamic> input,
  }) =>
      ProviderStreamEvent(
        type: StreamEventType.toolCallEnd,
        toolName: name,
        toolUseId: id,
        partialJson: input.toString(),
      );

  factory ProviderStreamEvent.done() => const ProviderStreamEvent(
        type: StreamEventType.done,
      );

  factory ProviderStreamEvent.error(String message) => ProviderStreamEvent(
        type: StreamEventType.error,
        error: message,
      );
  final StreamEventType type;
  final String? text;
  final String? thinking;
  final String? toolName;
  final String? toolUseId;
  final String? partialJson;
  final String? error;

  @override
  List<Object?> get props =>
      [type, text, thinking, toolName, toolUseId, partialJson, error];
}
