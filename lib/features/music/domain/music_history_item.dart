class MusicHistoryItem {

  const MusicHistoryItem({
    required this.id,
    required this.prompt,
    required this.model, required this.localPath, required this.isInstrumental, required this.createdAt, this.lyrics,
    this.duration,
    this.bitrate,
  });

  factory MusicHistoryItem.fromMap(Map<String, dynamic> map) {
    return MusicHistoryItem(
      id: map['id'] as String,
      prompt: map['prompt'] as String,
      lyrics: map['lyrics'] as String?,
      model: map['model'] as String,
      localPath: map['local_path'] as String,
      duration: map['duration'] as int?,
      bitrate: map['bitrate'] as int?,
      isInstrumental: (map['is_instrumental'] as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
  final String id;
  final String prompt;
  final String? lyrics;
  final String model;
  final String localPath;
  final int? duration;
  final int? bitrate;
  final bool isInstrumental;
  final DateTime createdAt;

  String get formattedDuration {
    if (duration == null) return '';
    final totalSec = duration!;
    // API返回的可能为秒或毫秒，超过100000秒（超过27小时）说明是毫秒
    final totalMin = totalSec > 100000 ? totalSec / 60000.0 : totalSec / 60.0;
    if (totalMin < 1) return '${totalSec}s';
    if (totalMin >= 10) return '${totalMin.round()}分钟';
    return '${totalMin.toStringAsFixed(1)}分钟';
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
