import 'dart:convert';
import '../../../core/storage/database_helper.dart';
import '../domain/image_history_item.dart';

class ImageHistoryRepository {

  ImageHistoryRepository({DatabaseHelper? db})
      : _db = db ?? DatabaseHelper();
  final DatabaseHelper _db;

  Future<List<ImageHistoryItem>> getHistory({int limit = 50}) async {
    final rows = await _db.getImageHistory(limit: limit);
    return rows.map((m) => ImageHistoryItem.fromMap(m)).toList();
  }

  Future<void> addToHistory({
    required String prompt,
    required String model,
    required List<String> images, String? ratio,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final imagesJson = jsonEncode(images);
    await _db.insertImageHistory(
      id: id,
      prompt: prompt,
      model: model,
      ratio: ratio,
      imagesJson: imagesJson,
    );
  }

  Future<void> deleteFromHistory(String id) async {
    await _db.deleteImageHistory(id);
  }
}
