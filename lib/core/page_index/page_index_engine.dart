/// PageIndex 核心引擎
///
/// 三模式自动降级建树 + 验证修正 + 大节点拆分:
/// 1. TOC + 页码 → LLM 提取映射 → 验证 → 修正
/// 2. TOC 无页码 → LLM 逐段定位 → 验证
/// 3. 无 TOC → 标题树（零 LLM）
library;

import '../api/minimax_client.dart';
import 'models.dart';
import 'page_index_utils.dart';

typedef ProgressCallback = void Function(String message);

class PageIndexEngine {

  PageIndexEngine(this._client);
  final MinimaxClient _client;

  // ─── 公开 API ───

  Future<BuildResult> build({
    required String docId,
    required String docName,
    required String markdownContent,
    required String docType,
    int? realPageCount,
    bool generateSummaries = false,
    bool generateDescription = false,
    ProgressCallback? onProgress,
  }) async {
    onProgress?.call('解析文档...');
    final lines = markdownContent.split('\n');
    final totalLines = lines.length;
    final mdNodes = _extractMarkdownNodes(lines);

    if (mdNodes.isEmpty) {
      onProgress?.call('无标题结构，作为单节点...');
      return _singleNodeResult(docId, docName, docType, totalLines, realPageCount);
    }

    double accuracy = 0.9; // 默认标题树准确率
    TocInfo? tocInfo;

    // ── 模式 1: TOC + 页码映射 ──
    if (realPageCount != null && mdNodes.length >= 3) {
      onProgress?.call('检测目录...');
      tocInfo = await _tryDetectToc(markdownContent, realPageCount);
      if (tocInfo != null) {
        // 验证 TOC 映射
        final verifyResult = await _verifyTocMapping(tocInfo, markdownContent, realPageCount);
        accuracy = verifyResult;
        if (accuracy < 0.6) {
          onProgress?.call('TOC 页码映射准确率不足 (${(accuracy*100).toInt()}%)，降级...');
          tocInfo = null; // 降级到模式 2
        } else if (accuracy < 1.0) {
          onProgress?.call('修正不准确的 TOC 映射...');
          tocInfo = await _correctTocMapping(tocInfo, markdownContent, realPageCount);
        }
      }
    }

    // ── 模式 2: TOC 无页码，LLM 定位 ──
    if (tocInfo == null && mdNodes.length >= 3 && realPageCount != null) {
      onProgress?.call('尝试 LLM 定位章节...');
      final result = await _llmLocateSections(mdNodes, markdownContent, realPageCount);
      if (result != null) {
        tocInfo = result;
        accuracy = 0.75; // LLM 定位中等可信度
      }
    }

    // ── 模式 3: 纯标题树 ──
    onProgress?.call('构建目录树...');
    var structure = _buildTreeFromMdNodes(mdNodes, totalLines);

    // 大节点递归拆分
    structure = await _subdivideLargeNodes(structure, markdownContent, realPageCount ?? totalLines, onProgress);

    // 摘要（在 TOC 映射前）
    if (generateSummaries) {
      onProgress?.call('生成摘要...');
      await _generateSummaries(structure, markdownContent, onProgress);
    }

    // 应用 TOC 页码映射
    if (tocInfo != null) {
      structure = _applyTocPageMapping(structure, tocInfo);
    }

    // 分配 node_id
    final flatNodes = flattenTree(structure);
    for (var i = 0; i < flatNodes.length; i++) {
      flatNodes[i].nodeId = i.toString().padLeft(4, '0');
    }

    String? docDescription;
    if (generateDescription) {
      docDescription = await _generateDocDescription(structure);
    }

    return BuildResult(
      docId: docId, docName: docName, docDescription: docDescription,
      docType: docType, pageCount: realPageCount, lineCount: totalLines,
      structure: structure, createdAt: DateTime.now(), accuracy: accuracy,
    );
  }

  // ─── 模式 1: TOC 检测 ───

  Future<TocInfo?> _tryDetectToc(String content, int realPageCount) async {
    final lines = content.split('\n');
    final checkLines = (lines.length * 0.3).ceil().clamp(0, lines.length);
    var head = lines.take(checkLines).join('\n');
    if (head.length > 12000) head = '${head.substring(0, 12000)}...';

    try {
      final hasTocRaw = await _client.chatCollect(
        '检测以下文本开头是否包含目录（列出章节标题和对应页码）。\n'
        '回复 JSON: {"has_toc": true/false, "toc_start_line": 数字, "toc_end_line": 数字}\n$head',
        temperature: 0.0, maxTokens: 512, thinkingBudgetTokens: 0,
        toolChoice: {'type': 'none'},
      );
      final tocJson = extractJson(hasTocRaw);
      if (tocJson['has_toc'] != true) return null;

      final s = ((tocJson['toc_start_line'] as int?) ?? 1) - 1;
      final e = ((tocJson['toc_end_line'] as int?) ?? checkLines) - 1;
      final tocContent = lines.sublist(s.clamp(0, lines.length), (e + 1).clamp(0, lines.length)).join('\n');

      final raw = await _client.chatCollect(
        '从以下目录提取章节→页码映射:\n$tocContent\n\n'
        '回复 JSON 数组: [{"title": "章节名", "page": 整数}, ...]',
        temperature: 0.0, maxTokens: 4096, thinkingBudgetTokens: 0,
        toolChoice: {'type': 'none'},
      );
      final list = extractJsonArray(raw);
      if (list.isEmpty) return null;

      final mappings = <String, int>{};
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        final t = m['title'] as String? ?? '';
        final p = m['page'] as int?;
        if (t.isNotEmpty && p != null && p > 0 && p <= realPageCount) mappings[t] = p;
      }
      return mappings.isNotEmpty ? TocInfo(mappings: mappings, totalPages: realPageCount) : null;
    } catch (_) {
      return null;
    }
  }

  // ─── 验证 TOC 映射 ───

  Future<double> _verifyTocMapping(TocInfo tocInfo, String content, int totalPages) async {
    final entries = tocInfo.mappings.entries.toList();
    final sampleSize = (entries.length < 5 ? entries.length : 5).clamp(1, entries.length);
    entries.shuffle();
    final samples = entries.take(sampleSize).toList();

    int correct = 0;
    for (final entry in samples) {
      try {
        final raw = await _client.chatCollect(
          '文档共 $totalPages 页。章节"${entry.key}"是否在第 ${entry.value} 页附近（±2 页内）？\n'
          '回复 JSON: {"match": true/false}',
          temperature: 0.0, maxTokens: 128, thinkingBudgetTokens: 0,
          toolChoice: {'type': 'none'},
        );
        if (extractJson(raw)['match'] == true) correct++;
      } catch (_) {
        correct++; // 无法判断时给 benefit of doubt
      }
    }
    return correct / samples.length;
  }

  // ─── 修正 TOC 映射 ───

  Future<TocInfo> _correctTocMapping(TocInfo tocInfo, String content, int totalPages) async {
    // 找出页码看起来不合理的条目并调整
    final corrected = Map<String, int>.from(tocInfo.mappings);
    final sorted = corrected.entries.toList()..sort((a, b) => a.value.compareTo(b.value));

    for (int i = 0; i < sorted.length; i++) {
      // 检查是否与前一个条目有 > 50 页的跳跃
      if (i > 0 && sorted[i].value - sorted[i - 1].value > 50) {
        try {
          final raw = await _client.chatCollect(
            '章节"${sorted[i].key}"的当前页码是 ${sorted[i].value}，但前一个章节"${sorted[i-1].key}"在第 ${sorted[i-1].value} 页。'
            '这两章之间不太可能间隔 ${sorted[i].value - sorted[i-1].value} 页。'
            '请给出"${sorted[i].key}"更合理的页码。总页数 $totalPages。\n'
            '回复 JSON: {"page": 整数}',
            temperature: 0.0, maxTokens: 128, thinkingBudgetTokens: 0,
            toolChoice: {'type': 'none'},
          );
          final newPage = extractJson(raw)['page'] as int?;
          if (newPage != null && newPage > 0 && newPage <= totalPages) {
            corrected[sorted[i].key] = newPage;
          }
        } catch (_) {}
      }
    }
    return TocInfo(mappings: corrected, totalPages: totalPages);
  }

  // ─── 模式 2: LLM 定位章节 ───

  Future<TocInfo?> _llmLocateSections(
    List<_MdNode> mdNodes, String content, int totalPages,
  ) async {
    // 把文档分块，让 LLM 定位每个大章节所在的页范围
    final lines = content.split('\n');
    final topNodes = mdNodes.where((n) => n.level <= 2).toList();
    if (topNodes.length < 3) return null;

    try {
      final titles = topNodes.map((n) => n.title).join('\n');
      final raw = await _client.chatCollect(
        '文档共 $totalPages 页。以下是要定位的章节标题:\n$titles\n\n'
        '为每个章节估算它应该在第几页（1-$totalPages）。基于章节标题的语义判断，比如概述在前、附录在后。\n'
        '回复 JSON 数组: [{"title": "...", "page": 整数}, ...]',
        temperature: 0.0, maxTokens: 2048, thinkingBudgetTokens: 0,
        toolChoice: {'type': 'none'},
      );
      final list = extractJsonArray(raw);
      final mappings = <String, int>{};
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        final t = m['title'] as String? ?? '';
        final p = m['page'] as int?;
        if (t.isNotEmpty && p != null && p > 0 && p <= totalPages) mappings[t] = p;
      }
      return mappings.length >= 2 ? TocInfo(mappings: mappings, totalPages: totalPages) : null;
    } catch (_) {
      return null;
    }
  }

  // ─── 标题树构建 ───

  List<_MdNode> _extractMarkdownNodes(List<String> lines) {
    final nodes = <_MdNode>[];
    for (int i = 0; i < lines.length; i++) {
      final m = RegExp(r'^(#{1,6})\s+(.+)').firstMatch(lines[i]);
      if (m != null) nodes.add(_MdNode(level: m.group(1)!.length, title: m.group(2)!.trim(), lineNum: i + 1));
    }
    return nodes;
  }

  List<TreeNode> _buildTreeFromMdNodes(List<_MdNode> mdNodes, int totalLines) {
    if (mdNodes.isEmpty) return [];
    final items = <TocItem>[];
    final counters = <int>[];

    for (final node in mdNodes) {
      while (counters.length < node.level) {
        counters.add(1);
      }
      while (counters.length > node.level) {
        counters.removeLast();
      }

      final structure = counters.isEmpty ? '1'
          : List.generate(counters.length, (j) => counters[j].toString()).join('.');
      items.add(TocItem(structure: structure, title: node.title, physicalIndex: node.lineNum));

      if (counters.isNotEmpty) counters[counters.length - 1]++;
    }
    return postProcessing(items, totalLines);
  }

  // ─── 大节点递归拆分 ───

  Future<List<TreeNode>> _subdivideLargeNodes(
    List<TreeNode> nodes, String content, int totalSize, ProgressCallback? onProgress,
  ) async {
    final lines = content.split('\n');
    for (final node in nodes) {
      await _subdivideIfLarge(node, lines, totalSize, onProgress);
    }
    return nodes;
  }

  Future<void> _subdivideIfLarge(
    TreeNode node, List<String> lines, int totalSize, ProgressCallback? onProgress,
  ) async {
    final span = node.endIndex - node.startIndex + 1;
    final threshold = (totalSize * 0.15).ceil().clamp(15, 100);
    if (span <= threshold) return;

    // 递归处理子节点
    if (node.nodes != null) {
      for (final child in node.nodes!) {
        await _subdivideIfLarge(child, lines, totalSize, onProgress);
      }
      return;
    }

    // 叶子节点但太大了，尝试从内容中提取子标题
    onProgress?.call('拆分大节点: ${node.title} ($span 页)');
    final sectionText = lines
        .skip((node.startIndex - 1).clamp(0, lines.length))
        .take(span.clamp(0, lines.length)).join('\n');
    final subNodes = _extractMarkdownNodes(sectionText.split('\n'));

    if (subNodes.length >= 2) {
      node.nodes = _buildTreeFromMdNodes(
        subNodes.map((n) => _MdNode(
          level: n.level, title: n.title,
          lineNum: n.lineNum + node.startIndex - 1,
        )).toList(), node.endIndex);
    }
  }

  // ─── TOC 页码映射 ───

  List<TreeNode> _applyTocPageMapping(List<TreeNode> nodes, TocInfo tocInfo) {
    final flat = flattenTree(nodes);
    for (final node in flat) {
      final page = _fuzzyMatchTitle(node.title, tocInfo.mappings);
      if (page != null) node.startIndex = page;
    }
    final sorted = flat.toList()..sort((a, b) => a.startIndex.compareTo(b.startIndex));
    for (int i = 0; i < sorted.length; i++) {
      sorted[i].endIndex = i + 1 < sorted.length
          ? (sorted[i + 1].startIndex - 1).clamp(sorted[i].startIndex, tocInfo.totalPages)
          : tocInfo.totalPages;
    }
    return nodes;
  }

  int? _fuzzyMatchTitle(String title, Map<String, int> mappings) {
    if (mappings.containsKey(title)) return mappings[title];
    String norm(String s) => s
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[（(][^)）]*[)）]'), '')
        .replaceAll('：', ':').replaceAll('，', ',')
        .replaceAll('"', '"').replaceAll('"', '"')
        .replaceAll(RegExp(r'[第章节]'), '').toLowerCase();
    final nt = norm(title);
    for (final e in mappings.entries) {
      final nk = norm(e.key);
      if (nk == nt || nk.contains(nt) || nt.contains(nk)) return e.value;
    }
    return null;
  }

  // ─── 摘要 ───

  Future<void> _generateSummaries(List<TreeNode> structure, String fullMarkdown, [ProgressCallback? p]) async {
    final nodes = flattenTree(structure);
    final lines = fullMarkdown.split('\n');
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      p?.call('摘要 ${i + 1}/${nodes.length}');
      try {
        final text = lines
            .skip((node.startIndex - 1).clamp(0, lines.length))
            .take((node.endIndex - node.startIndex + 1).clamp(0, lines.length)).join('\n');
        final t = text.length > 6000 ? '${text.substring(0, 6000)}...' : text;
        if (t.trim().isEmpty) continue;
        node.summary = (await _client.chatCollect(
          '用一句话（≤30字）概括: "${node.title}"\n$t\n直接返回摘要。',
          temperature: 0.0, maxTokens: 256, thinkingBudgetTokens: 0,
          toolChoice: {'type': 'none'},
        )).trim();
      } catch (_) {}
    }
  }

  Future<String?> _generateDocDescription(List<TreeNode> structure) async {
    if (structure.isEmpty) return null;
    try {
      return (await _client.chatCollect(
        '根据章节标题生成 ≤30 字文档描述: ${structure.map((n) => n.title).take(5).join('、')}',
        temperature: 0.0, maxTokens: 256, thinkingBudgetTokens: 0,
        toolChoice: {'type': 'none'},
      )).trim();
    } catch (_) { return null; }
  }

  // ─── 兜底 ───

  BuildResult _singleNodeResult(String docId, String docName, String docType, int lines, int? pages) {
    return BuildResult(
      docId: docId, docName: docName, docType: docType,
      pageCount: pages, lineCount: lines,
      structure: [TreeNode(title: docName, nodeId: '0000', startIndex: 1, endIndex: pages ?? lines)],
      createdAt: DateTime.now(), accuracy: 0.5,
    );
  }
}

class _MdNode {
  const _MdNode({required this.level, required this.title, required this.lineNum}); final int level; final String title; final int lineNum; }
class TocInfo {
  const TocInfo({required this.mappings, required this.totalPages}); final Map<String, int> mappings; final int totalPages; }
