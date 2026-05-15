/// 结果合成引擎的提示词模板。
class SynthesisPrompt {
  static const String _instructions = '''
将多个子任务输出合并为一份连贯的回复。

1. 通读所有子任务输出。
2. 合并为自然、结构清晰的回复。
3. 删除子任务输出之间的重复内容。
4. 保留所有重要细节和数据。
5. 如有子任务失败，简要说明尝试了什么。
6. 使用 markdown。简洁但完整。

## 输出格式
实现类任务使用以下结构：
### 总结
一句话概述

### 完成了什么
- [成果列表，含文件路径]

### 关键决策
[重要决策、使用的模式等]

### 后续建议
[用户可能的下一步]

一般任务按逻辑顺序呈现，用清晰的标题分段。
''';

  static String build({
    required String userRequest,
    required List<Map<String, dynamic>> taskOutputs,
  }) {
    final buf = StringBuffer();
    buf.writeln('<instructions>');
    buf.writeln(_instructions);
    buf.writeln('</instructions>');
    buf.writeln();
    buf.writeln('<user_request>');
    buf.writeln(userRequest);
    buf.writeln('</user_request>');
    buf.writeln();
    buf.writeln('<task_outputs>');

    for (int i = 0; i < taskOutputs.length; i++) {
      final task = taskOutputs[i];
      buf.writeln();
      buf.writeln('### 任务 ${i + 1}: ${task['label']}');
      buf.writeln('状态: ${task['status']}');
      if (task['status'] == 'completed') {
        if (task['output'] != null) {
          buf.writeln(task['output']);
        }
      } else {
        buf.writeln('错误: ${task['error'] ?? '未知'}');
      }
    }

    buf.writeln('</task_outputs>');
    return buf.toString();
  }
}
