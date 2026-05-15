/// Skills 技能系统 — 可插拔知识模块
///
/// 每个 Skill 的核心是 SKILL.md，包含 YAML frontmatter + Markdown body。
///
/// 加载路径（按优先级）：
/// 1. 内置 skill (lib/core/skills/builtin/)
/// 2. {workspace}/.claude/skills/<name>/SKILL.md
/// 3. {workspace}/skills/<name>/SKILL.md
///
/// 触发方式：
/// - description 字段用于 AI 意图匹配，匹配到的 skill 才注入上下文
/// - 用户可在设置中强制启用某个 skill（始终注入）
library;

enum SkillSource { builtin, externalDirectory, saf }

class Skill {

  Skill({
    required this.name,
    required this.description,
    required this.category,
    required this.systemPromptSnippet, this.origin = 'user',
    this.version,
    this.triggerOn = const [],
    this.suggestedTools = const [],
    this.source = SkillSource.builtin,
    this.directoryPath,
    this.configJson,
    this.isEnabled = false,
    this.useCount = 0,
    this.lastUsedAt,
  });
  final String name;
  final String description;
  final String category;

  /// builtin / community / user
  final String origin;

  /// 可选版本号
  final String? version;

  /// Markdown body（frontmatter 之后的内容）
  final String systemPromptSnippet;

  /// 触发关键词（从 description + body 中提取）
  final List<String> triggerOn;

  /// 关联工具
  final List<String> suggestedTools;

  /// 加载来源
  SkillSource source;

  /// 外部 skill 的目录路径
  final String? directoryPath;

  /// 可选的 config.json 内容
  final Map<String, dynamic>? configJson;

  /// 是否启用
  bool isEnabled;

  /// 使用统计
  int useCount = 0;
  DateTime? lastUsedAt;

  /// Markdown header（按需注入时使用）
  String toHeader() {
    final buf = StringBuffer();
    buf.writeln('--- $name: $description ---');
    if (version != null) buf.writeln('(v$version, origin: $origin)');
    return buf.toString();
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'category': category,
    'origin': origin,
    'version': version,
    'triggerOn': triggerOn,
    'suggestedTools': suggestedTools,
    'source': source.name,
    'isEnabled': isEnabled,
    'useCount': useCount,
  };
}

class SkillRegistry {
  SkillRegistry._();
  static final SkillRegistry _defaultInstance = SkillRegistry._();
  static SkillRegistry? _override;

  static SkillRegistry get instance => _override ?? _defaultInstance;
  static void setTestInstance(SkillRegistry v) => _override = v;
  static void reset() => _override = null;

  final Map<String, Skill> _skills = {};

  void register(Skill skill) {
    _skills[skill.name] = skill;
  }

  void registerAll(List<Skill> skills) {
    for (final s in skills) {
      register(s);
    }
  }

  void unregister(String name) {
    _skills.remove(name);
  }

  Skill? getSkill(String name) => _skills[name];

  List<Skill> get all => List.unmodifiable(_skills.values);

  List<Skill> get enabledSkills =>
      _skills.values.where((s) => s.isEnabled).toList();

  List<Skill> get disabledSkills =>
      _skills.values.where((s) => !s.isEnabled).toList();

  List<Skill> getByCategory(String category) =>
      _skills.values.where((s) => s.category == category).toList();

  List<Skill> getBySource(SkillSource source) =>
      _skills.values.where((s) => s.source == source).toList();

  /// 外部加载的 skills（可重新扫描卸载）
  List<Skill> get externalSkills =>
      _skills.values.where((s) => s.source != SkillSource.builtin).toList();

  void setEnabled(String name, bool enabled) {
    final skill = _skills[name];
    if (skill != null) {
      skill.isEnabled = enabled;
    }
  }

  void setEnabledAll(List<String> names) {
    for (final s in _skills.values) {
      s.isEnabled = names.contains(s.name);
    }
  }

  List<String> get enabledNames =>
      _skills.values.where((s) => s.isEnabled).map((s) => s.name).toList();

  void recordUse(String name) {
    final skill = _skills[name];
    if (skill != null) {
      skill.useCount++;
      skill.lastUsedAt = DateTime.now();
    }
  }

  /// 找到与用户输入匹配的 skills。
  @Deprecated('Keyword matching replaced by LLM-driven skill_load. Use skill catalog instead.')
  List<Skill> findMatchingSkills(String userInput) {
    return [];
  }

  /// 带评分的匹配结果，按相关性降序排列。
  @Deprecated('Keyword matching replaced by LLM-driven skill_load. Use skill catalog instead.')
  List<SkillMatch> findMatchingSkillsRanked(String userInput, {
    Set<String> activeNames = const {},
    Set<String> historicallyUsefulNames = const {},
  }) {
    return [];
  }

  /// 构建完整 system prompt（所有启用的 skill 都拼接进去）
  String buildSkillPrompt() {
    final enabled = enabledSkills;
    if (enabled.isEmpty) return '';

    final buf = StringBuffer();
    buf.writeln();
    buf.writeln('【已启用的专业能力】');
    for (final skill in enabled) {
      buf.writeln(skill.toHeader());
      buf.writeln(skill.systemPromptSnippet);
      buf.writeln();
    }
    return buf.toString();
  }

  /// 构建按需 prompt — 只注入匹配当前上下文的 skills
  String buildRelevantPrompt(String userInput) {
    final matching = findMatchingSkills(userInput);
    if (matching.isEmpty) return '';

    final buf = StringBuffer();
    buf.writeln();
    buf.writeln('【按需激活的专业能力】');
    for (final skill in matching) {
      buf.writeln(skill.toHeader());
      buf.writeln(skill.systemPromptSnippet);
      buf.writeln();
      recordUse(skill.name);
    }
    return buf.toString();
  }

  int get totalSkillPromptTokens {
    final text = buildSkillPrompt();
    return (text.length / 2).ceil();
  }

  List<Map<String, dynamic>> exportState() =>
      all.map((s) => s.toJson()).toList();

  /// 清空所有外部加载的 skills（保留内置）
  void clearExternal() {
    _skills.removeWhere((_, s) => s.source != SkillSource.builtin);
  }
}

/// 技能匹配结果（技能 + 相关性得分）
class SkillMatch {

  SkillMatch({required this.skill, required this.score});
  final Skill skill;
  final int score;
}
