/// PageIndex 索引仓库
///
/// 封装 DatabaseHelper 中 page_index 表的 CRUD 操作。
/// 树结构以 JSON 序列化存储。
library;

import 'dart:convert';
import '../storage/database_helper.dart';
import 'models.dart';

class PageIndexRepository {

  PageIndexRepository({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();
  final DatabaseHelper _db;

  String _generateDocId(String docName) {
    var hash = 0;
    for (int i = 0; i < docName.length; i++) {
      hash = (hash * 31 + docName.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return hash.toRadixString(16);
  }

  /// 通过文档路径生成确定性的 docId
  String docIdFor(String path) => _generateDocId(path);

  /// 存储构建好的索引（INSERT OR REPLACE，原子操作）
  Future<void> saveIndex(BuildResult result, {String? contentHash}) async {
    await _db.insertPageIndex(
      docId: result.docId,
      docName: result.docName,
      docDescription: result.docDescription,
      docType: result.docType,
      pageCount: result.pageCount,
      lineCount: result.lineCount,
      structureJson: jsonEncode(result.structure.map((n) => n.toJson()).toList()),
      accuracy: result.accuracy,
      contentHash: contentHash,
    );
  }

  /// 搜索所有已索引文档中匹配关键词的章节
  Future<List<Map<String, dynamic>>> searchAcrossIndices(String query) async {
    final rows = await _db.listPageIndices();
    final results = <Map<String, dynamic>>[];
    final q = query.toLowerCase();

    for (final row in rows) {
      final structureJson = row['structure_json'] as String?;
      if (structureJson == null || structureJson.isEmpty) continue;

      try {
        final list = jsonDecode(structureJson) as List<dynamic>;
        final nodes = list.map((n) => TreeNode.fromJson(n as Map<String, dynamic>)).toList();
        _searchNodes(nodes, q, row['doc_name'] as String? ?? '', results);
      } catch (_) {}
    }
    return results;
  }

  void _searchNodes(List<TreeNode> nodes, String query, String docName, List<Map<String, dynamic>> out) {
    for (final node in nodes) {
      if (node.title.toLowerCase().contains(query) ||
          (node.summary?.toLowerCase().contains(query) ?? false)) {
        out.add({
          'doc': docName,
          'title': node.title,
          'node_id': node.nodeId,
          'start': node.startIndex,
          'end': node.endIndex,
          if (node.summary != null) 'summary': node.summary,
        });
      }
      if (node.nodes != null) _searchNodes(node.nodes!, query, docName, out);
    }
  }

  /// 通过文档路径获取已构建的索引
  Future<BuildResult?> getIndexByPath(String path) async {
    final docId = _generateDocId(path);
    return getIndex(docId);
  }

  /// 通过 docId 获取索引
  Future<BuildResult?> getIndex(String docId) async {
    final row = await _db.getPageIndex(docId);
    if (row == null) return null;

    final structureJson = row['structure_json'] as String?;
    if (structureJson == null || structureJson.isEmpty) return null;

    List<TreeNode> structure;
    try {
      final list = jsonDecode(structureJson) as List<dynamic>;
      structure = list
          .map((n) => TreeNode.fromJson(n as Map<String, dynamic>))
          .toList();
    } catch (_) {
      structure = [];
    }

    return BuildResult(
      docId: row['doc_id'] as String? ?? docId,
      docName: row['doc_name'] as String? ?? '',
      docDescription: row['doc_description'] as String?,
      docType: row['doc_type'] as String? ?? '',
      pageCount: row['page_count'] as int?,
      lineCount: row['line_count'] as int?,
      structure: structure,
      createdAt: row['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int)
          : DateTime.now(),
      accuracy: (row['accuracy'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// 列出所有已索引的文档
  Future<List<BuildResult>> listIndices() async {
    final rows = await _db.listPageIndices();
    return rows.map((row) {
      return BuildResult(
        docId: row['doc_id'] as String? ?? '',
        docName: row['doc_name'] as String? ?? '',
        docDescription: row['doc_description'] as String?,
        docType: row['doc_type'] as String? ?? '',
        pageCount: row['page_count'] as int?,
        lineCount: row['line_count'] as int?,
        structure: const [], // 列表时不含结构
        createdAt: row['created_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int)
            : DateTime.now(),
        accuracy: (row['accuracy'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();
  }

  /// 删除索引
  Future<void> deleteIndex(String docId) async {
    await _db.deletePageIndex(docId);
  }

  /// 通过文档路径删除索引
  Future<void> deleteIndexByPath(String path) async {
    await deleteIndex(_generateDocId(path));
  }
}
