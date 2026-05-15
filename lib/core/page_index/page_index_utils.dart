/// PageIndex 工具函数
///
/// 纯 Dart 工具，无需 LLM 调用。对应 Python 版 utils.py 中的工具函数。
library;

import 'dart:convert';
import 'models.dart';

/// 从 LLM 回复中提取 JSON 对象
///
/// 对应 Python 版 extract_json() (utils.py:99-131)
Map<String, dynamic> extractJson(String raw) {
  if (raw.isEmpty) return {};

  var content = raw;

  // 提取 ```json ... ``` 块
  final startIdx = content.indexOf('```json');
  if (startIdx != -1) {
    content = content.substring(startIdx + 7);
    final endIdx = content.lastIndexOf('```');
    if (endIdx != -1) {
      content = content.substring(0, endIdx);
    }
  } else {
    // 尝试直接找 JSON 起止
    final braceStart = content.indexOf('{');
    final braceEnd = content.lastIndexOf('}');
    final bracketStart = content.indexOf('[');
    final bracketEnd = content.lastIndexOf(']');

    if (braceStart != -1 && braceEnd > braceStart) {
      content = content.substring(braceStart, braceEnd + 1);
    } else if (bracketStart != -1 && bracketEnd > bracketStart) {
      content = content.substring(bracketStart, bracketEnd + 1);
    }
  }

  content = content
      .replaceAll('None', 'null')
      .replaceAll('\n', ' ')
      .replaceAll('\r', ' ');

  // 规范化空白
  content = content.replaceAll(RegExp(r'\s+'), ' ').trim();

  try {
    return jsonDecode(content) as Map<String, dynamic>;
  } catch (_) {
    try {
      // 清理尾部逗号
      content = content.replaceAll(',]', ']').replaceAll(',}', '}');
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}

/// 从 LLM 回复中提取 JSON 数组
List<dynamic> extractJsonArray(String raw) {
  if (raw.isEmpty) return [];

  var content = raw;

  final startIdx = content.indexOf('```json');
  if (startIdx != -1) {
    content = content.substring(startIdx + 7);
    final endIdx = content.lastIndexOf('```');
    if (endIdx != -1) content = content.substring(0, endIdx);
  } else {
    final bracketStart = content.indexOf('[');
    final bracketEnd = content.lastIndexOf(']');
    if (bracketStart != -1 && bracketEnd > bracketStart) {
      content = content.substring(bracketStart, bracketEnd + 1);
    }
  }

  content = content
      .replaceAll('None', 'null')
      .replaceAll('\n', ' ')
      .replaceAll('\r', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  try {
    return jsonDecode(content) as List<dynamic>;
  } catch (_) {
    try {
      content = content.replaceAll(',]', ']').replaceAll(',}', '}');
      return jsonDecode(content) as List<dynamic>;
    } catch (_) {
      return [];
    }
  }
}

/// 粗略 token 估算 (chars / 4)
///
/// 对应 Python 版 count_tokens() 使用 litellm token_counter。
/// 移动端无等价库，使用 char/4 近似。
int countTokens(String text) {
  if (text.isEmpty) return 0;
  return (text.length / 4).ceil();
}

/// 展平目录列表转嵌套树
///
/// 对应 Python 版 list_to_tree() (utils.py:324-370)
List<TreeNode> listToTree(List<TocItem> flatList) {
  if (flatList.isEmpty) return [];

  final nodes = <String, TreeNode>{};
  final rootNodes = <TreeNode>[];

  for (final item in flatList) {
    final structure = item.structure ?? '';
    final node = TreeNode(
      title: item.title,
      startIndex: item.physicalIndex ?? 0,
      endIndex: item.physicalIndex ?? 0,
    );
    nodes[structure] = node;

    final parent = _findNearestAncestor(structure, nodes);
    if (parent != null) {
      parent.nodes ??= [];
      parent.nodes!.add(node);
    } else {
      rootNodes.add(node);
    }
  }

  return rootNodes.map((n) => _cleanNode(n)).toList();
}

/// 找最近存在的祖先（处理跳级标题：H1→H3 时 H3 挂在 H1 下）
TreeNode? _findNearestAncestor(String structure, Map<String, TreeNode> nodes) {
  final parts = structure.split('.');
  for (int i = parts.length - 1; i > 0; i--) {
    final ancestor = parts.sublist(0, i).join('.');
    if (nodes.containsKey(ancestor)) return nodes[ancestor];
  }
  return null;
}

TreeNode _cleanNode(TreeNode node) {
  if (node.nodes == null || node.nodes!.isEmpty) {
    node.nodes = null;
  } else {
    node.nodes = node.nodes!.map((n) => _cleanNode(n)).toList();
  }
  return node;
}

/// 后续处理：将展平列表转为带 start_index/end_index 的树
///
/// 对应 Python 版 post_processing() (utils.py:433-452)
List<TreeNode> postProcessing(List<TocItem> flatList, int endPhysicalIndex) {
  if (flatList.isEmpty) return [];

  for (int i = 0; i < flatList.length; i++) {
    flatList[i].physicalIndex ??= 0;
    if (i < flatList.length - 1) {
      final nextIdx = flatList[i + 1].physicalIndex ?? 0;
      if (flatList[i + 1].appearStart == 'yes') {
        flatList[i].physicalIndex = nextIdx - 1;
      } else {
        flatList[i].physicalIndex = nextIdx;
      }
    } else {
      flatList[i].physicalIndex = endPhysicalIndex;
    }
  }

  return listToTree(flatList);
}

/// 为树节点分配 node_id
///
/// 对应 Python 版 write_node_id() (utils.py:132-142)
int writeNodeId(dynamic structure, [int startId = 0]) {
  int nodeId = startId;
  if (structure is Map<String, dynamic>) {
    structure['node_id'] = nodeId.toString().padLeft(4, '0');
    nodeId++;
    for (final key in structure.keys) {
      if (key == 'nodes') {
        nodeId = writeNodeId(structure[key], nodeId);
      }
    }
  } else if (structure is List) {
    for (final item in structure) {
      nodeId = writeNodeId(item, nodeId);
    }
  }
  return nodeId;
}

/// 移除字段
///
/// 对应 Python 版 remove_fields() (utils.py:466-472)
dynamic removeFields(dynamic data, List<String> keys) {
  if (data is Map<String, dynamic>) {
    final result = <String, dynamic>{};
    for (final entry in data.entries) {
      if (!keys.contains(entry.key)) {
        result[entry.key] = removeFields(entry.value, keys);
      }
    }
    return result;
  } else if (data is List) {
    return data.map((item) => removeFields(item, keys)).toList();
  }
  return data;
}

/// 获取树中所有节点的展平列表
List<TreeNode> flattenTree(List<TreeNode> nodes) {
  final result = <TreeNode>[];
  for (final node in nodes) {
    result.add(node);
    if (node.nodes != null) {
      result.addAll(flattenTree(node.nodes!));
    }
  }
  return result;
}

/// 解析页码范围字符串
///
/// 支持 "5"、"5-10"、"3,8,12" 三种格式
List<int> parsePages(String pages) {
  final result = <int>[];
  for (final part in pages.split(',')) {
    final trimmed = part.trim();
    if (trimmed.contains('-')) {
      final range = trimmed.split('-');
      final start = int.tryParse(range[0].trim()) ?? 0;
      final end = int.tryParse(range[1].trim()) ?? 0;
      if (start > 0 && end >= start) {
        for (var i = start; i <= end; i++) {
          result.add(i);
        }
      }
    } else {
      final page = int.tryParse(trimmed);
      if (page != null && page > 0) result.add(page);
    }
  }
  return result.toSet().toList()..sort();
}

/// 解析物理页码值（int、字符串或标记格式 "<physical_index_N>"）
int? parsePhysicalIndex(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is String) {
    final m = RegExp(r'physical_index_(\d+)').firstMatch(v);
    if (m != null) return int.tryParse(m.group(1)!);
    return int.tryParse(v);
  }
  return null;
}
