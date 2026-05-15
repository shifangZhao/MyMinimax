import 'package:equatable/equatable.dart';

class ChatConversation extends Equatable {

  const ChatConversation({
    required this.id,
    required this.title,
    required this.createdAt, required this.updatedAt, this.summary,
  });
  final String id;
  final String title;
  final String? summary;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatConversation copyWith({
    String? id,
    String? title,
    String? summary,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatConversation(
      id: id ?? this.id,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, title, summary, createdAt, updatedAt];
}
