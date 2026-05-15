/// ============ 反馈层：回溯修正 + 策略升级 ============
library;

/// 反馈类型
enum FeedbackType {
  correction, // 纠正（你说"不对"）
  refinement, // 细化（"再详细点"）
  expand, // 扩展（"展开说说"）
  confirm, // 确认（"对了"）
  reject, // 拒绝（"不是这个"）
}

/// 反馈事件
class Feedback {

  Feedback({
    required this.type,
    this.details,
    this.attemptCount = 1,
  });
  final FeedbackType type;
  final String? details;
  final int attemptCount;
}

/// 策略升级
enum StrategyUpgrade {
  none, // 无需升级
  addVerification, // 增加验证步骤
  changeFormat, // 换格式
  addDetails, // 增加细节
  simplify, // 简化
  askClarify, // 询问澄清
}

/// 反馈处理器
class FeedbackProcessor {
  int _attemptCount = 0;

  /// 处理反馈，返回升级策略
  StrategyUpgrade process(Feedback feedback) {
    _attemptCount = feedback.attemptCount;

    switch (feedback.type) {
      case FeedbackType.correction:
        return _handleCorrection(feedback);
      case FeedbackType.refinement:
        return _handleRefinement(feedback);
      case FeedbackType.expand:
        return StrategyUpgrade.addDetails;
      case FeedbackType.confirm:
        return StrategyUpgrade.none;
      case FeedbackType.reject:
        return _handleReject(feedback);
    }
  }

  /// 处理纠正
  StrategyUpgrade _handleCorrection(Feedback feedback) {
    _attemptCount++;

    if (_attemptCount >= 3) {
      // 连续3次失败，询问澄清
      return StrategyUpgrade.askClarify;
    }

    // 检查是否是格式问题
    if (_isFormatIssue(feedback.details)) {
      return StrategyUpgrade.changeFormat;
    }

    // 检查是否是细节问题
    if (_isDetailIssue(feedback.details)) {
      return StrategyUpgrade.addDetails;
    }

    // 默认增加验证
    return StrategyUpgrade.addVerification;
  }

  /// 处理细化请求
  StrategyUpgrade _handleRefinement(Feedback feedback) {
    return StrategyUpgrade.addDetails;
  }

  /// 处理拒绝
  StrategyUpgrade _handleReject(Feedback feedback) {
    _attemptCount++;

    if (_attemptCount >= 2) {
      return StrategyUpgrade.askClarify;
    }

    return StrategyUpgrade.changeFormat;
  }

  bool _isFormatIssue(String? details) {
    if (details == null) return false;
    final formatKeywords = ['格式', 'json', 'markdown', '代码', 'format', 'code'];
    return formatKeywords.any((k) => details.toLowerCase().contains(k));
  }

  bool _isDetailIssue(String? details) {
    if (details == null) return false;
    final detailKeywords = ['详细', '更多', '展开', '具体', '细节', 'detail', 'more'];
    return detailKeywords.any((k) => details.toLowerCase().contains(k));
  }

  /// 重置计数器
  void reset() {
    _attemptCount = 0;
  }

  /// 获取当前尝试次数
  int get attemptCount => _attemptCount;
}