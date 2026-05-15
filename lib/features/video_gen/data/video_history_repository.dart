import '../../../core/storage/database_helper.dart';
import '../domain/video_history_item.dart';

class VideoHistoryRepository {

  VideoHistoryRepository({DatabaseHelper? db})
      : _db = db ?? DatabaseHelper();
  final DatabaseHelper _db;

  Future<List<VideoHistoryItem>> getHistory({int limit = 50}) async {
    final rows = await _db.getVideoHistory(limit: limit);
    return rows.map((m) => VideoHistoryItem.fromMap(m)).toList();
  }

  Future<void> addToHistory({
    required String prompt,
    required String model,
    int? duration,
    String? resolution,
    String? videoUrl,
    String? thumbnailUrl,
    String? templateId,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await _db.insertVideoHistory(
      id: id,
      prompt: prompt,
      model: model,
      duration: duration,
      resolution: resolution,
      videoUrl: videoUrl,
      thumbnailUrl: thumbnailUrl,
      templateId: templateId,
    );
  }

  Future<void> deleteFromHistory(String id) async {
    await _db.deleteVideoHistory(id);
  }
}
