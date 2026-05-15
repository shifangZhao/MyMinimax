/// 任务分解引擎的提示词模板。
class DecompositionPrompt {
  static const String _instructions = '''
分析用户请求，将其分解为带依赖关系的子任务图。

## 可用工具组
- basic: 时间、天气、搜索、网页抓取、定位、询问用户、记忆操作。始终可用。
- map: 导航、POI搜索、路况、地理编码、公交、行政区划。
- browser: 网页浏览、内容提取、截图、表单自动化、JS执行。
- file: 文件读写、grep/glob、文档转换（PDF/Word/Excel/PPT/EPub）、页面生成。
- phone: 通讯录、日历、短信、电话、悬浮窗、截屏、通知。
- cron: 定时任务、提醒、倒计时。
- express: 快递追踪（快递100）。
- generation: 网页/Markdown/HTML生成、音乐生成、图片生成。
- trend: 热搜榜单、趋势话题、历史趋势。
- train: 火车票查询。

## 指南
- 每个子任务应在 1-3 次工具调用内完成。
- 无依赖关系的任务并行执行。最大依赖深度：5。
- 仅分配该子任务实际需要的工具组。
- 温度: 分析 0.3-0.5，编码 0.5-0.7，创意 0.7-0.9，数据提取 0.1。
- 任务描述需包含: 目标、输入（working memory keys）、输出（产物）、约束边界。

## 复杂度
- trivial (0工具，纯知识): tasks 为空数组。
- small (1-2组，2-3步): 分解可选。
- medium (3+组，4-7步): 必须分解。
- large (全组，8+步): 完整流水线。

## 输出
只返回有效 JSON，不要 markdown、不要解释。

{
  "complexityTier": "trivial|small|medium|large",
  "tasks": [
    {
      "id": "t1",
      "label": "简短名称",
      "description": "目标 + 输入 + 输出 + 约束。写具体。",
      "dependsOn": [],
      "requiredToolGroups": ["basic"],
      "complexity": "trivial",
      "params": { "temperature": 1.0 }
    }
  ],
  "workingMemoryInit": { "userIntent": "用户意图简述" }
}
''';

  static String build(String userRequest,
      {String? projectContext, String? conversationContext}) {
    final buf = StringBuffer();
    buf.writeln('<instructions>');
    buf.writeln(_instructions);
    buf.writeln('</instructions>');
    buf.writeln();
    buf.writeln('<user_request>');
    buf.writeln(userRequest);
    buf.writeln('</user_request>');
    if (projectContext != null) {
      buf.writeln();
      buf.writeln('<project_context>');
      buf.writeln(projectContext);
      buf.writeln('</project_context>');
    }
    if (conversationContext != null) {
      buf.writeln();
      buf.writeln('<conversation_context>');
      buf.writeln(conversationContext);
      buf.writeln('</conversation_context>');
    }
    return buf.toString();
  }
}
