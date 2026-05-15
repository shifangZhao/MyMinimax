import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/storage/database_helper.dart';
import '../domain/music_history_item.dart';

class MusicHistoryRepository {

  MusicHistoryRepository({DatabaseHelper? db, Dio? dio})
      : _db = db ?? DatabaseHelper(),
        _dio = dio ?? Dio();
  final DatabaseHelper _db;
  final Dio _dio;

  Future<List<MusicHistoryItem>> getHistory() async {
    final rows = await _db.getMusicHistory();
    return rows.map((m) => MusicHistoryItem.fromMap(m)).toList();
  }

  /// Download audio and save to history.
  /// Returns the local file path.
  Future<String> addToHistory({
    required String audioUrl,
    required String prompt,
    required String model, required bool isInstrumental, String? lyrics,
    int? duration,
    int? bitrate,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final fileName = 'music_$id.mp3';
    final file = File('${dir.path}/$fileName');

    // Download audio
    final response = await _dio.get(
      audioUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    await file.writeAsBytes(response.data);

    await _db.insertMusicHistory(
      id: id,
      prompt: prompt,
      lyrics: lyrics,
      model: model,
      localPath: file.path,
      duration: duration,
      bitrate: bitrate,
      isInstrumental: isInstrumental,
    );

    return file.path;
  }

  Future<void> updatePrompt(String id, String prompt) async {
    await _db.updateMusicHistory(id, prompt: prompt);
  }

  Future<void> deleteFromHistory(String id, String localPath) async {
    await _db.deleteMusicHistory(id);
    try {
      await File(localPath).delete();
    } catch (_) {}
  }
}
