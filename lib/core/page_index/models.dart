/// PageIndex 数据模型
library;

class TocItem {

  TocItem({
    required this.title, this.structure,
    this.physicalIndex,
    this.listIndex,
    this.appearStart,
  });

  factory TocItem.fromJson(Map<String, dynamic> json) => TocItem(
        structure: json['structure'] as String?,
        title: json['title'] as String? ?? '',
        physicalIndex: json['physical_index'] as int? ??
            _parsePhysicalIndex(json['physical_index']),
        listIndex: json['list_index'] as int?,
        appearStart: json['appear_start'] as String?,
      );
  final String? structure;
  final String title;
  int? physicalIndex;
  final int? listIndex;
  String? appearStart;

  Map<String, dynamic> toJson() => {
        if (structure != null) 'structure': structure,
        'title': title,
        if (physicalIndex != null) 'physical_index': physicalIndex,
        if (listIndex != null) 'list_index': listIndex,
        if (appearStart != null) 'appear_start': appearStart,
      };

  static int? _parsePhysicalIndex(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is String) {
      final m = RegExp(r'physical_index_(\d+)').firstMatch(v);
      if (m != null) return int.tryParse(m.group(1)!);
      return int.tryParse(v);
    }
    return null;
  }

}

class TreeNode {

  TreeNode({
    required this.title,
    required this.startIndex, required this.endIndex, this.nodeId,
    this.summary,
    this.text,
    this.nodes,
  });

  factory TreeNode.fromJson(Map<String, dynamic> json) => TreeNode(
        title: json['title'] as String? ?? '',
        nodeId: json['node_id'] as String?,
        startIndex: json['start_index'] as int? ?? 0,
        endIndex: json['end_index'] as int? ?? 0,
        summary: json['summary'] as String?,
        text: json['text'] as String?,
        nodes: (json['nodes'] as List<dynamic>?)
            ?.map((n) => TreeNode.fromJson(n as Map<String, dynamic>))
            .toList(),
      );
  final String title;
  String? nodeId;
  int startIndex;
  int endIndex;
  String? summary;
  String? text;
  List<TreeNode>? nodes;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'title': title,
      'start_index': startIndex,
      'end_index': endIndex,
    };
    if (nodeId != null) m['node_id'] = nodeId;
    if (summary != null) m['summary'] = summary;
    if (text != null) m['text'] = text;
    if (nodes != null && nodes!.isNotEmpty) {
      m['nodes'] = nodes!.map((n) => n.toJson()).toList();
    }
    return m;
  }

  bool get isLeaf => nodes == null || nodes!.isEmpty;
}

class BuildResult {

  const BuildResult({
    required this.docId,
    required this.docName,
    required this.docType, required this.structure, required this.createdAt, this.docDescription,
    this.pageCount,
    this.lineCount,
    this.accuracy = 0.0,
  });

  factory BuildResult.fromJson(Map<String, dynamic> json) => BuildResult(
        docId: json['doc_id'] as String? ?? '',
        docName: json['doc_name'] as String? ?? '',
        docDescription: json['doc_description'] as String?,
        docType: json['doc_type'] as String? ?? '',
        pageCount: json['page_count'] as int?,
        lineCount: json['line_count'] as int?,
        structure: (json['structure'] as List<dynamic>?)
                ?.map((n) => TreeNode.fromJson(n as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: json['created_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int)
            : DateTime.now(),
        accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
      );
  final String docId;
  final String docName;
  final String? docDescription;
  final String docType;
  final int? pageCount;
  final int? lineCount;
  final List<TreeNode> structure;
  final DateTime createdAt;
  final double accuracy;

  Map<String, dynamic> toJson() => {
        'doc_id': docId,
        'doc_name': docName,
        if (docDescription != null) 'doc_description': docDescription,
        'doc_type': docType,
        if (pageCount != null) 'page_count': pageCount,
        if (lineCount != null) 'line_count': lineCount,
        'structure': structure.map((n) => n.toJson()).toList(),
        'created_at': createdAt.millisecondsSinceEpoch,
        'accuracy': accuracy,
      };
}

