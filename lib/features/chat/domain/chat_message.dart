import 'package:equatable/equatable.dart';

enum MessageRole { user, assistant, system, tool }

enum StreamState { idle, streaming, paused, resumed, completed, failed }

class ChatMessage extends Equatable {

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.imageBase64,
    this.fileName,
    this.thinking,
    this.fileType,
    this.mimeType,
    this.fileSize,
    this.extractedText,
    this.isTruncated = false,
    this.partialContent,
    this.tokenOffset = 0,
    this.contentHash,
    this.messageVersion = 1,
    this.dependsOn,
    this.streamState = 'completed',
    this.toolCall,
    this.toolInput,
    this.toolImageUrl,
  });
  final String id;
  final String conversationId;
  final MessageRole role;
  final String content;
  final DateTime createdAt;
  final String? imageBase64;
  final String? fileName;
  final String? thinking;
  final String? fileType;
  final String? mimeType;
  final int? fileSize;
  final String? extractedText;

  // 断点恢复新增字段
  final bool isTruncated;
  final String? partialContent;
  final int tokenOffset;
  final String? contentHash;
  final int messageVersion;
  final String? dependsOn;
  final String streamState;

  // 工具调用相关
  final String? toolCall;
  final String? toolInput;
  final String? toolImageUrl;  // 工具返回的图片 URL

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;
  bool get isTool => role == MessageRole.tool;
  bool get hasImage => imageBase64 != null && imageBase64!.isNotEmpty;
  bool get hasFile => fileName != null;
  bool get hasToolImage => toolImageUrl != null && toolImageUrl!.isNotEmpty;
  bool get hasThinking => thinking != null && thinking!.isNotEmpty;
  bool get isTruncatedMessage => isTruncated || streamState == 'paused' || streamState == 'failed';

  ChatMessage copyWith({
    String? id,
    String? conversationId,
    MessageRole? role,
    String? content,
    DateTime? createdAt,
    String? imageBase64,
    String? fileName,
    String? thinking,
    String? fileType,
    String? mimeType,
    int? fileSize,
    String? extractedText,
    bool? isTruncated,
    String? partialContent,
    int? tokenOffset,
    String? contentHash,
    int? messageVersion,
    String? dependsOn,
    String? streamState,
    String? toolCall,
    String? toolInput,
    String? toolImageUrl,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      imageBase64: imageBase64 ?? this.imageBase64,
      fileName: fileName ?? this.fileName,
      thinking: thinking ?? this.thinking,
      fileType: fileType ?? this.fileType,
      mimeType: mimeType ?? this.mimeType,
      fileSize: fileSize ?? this.fileSize,
      extractedText: extractedText ?? this.extractedText,
      isTruncated: isTruncated ?? this.isTruncated,
      partialContent: partialContent ?? this.partialContent,
      tokenOffset: tokenOffset ?? this.tokenOffset,
      contentHash: contentHash ?? this.contentHash,
      messageVersion: messageVersion ?? this.messageVersion,
      dependsOn: dependsOn ?? this.dependsOn,
      streamState: streamState ?? this.streamState,
      toolCall: toolCall ?? this.toolCall,
      toolInput: toolInput ?? this.toolInput,
      toolImageUrl: toolImageUrl ?? this.toolImageUrl,
    );
  }

  @override
  List<Object?> get props => [
        id,
        conversationId,
        role,
        content,
        createdAt,
        imageBase64,
        fileName,
        thinking,
        fileType,
        mimeType,
        fileSize,
        extractedText,
        isTruncated,
        partialContent,
        tokenOffset,
        contentHash,
        messageVersion,
        dependsOn,
        streamState,
        toolCall,
        toolInput,
      ];
}
