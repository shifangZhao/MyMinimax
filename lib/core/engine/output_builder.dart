import 'input_processor.dart';
import 'decision_engine.dart';

/// ============ 输出层：简化版 ============

/// 输出格式
enum OutputFormat {
  plain,      // 纯文本
  markdown,   // Markdown结构化
  json,      // JSON
  code,      // 代码块
  list,      // 列表
}

/// 输出风格
enum OutputStyle {
  concise,   // 简洁 - 直接给结果
  detailed,  // 详细 - 全解释
  teaching,  // 教学式 - 分步讲解
  consult,  // 咨询式 - 提供选项
}

/// 输出结果
class Output {

  Output({
    required this.content,
    this.format = OutputFormat.plain,
    this.style = OutputStyle.detailed,
    this.warnings = const [],
    this.metadata,
  });
  final String content;
  final OutputFormat format;
  final OutputStyle style;
  final List<Warning> warnings;
  final Metadata? metadata;
}

/// 警告/注意事项
class Warning {

  Warning({required this.message, this.level = WarningLevel.info});
  final String message;
  final WarningLevel level;
}

enum WarningLevel {
  info,
  suggestion,
  caution,
  error,
}

/// 元数据
class Metadata {

  Metadata({
    required this.confidence,
    this.verificationHint,
    this.sources = const [],
  });
  final double confidence;
  final String? verificationHint;
  final List<String> sources;
}

/// 输出构建器 - 简化版，让AI自行决定格式
class OutputBuilder {
  /// 构建最终输出
  Output build({
    required Decision decision,
    required InputAnalysis input,
    required List<String> rawResponses,
  }) {
    // 直接组合原始响应，让AI自行决定格式
    final combined = rawResponses.join('\n\n');

    return Output(
      content: combined,
      format: OutputFormat.markdown,
      style: OutputStyle.detailed,
      warnings: [],
      metadata: Metadata(
        confidence: 1.0,
      ),
    );
  }
}
