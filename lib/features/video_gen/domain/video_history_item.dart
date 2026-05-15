class VideoHistoryItem {

  const VideoHistoryItem({
    required this.id,
    required this.prompt,
    required this.model,
    required this.createdAt, this.duration,
    this.resolution,
    this.videoUrl,
    this.thumbnailUrl,
    this.templateId,
  });

  factory VideoHistoryItem.fromMap(Map<String, dynamic> map) {
    final createdRaw = map['created_at'];
    final DateTime createdAt;
    if (createdRaw is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(createdRaw);
    } else if (createdRaw is String) {
      createdAt = DateTime.tryParse(createdRaw) ?? DateTime.now();
    } else {
      createdAt = DateTime.now();
    }

    return VideoHistoryItem(
      id: (map['id'] as String?) ?? '',
      prompt: (map['prompt'] as String?) ?? '',
      model: (map['model'] as String?) ?? '',
      duration: map['duration'] as int?,
      resolution: map['resolution'] as String?,
      videoUrl: map['video_url'] as String?,
      thumbnailUrl: map['thumbnail_url'] as String?,
      templateId: map['template_id'] as String?,
      createdAt: createdAt,
    );
  }
  final String id;
  final String prompt;
  final String model;
  final int? duration;
  final String? resolution;
  final String? videoUrl;
  final String? thumbnailUrl;
  final String? templateId;
  final DateTime createdAt;

  /// duration 单位为秒
  String get formattedDuration {
    if (duration == null) return '';
    final seconds = duration!;
    if (seconds < 60) return '$seconds秒';
    if (seconds % 60 == 0) return '${seconds ~/ 60}分钟';
    return '${seconds ~/ 60}分${seconds % 60}秒';
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
