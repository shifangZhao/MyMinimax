/// MemoryEmbedder — 本地 + API 混合语义嵌入。
///
/// 1. 优先使用 API 嵌入（MiniMax embo-01，1536 维）
/// 2. 嵌入结果缓存到 SQLite，避免重复 API 调用
/// 3. 提供余弦相似度计算
library;

import 'dart:typed_data';
import 'dart:math' as math;
import 'package:sqflite/sqflite.dart';
import '../../../core/api/minimax_client.dart';
import '../../../core/storage/database_helper.dart';

class MemoryEmbedder {

  MemoryEmbedder({
    required MinimaxClient client,
    DatabaseHelper? db,
  })  : _client = client,
        _db = db ?? DatabaseHelper();

  final MinimaxClient _client;
  final DatabaseHelper _db;

  /// 对文本生成 embedding（先查缓存，没有再调 API）。
  Future<List<double>> embed(String text, {String type = 'query'}) async {
    // 1. 查本地缓存
    final cached = await _getCachedEmbedding(text);
    if (cached != null) return cached;

    // 2. 调 API
    final vector = await _client.embed(text, type: type);

    // 3. 缓存到 DB（仅 type=db 时缓存，query 是临时搜索不用存）
    if (type == 'db') {
      await _cacheEmbedding(text, vector);
    }

    return vector;
  }

  /// 批量嵌入并缓存。
  Future<Map<String, List<double>>> embedBatch(
    List<String> texts, {
    String type = 'db',
  }) async {
    final result = <String, List<double>>{};
    final uncached = <String>[];

    // 1. 批量查缓存
    for (final text in texts) {
      final cached = await _getCachedEmbedding(text);
      if (cached != null) {
        result[text] = cached;
      } else {
        uncached.add(text);
      }
    }
    if (uncached.isEmpty) return result;

    // 2. 批量调 API（每次最多 10 条）
    for (var i = 0; i < uncached.length; i += 10) {
      final batch = uncached.sublist(i, (i + 10).clamp(0, uncached.length));
      final vectors = await _client.embedBatch(batch, type: type);
      for (var j = 0; j < batch.length; j++) {
        result[batch[j]] = vectors[j];
        if (type == 'db') {
          await _cacheEmbedding(batch[j], vectors[j]);
        }
      }
    }

    return result;
  }

  /// 余弦相似度。
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0, na = 0, nb = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    final denom = math.sqrt(na) * math.sqrt(nb);
    return denom == 0 ? 0.0 : dot / denom;
  }

  /// float32 列表 → Uint8List（存 DB）。
  static Uint8List vectorsToBytes(List<double> vectors) {
    final bytes = ByteData(vectors.length * 4);
    for (var i = 0; i < vectors.length; i++) {
      bytes.setFloat32(i * 4, vectors[i].toDouble(), Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  /// Uint8List → float32 列表（从 DB 读）。
  static List<double> bytesToVectors(Uint8List bytes) {
    final count = bytes.length ~/ 4;
    final result = List<double>.generate(count, (i) {
      return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length)
          .getFloat32(i * 4, Endian.little);
    });
    return result;
  }

  // ── 缓存层 ──

  Future<List<double>?> _getCachedEmbedding(String text) async {
    // 用 text 的 hash 作为 cache key，避免存整段文本到 DB
    final hash = _simpleHash(text);
    final db = await _db.database;
    final rows = await db.query('memory_embeddings',
        where: 'text_hash = ?', whereArgs: [hash], limit: 1);
    if (rows.isEmpty) return null;
    final blob = rows.first['embedding'] as Uint8List?;
    if (blob == null || blob.isEmpty) return null;
    return bytesToVectors(blob);
  }

  Future<void> _cacheEmbedding(String text, List<double> vector) async {
    final hash = _simpleHash(text);
    final db = await _db.database;
    await db.insert('memory_embeddings', {
      'text_hash': hash,
      'text_preview': text.length > 200 ? text.substring(0, 200) : text,
      'embedding': vectorsToBytes(vector),
      'source': 'api',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  String _simpleHash(String text) {
    final bytes = text.codeUnits;
    int h = 0;
    for (final b in bytes) {
      h = ((h << 5) - h) + b;
      h = h & h; // Convert to 32bit integer
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
