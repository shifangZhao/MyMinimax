/// 文档深度分析技能 — 上下文感知双级注入
///
/// 关键词匹配时注入轻量提示；检测到强分析意图时才注入完整操作指南。
library;

import '../skill.dart';

final documentAnalysisSkill = Skill(
  name: 'document-analysis',
  description: '当你需要分析、阅读、检索文档内容时使用 — 先建索引看清结构，再按章节精准定位',
  category: 'analysis',
  origin: 'builtin',
  version: '1.0.0',
  source: SkillSource.builtin,
  isEnabled: true,
  triggerOn: [
    // 短语（精确场景）
    '分析文档', '文档分析',
    '文档结构', '检索文档', '查找章节', '文档摘要',
    '这篇文档', '这个PDF', '这个报告',
    '理解文档', '阅读文档', '文档讲了什么',
    '总结文档', '文档内容',
    // 单字锚点（覆盖自然语言变体）
    '文档', '文件', '报告',
    '分析', '总结', '阅读', '读取', '查看', '解读', '检索',
    '章节', '目录',
    'PDF', 'pdf', 'document', 'report',
  ],
  suggestedTools: [
    'build_page_index', 'get_document_info', 'get_document_structure',
    'get_page_content', 'list_indexed_documents', 'delete_page_index',
    'search_documents', 'read_section', 'close_document',
  ],
  systemPromptSnippet: '''
## 文档分析

你有 9 个文档工具。path 只需在 build_page_index 时传一次，后续工具自动沿用当前文档。

### 树推理导航
拿到文档目录树后，像人类阅读那样逐层推理：
1. 从根节点开始，看每个章节的标题判断是否与用户问题相关
2. 发现相关章节 → 深入其子节点继续判断
3. 到达叶子节点 → 用 get_page_content 读取该页码范围的内容
4. 如果树太大（>50章），先用 read_section(query="关键词") 快速定位，再精确读取

### 工具速查
- build_page_index(path) — 建索引，秒级，一次即可
- get_document_structure(query?, max_nodes?) — 看目录树。传 query 直接搜相关章节
- read_section(section:"章节名") — 一步定位+获取页码范围
- get_page_content(pages:"起-止") — 读原文内容
- search_documents(query) — 跨所有文档搜索
- close_document — 结束当前文档会话
''',
);

