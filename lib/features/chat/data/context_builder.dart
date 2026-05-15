import '../domain/chat_message.dart';
import 'prompts/summary_lengths.dart';

class ContextBuilder {
  /// 构建系统提示词（不含摘要）
  static String buildSystemPrompt(String basePrompt) {
    return basePrompt;
  }

  /// 构建完整上下文
  static List<Map<String, String>> buildContext({
    required List<ChatMessage> messages,
    String? summary,
  }) {
    // Step 1: filter truncated / incomplete messages
    final filtered = messages.where((m) {
      if (m.isTruncated) return false;
      if (m.streamState == 'paused' || m.streamState == 'failed') return false;
      return true;
    }).toList();

    // Step 2: build context
    // system messages are UI-only (reconnection, etc.)
    // and must not leak into API history
    // tool messages: compacted and injected as user context so the model
    // remembers what happened in previous turns
    final result = <Map<String, String>>[];
    final toolSummaries = <String>[];
    for (final m in filtered) {
      if (m.role == MessageRole.system) continue;
      if (m.role == MessageRole.tool) {
        toolSummaries.add(_compactToolMessage(m.content));
        continue;
      }
      final stripped = _stripInternalMarkers(m.content);
      if (stripped.isNotEmpty) {
        result.add({'role': m.role.name, 'content': stripped});
      }
    }
    // Inject compacted tool call history as a user message at the end
    // so the model knows what happened in previous turns
    if (toolSummaries.isNotEmpty) {
      result.add({
        'role': 'user',
        'content': '【上一轮工具调用记录】\n${toolSummaries.join('\n')}',
      });
    }

    // Step 3: merge consecutive same-role messages (prevents API 400)
    final merged = <Map<String, String>>[];
    for (final m in result) {
      if (merged.isNotEmpty && merged.last['role'] == m['role']) {
        merged.last = {
          'role': m['role']!,
          'content': '${merged.last['content']}\n\n${m['content']}',
        };
      } else {
        merged.add(m);
      }
    }

    if (summary != null && summary.isNotEmpty) {
      return [
        {'role': 'system', 'content': '【对话历史摘要】以下是你和用户之前的对话要点，请基于这些背景继续交流：\n\n$summary'},
        ...merged,
      ];
    }
    return merged;
  }

  /// 压缩工具消息为一行摘要（保留工具名+成功/失败+首行结果）
  ///特殊情况：检测到图片时提取 base64 用于后续渲染显示
  static String _compactToolMessage(String content) {
    // 检测 markdown 图片格式：![静态地图](data:image/png;base64,...)
    final imgMatch = RegExp(r'!\[([^\]]*)\]\(data:image/([^;]+);base64,([^)]+)\)').firstMatch(content);
    if (imgMatch != null) {
      final label = imgMatch.group(1) ?? 'image';
      final mimeType = imgMatch.group(2) ?? 'png';
      final base64 = imgMatch.group(3) ?? '';
      return '![$label](data:image/$mimeType;base64,$base64)';
    }

    // 原压缩逻辑
    final firstLineEnd = content.indexOf('\n');
    final header = firstLineEnd > 0 ? content.substring(0, firstLineEnd) : content;
    // Extract first meaningful output line (skip empty lines)
    String? firstOutput;
    if (firstLineEnd > 0 && firstLineEnd + 1 < content.length) {
      final rest = content.substring(firstLineEnd + 1).trim();
      if (rest.isNotEmpty) {
        // Take first non-empty line, cap at 200 chars
        final lines = rest.split('\n').where((l) => l.trim().isNotEmpty);
        firstOutput = lines.isNotEmpty ? lines.first.trim() : null;
        if (firstOutput != null && firstOutput.length > 200) {
          firstOutput = '${firstOutput.substring(0, 200)}...';
        }
      }
    }
    if (firstOutput != null && firstOutput.isNotEmpty) {
      return '- $header → $firstOutput';
    }
    return '- $header';
  }

  /// 剥离遗留内部标记
  /// [SEARCH]/[ASK]/[TOOL_CALL] 已改为原生 tool_use，
  /// 此方法仅处理可能残留的标记（向后兼容）
  static String _stripInternalMarkers(String content) {
    if (content.isEmpty) return content;

    // 移除残留的标记块
    content = content.replaceAll(RegExp(r'\[TOOL_CALL\][\s\S]*?\[/TOOL_CALL\]', dotAll: true), '');
    content = content.replaceAll(RegExp(r'\[TOOL_RESULT\][\s\S]*?\[/TOOL_RESULT\]', dotAll: true), '');
    content = content.replaceAll(RegExp(r'\[SEARCH\].*'), '');
    content = content.replaceAll(RegExp(r'\[ASK\][\s\S]*?(?=\[|$)', caseSensitive: false), '');
    content = content.replaceAll(RegExp(r'\[OPEN_FOLDER\].*'), '');

    return content.trim();
  }

  /// 构建历史消息（兼容旧接口，但逻辑相同）
  static List<Map<String, String>> buildHistory(String summary, List<ChatMessage> recentMessages) {
    return buildContext(messages: recentMessages, summary: summary);
  }

  /// 简化版本 - 只有摘要时使用
  static List<Map<String, String>> buildHistoryWithSummary(String summary) {
    if (summary.isEmpty) return [];
    return [{'role': 'system', 'content': '【重要】以下是之前对话的完整摘要。你和用户已经聊过这些内容，你现在是在延续之前的对话，不是新会话。基于这些已有上下文自然地继续交流，不要表现得像第一次见面，不要重复询问已经讨论过的话题。\n\n$summary'}];
  }

  /// 提取需要摘要的对话内容并生成结构化摘要提示
  /// [messages] - 所有历史消息
  /// [lastSummaryPosition] - 上次摘要到了哪条消息的位置
  /// [length] - 摘要长度级别（默认 medium）
  static String extractForSummarization({
    required List<ChatMessage> messages,
    required int lastSummaryPosition,
    SummaryLength length = SummaryLength.medium,
  }) {
    if (messages.isEmpty) return '';

    final startIndex = lastSummaryPosition >= 0 ? lastSummaryPosition + 1 : 0;
    if (startIndex >= messages.length) return '';

    final relevantMessages = messages.sublist(startIndex);
    final buffer = StringBuffer();

    for (final msg in relevantMessages) {
      buffer.writeln('${msg.role.name}: ${msg.content}');
    }

    final conversationText = buffer.toString();
    final spec = resolveSummaryLengthSpec(length);

    return '<instructions>\n'
        'Summarize this conversation history. ${spec.guidance}\n'
        '${spec.formatting}\n'
        'Target: around ${spec.targetCharacters} characters '
        '(range: ${spec.minCharacters}-${spec.maxCharacters}).\n'
        'Preserve key facts, decisions, user preferences, and action items.\n'
        'Output format: wrap the summary in [SUMMARY]...[/SUMMARY] tags.\n'
        '</instructions>\n\n'
        '<context>\n'
        'You are summarizing a conversation between a user and an AI assistant.\n'
        '</context>\n\n'
        '<content>\n'
        '$conversationText\n'
        '</content>';
  }

}