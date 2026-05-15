import 'dart:convert';

class ImageHistoryItem {

  const ImageHistoryItem({
    required this.id,
    required this.prompt,
    required this.model,
    required this.images, required this.createdAt, this.ratio,
  });

  factory ImageHistoryItem.fromMap(Map<String, dynamic> map) {
    final imagesRaw = map['images'] as String;
    List<String> images;
    try {
      images = (jsonDecode(imagesRaw) as List).cast<String>();
    } catch (_) {
      images = <String>[];
    }
    return ImageHistoryItem(
      id: map['id'] as String,
      prompt: map['prompt'] as String,
      model: map['model'] as String,
      ratio: map['ratio'] as String?,
      images: images,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
  final String id;
  final String prompt;
  final String model;
  final String? ratio;
  final List<String> images;
  final DateTime createdAt;

  String get formattedDate {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${createdAt.month}/${createdAt.day}';
  }

  String get imageCountLabel => '${images.length}张';
}
