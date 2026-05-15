import '../../../core/storage/database_helper.dart';
import '../domain/speech_history_item.dart';

class SpeechHistoryRepository {

  SpeechHistoryRepository({DatabaseHelper? db})
      : _db = db ?? DatabaseHelper();
  final DatabaseHelper _db;

  Future<List<SpeechHistoryItem>> getHistory({int limit = 50}) async {
    final rows = await _db.getSpeechHistory(limit: limit);
    return rows.map((m) => SpeechHistoryItem.fromMap(m)).toList();
  }

  Future<void> addToHistory({
    required String text,
    required String voiceId,
    required String voiceName,
    required String model,
    required double speed,
    required String audioUrl,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await _db.insertSpeechHistory(
      id: id,
      text: text,
      voiceId: voiceId,
      voiceName: voiceName,
      model: model,
      speed: speed,
      audioUrl: audioUrl,
    );
  }

  Future<void> deleteFromHistory(String id) async {
    await _db.deleteSpeechHistory(id);
  }
}
