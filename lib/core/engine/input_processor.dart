/// ============ 输入层：直接传递用户输入 ============
library;

/// 简化的输入分析 - 直接传递原始输入
class InputAnalysis {

  InputAnalysis({required this.rawInput});
  /// 原始用户输入
  final String rawInput;
}

/// 输入处理器 - 直接返回原始输入
class InputProcessor {
  InputAnalysis analyze(String input, {Map<String, dynamic>? context}) {
    return InputAnalysis(rawInput: input);
  }
}
