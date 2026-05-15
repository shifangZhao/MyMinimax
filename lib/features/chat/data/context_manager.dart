import '../domain/chat_message.dart';
import 'prompts/summary_lengths.dart';

/// 上下文管理器 - 跟踪 token 使用量并在达到阈值时触发摘要
class ContextManager {

  ContextManager({this.contextLimit = defaultContextLimit});
  /// MiniMax M2.7 系列上下文窗口: 204,800 tokens
  /// 消息历史上限 = 204,800 - 2000(系统提示) - 5000(回复预留) = 197,800
  static const int defaultContextLimit = 197800;

  /// 触发摘要的阈值（百分比）
  static const double summaryThreshold = 0.75;

  /// 系统提示词预估 token 数（固定开销）
  static const int systemPromptEstimate = 2000;

  /// 当前上下文限制
  final int contextLimit;

  /// 当前 token 使用量
  int currentTokens = 0;

  /// 消息列表（用于计算）
  final List<ChatMessage> _messages = [];

  /// 根据模型名称获取上下文限制
  static int getContextLimitForModel(String model) {
    if (model.contains('M2.7') || model.contains('M2.5') || model.contains('M2.1') || model.contains('M2')) {
      return 180000; // 180K，实测上限 200K
    }
    return defaultContextLimit;
  }

  /// 计算单条消息的 token 数（粗略估算）
  /// 中文约 1.5-2 字符/token，英文约 3-4 字符/token
  int estimateMessageTokens(ChatMessage msg) {
    int charCount = 0;
    // content
    for (final char in msg.content.codeUnits) {
      if (char > 127) {
        charCount += 2; // CJK 等宽字符
      } else {
        charCount += 1;
      }
    }
    // thinking（如有）
    final thinking = msg.thinking;
    if (thinking != null && thinking.isNotEmpty) {
      for (final char in thinking.codeUnits) {
        if (char > 127) {
          charCount += 2;
        } else {
          charCount += 1;
        }
      }
    }
    // 保守估算：÷3.0 token/chars + 15% JSON/block 结构开销
    return (charCount / 3.0 * 1.15).round();
  }

  /// 计算当前总 token 使用量
  int calculateTotalTokens({
    List<Map<String, String>>? history,
  }) {
    int total = systemPromptEstimate; // 系统提示词固定开销

    // 加上历史消息
    for (final msg in _messages) {
      total += estimateMessageTokens(msg);
    }

    // 加上 pending 消息
    for (final msg in _pendingMessages) {
      total += estimateMessageTokens(msg);
    }

    return total;
  }

  /// 待发送的消息（还未加入 _messages）
  final List<ChatMessage> _pendingMessages = [];

  /// 添加待发送消息（不立即计入，避免重复计算）
  void addPendingMessage(ChatMessage msg) {
    _pendingMessages.add(msg);
  }

  /// 确认消息（从 pending 移到正式列表）
  void confirmMessage(ChatMessage msg) {
    _pendingMessages.removeWhere((m) => m.id == msg.id);
    _messages.add(msg);
    currentTokens = calculateTotalTokens();
  }

  /// 取消待发送消息
  void cancelPendingMessage(String msgId) {
    _pendingMessages.removeWhere((m) => m.id == msgId);
  }

  /// 获取当前使用率（0.0 - 1.0）
  double get usageRate {
    return currentTokens / contextLimit;
  }

  /// 是否达到需要摘要的阈值
  bool get needsSummary {
    return usageRate >= summaryThreshold;
  }

  /// 获取剩余可用 token 数
  int get remainingTokens {
    return contextLimit - currentTokens;
  }

  /// 是否可以发送新消息（考虑 pending 消息）
  bool canSendMessage(ChatMessage newMsg) {
    final estimated = estimateMessageTokens(newMsg);
    return (currentTokens + estimated) < contextLimit * 0.95; // 留 5% buffer
  }

  /// 获取需要摘要的消息范围（从最早的消息开始）
  List<ChatMessage> getMessagesNeedingSummary() {
    return List.from(_messages);
  }

  /// 获取上下文使用情况的描述
  String getUsageDescription() {
    return '$currentTokens / $contextLimit tokens (${(usageRate * 100).toStringAsFixed(1)}%)';
  }

  /// 清除已摘要的消息，保留最近的消息
  void clearSummarizedMessages(int keepCount) {
    if (_messages.length > keepCount) {
      _messages.removeRange(0, _messages.length - keepCount);
      currentTokens = calculateTotalTokens();
    }
  }

  /// 重置上下文
  void reset() {
    _messages.clear();
    _pendingMessages.clear();
    currentTokens = 0;
  }

  /// 根据当前 token 使用量推荐摘要长度级别
  SummaryLength get recommendedSummaryLength {
    final total = calculateTotalTokens();
    if (total < 10000) return SummaryLength.short;
    if (total < 25000) return SummaryLength.medium;
    if (total < 60000) return SummaryLength.long;
    if (total < 100000) return SummaryLength.xl;
    return SummaryLength.xxl;
  }

  /// 从数据库加载历史消息
  void loadFromMessages(List<ChatMessage> messages) {
    _messages.clear();
    _messages.addAll(messages);
    currentTokens = calculateTotalTokens();
  }

  /// 获取上下文状态描述
  ContextStatus getStatus() {
    final total = calculateTotalTokens();
    final rate = contextLimit > 0 ? total / contextLimit : 0.0;

    String status;
    if (rate < 0.5) {
      status = '充足';
    } else if (rate < 0.75) {
      status = '良好';
    } else if (rate < 0.9) {
      status = '偏紧';
    } else {
      status = '危险';
    }

    return ContextStatus(
      usedTokens: total,
      limitTokens: contextLimit,
      usageRate: rate,
      status: status,
      needsSummary: rate >= summaryThreshold,
    );
  }
}

/// 上下文状态
class ContextStatus {

  ContextStatus({
    required this.usedTokens,
    required this.limitTokens,
    required this.usageRate,
    required this.status,
    required this.needsSummary,
  });
  final int usedTokens;
  final int limitTokens;
  final double usageRate;
  final String status;
  final bool needsSummary;

  String get description => '$usedTokens / $limitTokens (${(usageRate * 100).toStringAsFixed(1)}%)';
}