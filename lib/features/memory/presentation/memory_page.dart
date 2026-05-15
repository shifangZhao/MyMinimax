import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/app.dart';
import '../data/memory_cache.dart';
import '../data/memory_entry.dart';
import '../data/memory_consolidator.dart';
import '../data/memory_repository.dart';
import 'dart:math' as math;
import '../domain/user_memory.dart';

final memoryRepositoryProvider = Provider((ref) => MemoryRepository());

class MemoryPage extends ConsumerStatefulWidget {
  const MemoryPage({super.key});
  @override
  ConsumerState<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends ConsumerState<MemoryPage> {
  UserMemory _memory = const UserMemory();
  List<PendingEntry> _pendingEntries = [];
  Map<String, List<MemoryEntry>> _openEntries = {};  // category → entries
  final Map<String, bool> _sectionExpanded = {
    'static': true, 'dynamic': true, 'pref': true, 'note': true,
    'interest': true, 'fact': true, 'experience': true, 'relationship': true,
    'health': true, 'professional': true, 'plan': true, 'ai': true,
  };
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<MemoryEntry> _searchResults = [];
  Timer? _searchDebounce;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  void initState() {
    super.initState();
    _load();
    MemoryCache.instance.addListener(_onCacheChanged);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    MemoryCache.instance.removeListener(_onCacheChanged);
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onCacheChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final repo = ref.read(memoryRepositoryProvider);
    await repo.init();
    await repo.expireOverdueTasks();
    final memory = await repo.loadMemory();
    if (mounted) {
      setState(() {
      _memory = memory;
      _pendingEntries = MemoryCache.instance.getPending();
      _openEntries = _loadOpenEntries();
      _isLoading = false;
    });
    }
  }

  /// Collect active memories from open categories (not covered by the 17 preset fields).
  Map<String, List<MemoryEntry>> _loadOpenEntries() {
    final map = <String, List<MemoryEntry>>{};
    final presetKeys = {
      'static': {'birthday', 'gender', 'nativeLanguage'},
      'dynamic': {'knowledgeBackground', 'currentIdentity', 'location', 'usingLanguage',
                  'shortTermGoals', 'shortTermInterests', 'behaviorHabits', 'namePreference'},
      'preference': {'answerStyle', 'detailLevel', 'formatPreference', 'visualPreference'},
      'notice': {'communicationRules', 'prohibitedItems', 'otherRequirements'},
    };

    for (final m in MemoryCache.instance.allActive) {
      // Skip preset keys — they're shown in the dedicated sections
      final presetForCat = presetKeys[m.category];
      if (presetForCat != null && m.key != null && presetForCat.contains(m.key)) continue;
      // Skip episodic/procedural — shown elsewhere or not user-editable
      if (m.category == 'episodic' || m.category == 'procedural') continue;
      map.putIfAbsent(m.category, () => []).add(m);
    }
    return map;
  }

  void _refresh() {
    if (mounted) {
      setState(() {
      _memory = UserMemory(
        birthday: MemoryCache.instance.get('static', 'birthday') ?? '',
        gender: MemoryCache.instance.get('static', 'gender') ?? '',
        nativeLanguage: MemoryCache.instance.get('static', 'nativeLanguage') ?? '',
        knowledgeBackground: MemoryCache.instance.get('dynamic', 'knowledgeBackground') ?? '',
        currentIdentity: MemoryCache.instance.get('dynamic', 'currentIdentity') ?? '',
        location: MemoryCache.instance.get('dynamic', 'location') ?? '',
        usingLanguage: MemoryCache.instance.get('dynamic', 'usingLanguage') ?? '',
        shortTermGoals: MemoryCache.instance.get('dynamic', 'shortTermGoals') ?? '',
        shortTermInterests: MemoryCache.instance.get('dynamic', 'shortTermInterests') ?? '',
        behaviorHabits: MemoryCache.instance.get('dynamic', 'behaviorHabits') ?? '',
        namePreference: MemoryCache.instance.get('dynamic', 'namePreference') ?? '',
        answerStyle: MemoryCache.instance.get('preference', 'answerStyle') ?? '',
        detailLevel: MemoryCache.instance.get('preference', 'detailLevel') ?? '',
        formatPreference: MemoryCache.instance.get('preference', 'formatPreference') ?? '',
        visualPreference: MemoryCache.instance.get('preference', 'visualPreference') ?? '',
        communicationRules: MemoryCache.instance.get('notice', 'communicationRules') ?? '',
        prohibitedItems: MemoryCache.instance.get('notice', 'prohibitedItems') ?? '',
        otherRequirements: MemoryCache.instance.get('notice', 'otherRequirements') ?? '',
      );
      _pendingEntries = MemoryCache.instance.getPending();
      _openEntries = _loadOpenEntries();
    });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final textMuted = _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted;
    final dividerColor = _isDark ? PixelTheme.darkBorderSubtle : PixelTheme.border;

    return Scaffold(
      backgroundColor: _isDark ? PixelTheme.darkBase : PixelTheme.background,
      appBar: AppBar(
        title: Text('用户记忆', style: TextStyle(fontFamily: 'monospace', color: textPrimary)),
        centerTitle: true,
        backgroundColor: _isDark ? PixelTheme.darkBase : PixelTheme.background,
        foregroundColor: textPrimary, elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: textMuted),
            color: _isDark ? PixelTheme.darkSurface : PixelTheme.surface,
            onSelected: (v) {
              if (v == 'refresh') _refresh();
              if (v == 'consolidate') _runConsolidation();
              if (v == 'graph') _showMemoryGraph();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'refresh', child: Text('刷新')),
              const PopupMenuItem(value: 'consolidate', child: Text('执行记忆整合')),
              const PopupMenuItem(value: 'graph', child: Text('记忆图谱')),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: PixelTheme.brandBlue))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _buildSearchBar(textMuted),
                const SizedBox(height: 8),
                if (_searchQuery.isNotEmpty)
                  ..._buildSearchResultChildren(textPrimary, textMuted)
                else ...[
                  _buildSection('静态画像', Icons.person_outline, 'static',
                  children: [
                    _fieldRow('性别', _memory.gender, onTap: () => _editStaticChip('性别', 'static', 'gender', const ['', '男', '女', '其他']), dividerColor: dividerColor),
                    _fieldRow('生日', _memory.birthday, onTap: _editStaticDate, dividerColor: dividerColor),
                    _fieldRow('母语', _memory.nativeLanguage, onTap: () => _editStaticChip('母语', 'static', 'nativeLanguage', const ['', '中文', 'English', '其他']), dividerColor: dividerColor, isLast: true),
                  ], textPrimary: textPrimary, textMuted: textMuted),
                const SizedBox(height: 4),
                _buildSection('动态画像', Icons.auto_awesome, 'dynamic',
                  children: [
                    _fieldRow('知识背景', _memory.knowledgeBackground, dividerColor: dividerColor),
                    _fieldRow('当前身份', _memory.currentIdentity, dividerColor: dividerColor),
                    _fieldRow('所在地区', _memory.location, dividerColor: dividerColor),
                    _fieldRow('使用语言', _memory.usingLanguage, dividerColor: dividerColor),
                    _fieldRow('短期目标', _memory.shortTermGoals, dividerColor: dividerColor),
                    _fieldRow('短期兴趣', _memory.shortTermInterests, dividerColor: dividerColor),
                    _fieldRow('行为习惯', _memory.behaviorHabits, dividerColor: dividerColor),
                    _fieldRow('称呼偏好', _memory.namePreference, dividerColor: dividerColor, isLast: true),
                  ], textPrimary: textPrimary, textMuted: textMuted),
                const SizedBox(height: 4),
                _buildSection('交互偏好', Icons.tune, 'pref',
                  children: [
                    _fieldRow('回答风格', _memory.answerStyle, dividerColor: dividerColor),
                    _fieldRow('详细程度', _memory.detailLevel, dividerColor: dividerColor),
                    _fieldRow('格式偏好', _memory.formatPreference, dividerColor: dividerColor),
                    _fieldRow('视觉偏好', _memory.visualPreference, dividerColor: dividerColor, isLast: true),
                  ], textPrimary: textPrimary, textMuted: textMuted),
                const SizedBox(height: 4),
                _buildSection('注意事项', Icons.info_outline, 'note',
                  children: [
                    _fieldRow('沟通规则', _memory.communicationRules, dividerColor: dividerColor, multiline: true),
                    _fieldRow('禁止事项', _memory.prohibitedItems, dividerColor: dividerColor, multiline: true),
                    _fieldRow('其他要求', _memory.otherRequirements, dividerColor: dividerColor, multiline: true, isLast: true),
                  ], textPrimary: textPrimary, textMuted: textMuted),

                // ── 开放类别区（AI 提取的活跃记忆）──
                ..._buildOpenCategorySections(textPrimary, textMuted, dividerColor),

                // ── AI 待确认 ──
                if (_pendingEntries.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildSection('AI 待确认', Icons.psychology_outlined, 'ai',
                    children: [
                      for (final entry in _pendingEntries) _buildPendingCard(entry),
                    ], textPrimary: textPrimary, textMuted: textMuted),
                ],
              ],
              ],
            ),
    );
  }

  // ═══ Section header + body ═══
  Widget _buildSection(
    String title, IconData icon, String sectionKey, {
    required List<Widget> children,
    required Color textPrimary,
    required Color textMuted,
  }) {
    final expanded = _sectionExpanded[sectionKey] ?? true;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _sectionExpanded[sectionKey] = !expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(children: [
            Icon(icon, size: 18, color: _isDark ? PixelTheme.darkPrimary : PixelTheme.primary),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary)),
            const Spacer(),
            AnimatedRotation(turns: expanded ? 0.25 : 0, duration: const Duration(milliseconds: 200), child: Icon(Icons.chevron_right, size: 20, color: textMuted)),
          ]),
        ),
      ),
      AnimatedCrossFade(
        firstChild: const SizedBox(width: double.infinity),
        secondChild: Column(children: children),
        crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        duration: const Duration(milliseconds: 200),
      ),
    ]);
  }

  // ═══ Compact field row ═══
  Widget _fieldRow(String label, String value, {
    required Color dividerColor, VoidCallback? onTap,
    bool multiline = false,
    bool isLast = false,
  }) {
    final hasValue = value.isNotEmpty;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              crossAxisAlignment: multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 72,
                  child: Text(label, style: TextStyle(fontSize: 13, color: _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasValue ? value : '(未设置)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: hasValue ? FontWeight.w500 : FontWeight.normal,
                      color: hasValue
                          ? (_isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)
                          : (_isDark ? PixelTheme.darkTextMuted.withValues(alpha: 0.5) : PixelTheme.textMuted.withValues(alpha: 0.5)),
                    ),
                    maxLines: multiline ? 3 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onTap != null)
                  Icon(Icons.chevron_right, size: 16, color: _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted),
              ],
            ),
          ),
        ),
        if (!isLast) Divider(height: 1, color: dividerColor, indent: 4, endIndent: 4),
      ],
    );
  }

  // ═══ Static field editing ═══

  Future<void> _editStaticChip(String label, String type, String key, List<String> options) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = _getStaticValue(key);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? PixelTheme.darkSurface : PixelTheme.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
        content: Wrap(spacing: 8, runSpacing: 8, children: options.map((opt) {
          final isSel = opt == current;
          final display = opt.isEmpty ? '(不指定)' : opt;
          return GestureDetector(
            onTap: () => Navigator.pop(ctx, opt),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                gradient: isSel ? PixelTheme.primaryGradient : null,
                color: isSel ? null : (isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(display, style: TextStyle(fontSize: 13, fontWeight: isSel ? FontWeight.w600 : FontWeight.normal, color: isSel ? Colors.white : (isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary))),
            ),
          );
        }).toList()),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消'))],
      ),
    );
    if (result != null && result != current) {
      await MemoryCache.instance.set(type, key, result, confirmed: true);
      _refresh();
    }
  }

  Future<void> _editStaticDate() async {
    final now = DateTime.now();
    final current = _memory.birthday;
    final initial = current.isNotEmpty ? DateTime.tryParse(current) ?? now : now;
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(1900), lastDate: now);
    if (picked != null) {
      final v = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      if (v != current) {
        await MemoryCache.instance.set('static', 'birthday', v, confirmed: true);
        _refresh();
      }
    }
  }

  String _getStaticValue(String key) {
    switch (key) {
      case 'gender': return _memory.gender;
      case 'nativeLanguage': return _memory.nativeLanguage;
      default: return '';
    }
  }

  // ═══ 开放类别记忆区（AI 提取的非预设字段） ═══

  static const _openCategoryMeta = {
    'interest':   ('兴趣爱好', Icons.favorite_outline, '收录娱乐、阅读、影视等偏好'),
    'fact':       ('个人事实', Icons.lightbulb_outline, '杂项个人信息'),
    'experience': ('经历事件', Icons.auto_stories, '过往经历和重要事件'),
    'relationship': ('人际关系', Icons.people_outline, '家人、朋友、同事等'),
    'health':     ('健康养生', Icons.monitor_heart_outlined, '饮食、运动、健康相关'),
    'professional': ('职业工作', Icons.work_outline, '工作、技能、职业发展'),
    'plan':       ('计划目标', Icons.flag_outlined, '未来计划和目标'),
  };

  List<Widget> _buildOpenCategorySections(Color textPrimary, Color textMuted, Color dividerColor) {
    final sections = <Widget>[];
    for (final cat in _openCategoryMeta.keys) {
      final entries = _openEntries[cat];
      if (entries == null || entries.isEmpty) continue;
      final meta = _openCategoryMeta[cat]!;
      sections.add(const SizedBox(height: 4));
      sections.add(_buildSection(
        meta.$1, meta.$2, cat,
        children: [
          for (final entry in entries)
            _buildOpenMemoryCard(entry, textPrimary, textMuted, dividerColor),
        ],
        textPrimary: textPrimary, textMuted: textMuted,
      ));
    }
    return sections;
  }

  /// Card for an open-category memory entry with link indicator and actions.
  Widget _buildOpenMemoryCard(MemoryEntry entry, Color textPrimary, Color textMuted, Color dividerColor) {
    final confColor = entry.confidence == 'high'
        ? PixelTheme.success
        : entry.confidence == 'low'
            ? PixelTheme.warning
            : PixelTheme.brandBlue;
    final hasLinks = entry.linkedMemoryIds.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PixelCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Content
          Text(entry.content, style: TextStyle(fontSize: 13, color: textPrimary, height: 1.4)),
          const SizedBox(height: 10),
          // Meta row
          Row(children: [
            _badge(entry.confidence == 'high' ? '高' : entry.confidence == 'low' ? '低' : '中', confColor),
            const SizedBox(width: 6),
            if (entry.key != null) ...[
              _badge(entry.key!, textMuted),
              const SizedBox(width: 6),
            ],
            Text(_timeAgo(entry.createdAt), style: TextStyle(fontSize: 10, color: textMuted)),
            const Spacer(),
            // Linked memories indicator
            if (hasLinks)
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _showLinkedMemories(entry, textPrimary, textMuted),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.link, size: 14, color: PixelTheme.brandBlue),
                    const SizedBox(width: 3),
                    Text('${entry.linkedMemoryIds.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PixelTheme.brandBlue)),
                  ]),
                ),
              ),
            const SizedBox(width: 6),
            // Delete
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () async {
                await MemoryCache.instance.remove(entry.category, entry.key ?? '');
                _refresh();
              },
              child: Icon(Icons.close, size: 16, color: textMuted.withValues(alpha: 0.5)),
            ),
          ]),
        ]),
      ),
    );
  }

  void _showLinkedMemories(MemoryEntry entry, Color textPrimary, Color textMuted) {
    final linked = <MemoryEntry>[];
    for (final id in entry.linkedMemoryIds) {
      final m = MemoryCache.instance.allActive.where((e) => e.id == id).firstOrNull;
      if (m != null) linked.add(m);
    }
    if (linked.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: _isDark ? PixelTheme.darkSurface : PixelTheme.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('关联记忆 (${linked.length})', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
            const SizedBox(height: 4),
            Text(entry.content, style: TextStyle(fontSize: 12, color: textMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
            const Divider(height: 24),
            ...linked.map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.link, size: 14, color: PixelTheme.brandBlue),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.content, style: TextStyle(fontSize: 13, color: textPrimary)),
                  const SizedBox(height: 2),
                  Text('${m.category}${m.key != null ? '.${m.key}' : ''} · ${_timeAgo(m.createdAt)}', style: TextStyle(fontSize: 10, color: textMuted)),
                ])),
              ]),
            )),
          ]),
          ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 30) return '${diff.inDays ~/ 30}月前';
    if (diff.inDays > 0) return '${diff.inDays}天前';
    if (diff.inHours > 0) return '${diff.inHours}小时前';
    return '刚刚';
  }

  // ═══ AI 待确认卡片 ═══

  Widget _buildPendingCard(PendingEntry entry) {
    final textPrimary = _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final textMuted = _isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted;
    final confInfo = entry.confidence == 'high' ? (PixelTheme.success, '高') : entry.confidence == 'low' ? (PixelTheme.warning, '低') : (PixelTheme.brandBlue, '中');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: PixelCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 32, height: 32, decoration: BoxDecoration(color: PixelTheme.brandBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.auto_awesome, size: 16, color: PixelTheme.brandBlue)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.key.isNotEmpty ? '${entry.type}.${entry.key}' : entry.type, style: TextStyle(fontSize: 11, color: textMuted, fontFamily: 'monospace')),
              const SizedBox(height: 2),
              Text(entry.value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary)),
            ])),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _badge(confInfo.$2, confInfo.$1),
            const SizedBox(width: 8),
            _badge(entry.source == 'ai' ? 'AI推断' : '正则', entry.source == 'ai' ? PixelTheme.brandBlue : PixelTheme.warning),
            const SizedBox(width: 8),
            Text(entry.sourceDetail, style: TextStyle(fontSize: 10, color: textMuted)),
            const Spacer(),
            _actionBtn('拒绝', PixelTheme.error, () async { await MemoryCache.instance.reject(entry.type, entry.key); _refresh(); }),
            const SizedBox(width: 8),
            _actionBtn('确认', PixelTheme.success, () async { await MemoryCache.instance.confirm(entry.type, entry.key); _refresh(); }),
          ]),
        ]),
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)), child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)));
  Widget _actionBtn(String label, Color color, VoidCallback onTap) => InkWell(borderRadius: BorderRadius.circular(6), onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(border: Border.all(color: color.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(6)), child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color))));

  // ═══ Search ═══

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final q = _searchController.text.trim();
      if (q == _searchQuery) return;
      setState(() => _searchQuery = q);
      if (q.isNotEmpty) {
        _performSearch(q);
      } else {
        setState(() => _searchResults = []);
      }
    });
  }

  Future<void> _performSearch(String query) async {
    try {
      final results = await MemoryCache.instance.retrieveRelevant(query, topK: 20);
      if (mounted && _searchController.text.trim() == query) {
        setState(() => _searchResults = results);
      }
    } catch (_) {}
  }

  Widget _buildSearchBar(Color textMuted) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: _isDark ? PixelTheme.darkBorderSubtle : PixelTheme.border,
      ),
    );
    final focusBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: PixelTheme.brandBlue, width: 1.5),
    );

    return TextField(
      controller: _searchController,
      style: TextStyle(fontSize: 13, color: _isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary),
      decoration: InputDecoration(
        hintText: '搜索记忆...',
        hintStyle: TextStyle(fontSize: 13, color: textMuted),
        prefixIcon: Icon(Icons.search, size: 18, color: textMuted),
        suffixIcon: _searchQuery.isNotEmpty
            ? InkWell(
                onTap: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _searchResults = [];
                  });
                },
                child: Icon(Icons.close, size: 16, color: textMuted),
              )
            : null,
        filled: true,
        fillColor: _isDark ? PixelTheme.darkSurface : PixelTheme.surfaceVariant,
        border: border,
        enabledBorder: border,
        focusedBorder: focusBorder,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  List<Widget> _buildSearchResultChildren(Color textPrimary, Color textMuted) {
    if (_searchResults.isEmpty && _searchQuery.isNotEmpty) {
      return [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('未找到相关记忆', style: TextStyle(color: textMuted)),
          ),
        ),
      ];
    }

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('搜索结果 (${_searchResults.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary)),
      ),
      for (final entry in _searchResults)
        _buildOpenMemoryCard(entry, textPrimary, textMuted, _isDark ? PixelTheme.darkBorderSubtle : PixelTheme.border),
    ];
  }

  // ═══ Consolidation ═══

  Future<void> _runConsolidation() async {
    final consolidator = MemoryConsolidator(MemoryCache.instance);
    if (consolidator.isRunning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('整合正在进行中...')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: PixelTheme.brandBlue)),
    );

    try {
      final report = await consolidator.runOnce();
      if (mounted) Navigator.of(context).pop();

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _isDark ? PixelTheme.darkSurface : PixelTheme.cardBackground,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('记忆整合完成'),
            content: Text(report.toString()),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定'))],
          ),
        );
      }
    } catch (e) {
      print('[memory] error: \$e');
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('整合失败: $e')));
      }
    }
  }

  // ═══ Memory Graph ═══

  void _showMemoryGraph() {
    final all = MemoryCache.instance.allActive;
    final linkedNodes = <String>{};
    for (final m in all) {
      if (m.linkedMemoryIds.isNotEmpty) {
        linkedNodes.add(m.id);
        linkedNodes.addAll(m.linkedMemoryIds);
      }
    }

    final nodes = all.where((m) => linkedNodes.contains(m.id)).toList();
    if (nodes.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无关联记忆，需要先建立记忆链接')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MemoryGraphPage(nodes: nodes, isDark: _isDark),
      ),
    );
  }

}

/// 记忆图谱全屏页 — 用 CustomPainter 展示关联关系。
class _MemoryGraphPage extends StatefulWidget {
  final List<MemoryEntry> nodes;
  final bool isDark;
  const _MemoryGraphPage({required this.nodes, required this.isDark});

  @override
  State<_MemoryGraphPage> createState() => _MemoryGraphPageState();
}

class _MemoryGraphPageState extends State<_MemoryGraphPage> {
  late final Map<String, Offset> _positions = {};
  MemoryEntry? _selectedNode;

  @override
  void initState() {
    super.initState();
    _layout();
  }

  void _layout() {
    final n = widget.nodes.length;
    final w = MediaQuery.of(context).size.width - 40;
    final h = MediaQuery.of(context).size.height - 200;
    final cx = w / 2;
    final cy = h / 2;
    final r = math.min(cx, cy) - 40;

    for (var i = 0; i < n; i++) {
      final angle = 2 * math.pi * i / n - math.pi / 2;
      _positions[widget.nodes[i].id] = Offset(
        cx + r * math.cos(angle),
        cy + r * math.sin(angle),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = widget.isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final textMuted = widget.isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted;

    return Scaffold(
      backgroundColor: widget.isDark ? PixelTheme.darkBase : PixelTheme.background,
      appBar: AppBar(
        title: Text('记忆图谱 (${widget.nodes.length} 节点)', style: TextStyle(color: textPrimary)),
        centerTitle: true,
        backgroundColor: widget.isDark ? PixelTheme.darkBase : PixelTheme.background,
        foregroundColor: textPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTapDown: (d) {
                MemoryEntry? hitNode;
                for (final node in widget.nodes) {
                  final pos = _positions[node.id];
                  if (pos == null) continue;
                  if ((d.localPosition - pos).distance < 32) {
                    hitNode = node;
                    break;
                  }
                }
                setState(() => _selectedNode = hitNode);
              },
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _GraphPainter(
                    nodes: widget.nodes,
                    positions: _positions,
                    isDark: widget.isDark,
                    selectedId: _selectedNode?.id,
                  ),
                ),
              ),
            ),
          ),
          if (_selectedNode != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: widget.isDark ? PixelTheme.darkSurface : PixelTheme.surface,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_selectedNode!.content, style: TextStyle(fontSize: 14, color: textPrimary)),
                const SizedBox(height: 4),
                Text(
                  '${_selectedNode!.category}${_selectedNode!.key != null ? '.${_selectedNode!.key}' : ''} · ${_selectedNode!.confidence} · ${_selectedNode!.linkedMemoryIds.length} 链接',
                  style: TextStyle(fontSize: 11, color: textMuted),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<MemoryEntry> nodes;
  final Map<String, Offset> positions;
  final bool isDark;
  final String? selectedId;

  _GraphPainter({
    required this.nodes,
    required this.positions,
    required this.isDark,
    this.selectedId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintEdge = Paint()
      ..color = (isDark ? Colors.white24 : Colors.black12)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final paintNodeFill = Paint()
      ..color = (isDark ? PixelTheme.brandBlue.withValues(alpha: 0.2) : PixelTheme.brandBlue.withValues(alpha: 0.1))
      ..style = PaintingStyle.fill;

    final paintNodeStroke = Paint()
      ..color = PixelTheme.brandBlue
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final paintSelected = Paint()
      ..color = PixelTheme.success
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    // Draw edges
    for (final node in nodes) {
      final from = positions[node.id];
      if (from == null) continue;
      for (final lid in node.linkedMemoryIds) {
        final to = positions[lid];
        if (to == null) continue;
        canvas.drawLine(from, to, paintEdge);
      }
    }

    // Draw nodes
    for (final node in nodes) {
      final pos = positions[node.id];
      if (pos == null) continue;
      final isSelected = node.id == selectedId;
      final r = isSelected ? 28.0 : 22.0;

      canvas.drawCircle(pos, r, paintNodeFill);
      canvas.drawCircle(pos, r, isSelected ? paintSelected : paintNodeStroke);

      // Short label (first 6 chars of content)
      final label = node.content.length > 6 ? '${node.content.substring(0, 6)}…' : node.content;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(fontSize: 8, color: isDark ? Colors.white70 : Colors.black54),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 56);
      tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => old.selectedId != selectedId;
}
