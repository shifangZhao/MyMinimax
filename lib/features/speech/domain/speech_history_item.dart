class SpeechHistoryItem {

  const SpeechHistoryItem({
    required this.id,
    required this.text,
    required this.voiceId,
    required this.voiceName,
    required this.model,
    required this.speed,
    required this.audioUrl,
    required this.createdAt,
  });

  factory SpeechHistoryItem.fromMap(Map<String, dynamic> map) {
    return SpeechHistoryItem(
      id: map['id'] as String,
      text: map['text'] as String,
      voiceId: map['voice_id'] as String,
      voiceName: map['voice_name'] as String? ?? '',
      model: map['model'] as String,
      speed: (map['speed'] as num).toDouble(),
      audioUrl: map['audio_url'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
  final String id;
  final String text;
  final String voiceId;
  final String voiceName;
  final String model;
  final double speed;
  final String audioUrl;
  final DateTime createdAt;

  String get shortText {
    if (text.length <= 30) return text;
    return '${text.substring(0, 30)}...';
  }

  String get formattedDate {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${createdAt.month}/${createdAt.day}';
  }
}
