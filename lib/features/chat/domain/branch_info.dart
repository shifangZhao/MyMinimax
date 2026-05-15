import 'package:equatable/equatable.dart';

class BranchInfo extends Equatable {

  const BranchInfo({
    required this.id,
    required this.conversationId,
    required this.forkMessageId, required this.createdAt, this.parentBranchId,
    this.name,
    this.isActive = false,
    this.messageCount = 0,
  });
  final String id;
  final String conversationId;
  final String? parentBranchId;
  final String forkMessageId;
  final String? name;
  final DateTime createdAt;
  final bool isActive;
  final int messageCount;

  BranchInfo copyWith({
    String? id,
    String? conversationId,
    String? parentBranchId,
    String? forkMessageId,
    String? name,
    DateTime? createdAt,
    bool? isActive,
    int? messageCount,
  }) {
    return BranchInfo(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      parentBranchId: parentBranchId ?? this.parentBranchId,
      forkMessageId: forkMessageId ?? this.forkMessageId,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
      messageCount: messageCount ?? this.messageCount,
    );
  }

  @override
  List<Object?> get props => [id, conversationId, parentBranchId, forkMessageId, name, createdAt, isActive, messageCount];
}
