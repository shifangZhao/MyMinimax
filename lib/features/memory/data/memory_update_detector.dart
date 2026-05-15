/// Extracts semantic, episodic, and procedural memories from conversations
/// using Instructor structured extraction. mem0-inspired: ADD-only, extracts
/// from both user AND assistant messages, supports memory linking.
///
/// V2 improvements (mem0 V3 parity):
/// - Open category taxonomy (not just 4 preset types)
/// - Transition capture (old→new with reasons)
/// - Implicit preference recognition
/// - Observation Date for temporal grounding
/// - Existing memory dedup reference in extraction context
/// - related_to → linked_memory_ids pipeline
library;

import 'dart:convert';

import '../../../core/instructor/instructor.dart';
import '../../../core/api/minimax_client.dart';
import 'memory_cache.dart';
import 'memory_entry.dart';
import 'entity_extractor.dart';

class MemoryUpdateDetector {

  MemoryUpdateDetector(this._cache, this._client);
  final MemoryCache _cache;
  final MinimaxClient _client;

  /// Enhanced mem0-V3-style extraction schema with transition capture,
  /// implicit preference recognition, and temporal grounding.
  static final _memorySchema = SchemaDefinition(
    name: 'extract_memory',
    description: '''
Extract new facts, preferences, events, and agent actions from this conversation turn.
Only extract NEW information revealed in this exchange — do not repeat what is already in "现有记忆".
Each fact must be a self-contained sentence understandable without reading the conversation.

Rules:
- ADD only: extract new facts, never update or delete existing memories
- Self-contained: "用户张明喜欢Python编程" not "他喜欢编程"
- Temporal grounding: resolve ALL relative time references using the Observation Date provided in context
  * "昨天" → specific date before Observation Date (e.g. "用户在2026年5月5日...")
  * "上周" → specific week before Observation Date ("用户在2026年4月底那周...")
  * "下个月" → specific month after Observation Date ("用户计划在2026年6月...")
  * "今天" / "刚刚" → Observation Date
  * Always produce absolute dates, never vague relative references
- Confidence: high=explicitly stated, medium=clearly implied, low=weakly implied
- Pay attention to proper nouns: names, places, product names, book titles, brand names
- Capture transitions: when user changes from X to Y, record the full transition
  * "User switched from almond milk to oat milk lattes after developing almond sensitivity" — not just "User prefers oat milk"
  * Include reasons for change when stated
  * If the change is explicitly temporary or a trial ("试用", "先试试"), capture that too
- Recognize implicit preferences through requests and questions:
  * "可以简短回答吗" → preference for concise answer style
  * "说重点" / "直接说结论" → preference for direct/detailed answer style
  * "用表格/列表展示" → format preference
  * "用中文回答" → language preference
  * Questions repeated across conversations may indicate an interest pattern
- Extract ALL topics in a multi-topic conversation — do not stop after the first topic
- Extract incidental facts stated as context in questions
  * "我种的樱桃番茄收成了，有什么伴生种植建议吗？" → extract BOTH the gardening fact AND the question topic
- Preserve specific details: quantities ("416页"), proper nouns, titles, dates, numbers exactly as stated
- Never fabricate: only extract what is stated or clearly implied
- Never infer gender, age, ethnicity from names alone
- Each distinct topic gets its own fact entry — one fact per meaningful piece of information
''',
    inputSchema: {
      'type': 'object',
      'properties': {
        'new_facts': {
          'type': 'array',
          'description': 'New semantic facts from this exchange',
          'items': {
            'type': 'object',
            'properties': {
              'content': {
                'type': 'string',
                'description': 'Self-contained factual sentence with proper pronouns resolved and temporal references grounded to absolute dates.',
              },
              'category': {
                'type': 'string',
                'enum': ['static', 'dynamic', 'preference', 'notice', 'interest', 'fact', 'experience', 'relationship', 'health', 'professional', 'plan', 'episodic', 'procedural'],
                'description': 'Category: static=immutable traits, dynamic=changeable context, preference=interaction style, notice=communication rules/prohibitions, interest=long-term hobbies, fact=personal facts, experience=past events, relationship=connections with people, health=wellness, professional=work, plan=upcoming plans, episodic=conversation scene (auto), procedural=operation log (auto)',
              },
              'key': {
                'type': 'string',
                'description': 'Short key in camelCase. For preference: answerStyle/detailLevel/formatPreference/tone/visualPreference. For dynamic: agentName/namePreference/userTitle/behaviorHabits/shortTermGoals/shortTermInterests/currentIdentity/location/usingLanguage/knowledgeBackground. For notice: communicationRules/prohibitedItems/otherRequirements. For static: birthday/gender/nativeLanguage. Others: free-form.',
              },
              'confidence': {
                'type': 'string',
                'enum': ['high', 'medium'],
              },
              'related_to': {
                'type': 'array',
                'items': {'type': 'string'},
                'description': 'Brief descriptions of EXISTING facts (from "现有记忆") this relates to. Use the exact wording from the existing memory when possible. Only include if there is a clear, specific relationship (same entity, continuation, update, or contradiction).',
              },
            },
            'required': ['content', 'category', 'confidence'],
          },
        },
        'episodic_summary': {
          'type': 'string',
          'description': '1-2 sentence summary of what happened in this conversation turn. Omit if nothing notable happened beyond routine Q&A.',
        },
        'procedural_actions': {
          'type': 'array',
          'description': 'Agent actions that should be remembered for future context (tool calls with notable outcomes)',
          'items': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'description': 'What the agent did. E.g., "Agent sent an email to Bob about the project deadline"',
              },
              'outcome': {
                'type': 'string',
                'description': 'Result or key output of the action',
              },
            },
            'required': ['action'],
          },
        },
      },
    },
    fromJson: (json) => json,
  );

  /// Called after each conversation exchange to detect memory-worthy info.
  /// Now with mem0-V3-style context: existing memories for dedup reference
  /// and observation date for temporal grounding.
  Future<MemoryUpdateResult> analyze({
    required String userMessage,
    required String aiResponse,
  }) async {
    final result = MemoryUpdateResult();
    final observationDate = DateTime.now();

    // Phase 0: Gather existing memories for dedup reference
    List<MemoryEntry> existingActive = [];
    try {
      if (_cache.isLoaded) {
        existingActive = List<MemoryEntry>.from(_cache.allActive);
      }
    } catch (_) {}

    // Instructor extraction from full exchange (user + assistant)
    try {
      final instructor = Instructor.fromClient(
        _client,
        retryPolicy: const RetryPolicy(maxRetries: 1),
      );

      final contextMsg = _buildExtractionContext(existingActive, observationDate);

      final maybe = await instructor.extract<Map<String, dynamic>>(
        schema: _memorySchema,
        messages: [
          Message.user(userMessage),
          Message.assistant(aiResponse),
          Message.user(contextMsg),
        ],
        maxRetries: 1,
      );

      if (maybe.isSuccess) {
        _applyExtracted(maybe.value, result);
      }
    } catch (_) {
      // Extraction is best-effort
    }

    // Legacy [MEM:...] tag parsing from AI response
    _parseAiMemoryTags(aiResponse, result);

    // Write to cache (with linking support)
    if (result.hasUpdates) {
      await _applyUpdates(result, existingActive);
    }

    return result;
  }

  /// Build extraction context with existing memories and observation date.
  /// Mirrors mem0's generate_additive_extraction_prompt().
  String _buildExtractionContext(List<MemoryEntry> existing, DateTime observationDate) {
    final buf = StringBuffer();

    // Existing memories for dedup + linking reference
    if (existing.isNotEmpty) {
      buf.writeln('## 现有记忆 (仅用于去重参考，不要重复提取)');
      final recent = existing.take(20).toList();
      for (var i = 0; i < recent.length; i++) {
        final m = recent[i];
        buf.writeln('${m.id}: ${m.content}');
      }
      buf.writeln('');
    } else {
      buf.writeln('## 现有记忆');
      buf.writeln('(空 — 当前没有已存储的记忆)');
      buf.writeln('');
    }

    buf.writeln('## 观察日期 (用此日期解析所有相对时间引用)');
    buf.writeln(observationDate.toIso8601String().substring(0, 10));
    buf.writeln('将"昨天"解析为该日期的前一天，"上周"解析为该日期前一周，"下个月"解析为该日期后一月。');

    return buf.toString();
  }

  // ===== Map Instructor output to MemoryUpdateResult =====

  void _applyExtracted(Map<String, dynamic> data, MemoryUpdateResult r) {
    // New semantic facts (mem0-style array)
    if (data['new_facts'] is List) {
      for (final fact in (data['new_facts'] as List)) {
        if (fact is Map) {
          final content = (fact['content'] ?? '').toString();
          final category = (fact['category'] ?? 'dynamic').toString();
          final key = (fact['key'] ?? '').toString();
          final confidence = (fact['confidence'] ?? 'medium').toString();
          final relatedTo = fact['related_to'] as List?;

          if (content.isEmpty) continue;
          // Skip low-confidence facts to prevent hallucination pollution
          if (confidence == 'low') continue;
          r.addFact(
            content: content,
            category: category,
            key: key.isNotEmpty ? key : null,
            confidence: confidence,
            relatedTo: relatedTo?.cast<String>(),
          );
        }
      }
    }

    // Backward compat: old flat fields
    _addIfPresent(data, 'namePreference', (v) => r.addFact(content: '用户希望被称为$v', category: 'dynamic', key: 'namePreference', confidence: 'high'));
    _addIfPresent(data, 'birthday', (v) => r.addFact(content: '用户生日为$v', category: 'static', key: 'birthday', confidence: 'high'));
    _addIfPresent(data, 'gender', (v) => r.addFact(content: '用户性别为$v', category: 'static', key: 'gender', confidence: 'high'));

    // Episodic summary
    final episodic = data['episodic_summary'] as String?;
    if (episodic != null && episodic.isNotEmpty) {
      r.episodicSummary = episodic;
    }

    // Procedural actions
    if (data['procedural_actions'] is List) {
      for (final action in (data['procedural_actions'] as List)) {
        if (action is Map) {
          final actionText = (action['action'] ?? '').toString();
          final outcome = (action['outcome'] ?? '').toString();
          if (actionText.isNotEmpty) {
            r.addProceduralAction(actionText, outcome);
          }
        }
      }
    }

    // Old-format preferences
    final prefs = data['preferences'];
    if (prefs is Map) {
      _addIfPresent(prefs as Map<String, dynamic>, 'detailLevel', (v) => r.addFact(content: '用户偏好$v的回答', category: 'preference', key: 'detailLevel', confidence: 'high'));
      _addIfPresent(prefs, 'answerStyle', (v) => r.addFact(content: '用户偏好$v的交流风格', category: 'preference', key: 'answerStyle', confidence: 'high'));
      _addIfPresent(prefs, 'formatPreference', (v) => r.addFact(content: '用户偏好$v的输出格式', category: 'preference', key: 'formatPreference', confidence: 'high'));
    }

    // Old-format tasks
    if (data['tasks'] is List) {
      for (final task in (data['tasks'] as List)) {
        if (task is Map) {
          final title = (task['title'] ?? '').toString();
          final timeHint = (task['timeHint'] ?? '').toString();
          if (title.isNotEmpty) {
            final dueDate = timeHint.isNotEmpty ? _parseTimeHint(timeHint) : null;
            r.addTask(title, '', dueDate);
          }
        }
      }
    }
  }

  void _addIfPresent(Map<String, dynamic> data, String key, void Function(dynamic) setter) {
    final v = data[key];
    if (v != null && (v is! String || v.isNotEmpty)) {
      setter(v);
    }
  }

  /// Match a related_to description against existing memories.
  /// Returns the IDs of matching existing memories for linking.
  List<String> _matchRelatedTo(List<String> relatedTo, List<MemoryEntry> existing) {
    if (relatedTo.isEmpty || existing.isEmpty) return [];

    final linked = <String>{};
    for (final ref in relatedTo) {
      final refLower = ref.toLowerCase();
      for (final m in existing) {
        if (m.content.toLowerCase().contains(refLower) ||
            _hasKeywordOverlap(refLower, m.content.toLowerCase())) {
          linked.add(m.id);
          break;
        }
      }
    }
    return linked.toList();
  }

  /// Check if two strings share at least one meaningful keyword.
  /// Uses CJK bigrams and English 3+ char words.
  bool _hasKeywordOverlap(String a, String b) {
    return _extractKeywords(a).intersection(_extractKeywords(b)).isNotEmpty;
  }

  /// Extract CJK bigrams and English 3+ char words from text.
  /// Filters common stopwords to avoid false-positive linking.
  Set<String> _extractKeywords(String text) {
    const cjkStopBigrams = {
      '用户', '这个', '那个', '什么', '怎么', '为什么', '可以', '没有',
      '不是', '一个', '一下', '一些', '这种', '那种', '时候', '已经',
      '还是', '但是', '因为', '所以', '如果', '虽然', '不过', '而且',
      '知道', '觉得', '认为', '应该', '可能', '需要', '比如', '关于',
      '就是', '的话', '来说', '看到', '还有', '真的', '然后', '之后',
      '之前', '以后', '比较', '非常', '特别', '一起', '不会', '不能',
    };

    final result = <String>{};
    final lower = text.toLowerCase();

    // CJK bigrams — sliding window (not greedy regex, which would consume the entire CJK block)
    final cjkOnly = lower.replaceAll(RegExp(r'[^一-鿿]'), ' ');
    for (final segment in cjkOnly.split(' ')) {
      if (segment.length < 2) continue;
      for (var i = 0; i <= segment.length - 2; i++) {
        final bigram = segment.substring(i, i + 2);
        if (!cjkStopBigrams.contains(bigram)) {
          result.add(bigram);
        }
      }
      // Also add trigrams for longer segments (no stopword filter needed — trigrams are rarely common)
      for (var i = 0; i <= segment.length - 3; i++) {
        result.add(segment.substring(i, i + 3));
      }
    }

    // English words (3+ chars)
    final enRe = RegExp(r'[a-z]{3,}');
    for (final m in enRe.allMatches(lower)) {
      result.add(m.group(0)!);
    }

    return result;
  }

  // ===== Legacy AI tag parsing =====

  void _parseAiMemoryTags(String aiResponse, MemoryUpdateResult r) {
    final tagPattern = RegExp(r'\[MEM:(\w+):(\w+)=(.+?)\]');
    for (final m in tagPattern.allMatches(aiResponse)) {
      final memType = m.group(1)!;
      final key = m.group(2)!;
      final value = m.group(3)!;
      if (memType == 'task') {
        final parts = value.split('|');
        final taskTitle = parts[0].trim();
        final dateStr = parts.length > 1 ? parts[1].trim() : null;
        DateTime? dueDate;
        if (dateStr != null && dateStr.isNotEmpty) {
          dueDate = DateTime.tryParse(dateStr);
        }
        r.addTask(taskTitle, '', dueDate);
      } else if (memType == 'preference' && key == 'trendInterests') {
        r.addFact(content: '用户关注领域：$value', category: 'preference', key: 'trendInterests', confidence: 'high');
      } else {
        r.addFact(content: value, category: memType, key: key, confidence: 'high');
      }
    }
  }

  // ===== Write to cache with linking =====

  Future<void> _applyUpdates(MemoryUpdateResult result, List<MemoryEntry> existing) async {
    // 1. Add semantic facts with related_to → linked_memory_ids resolution
    for (final fact in result.newFacts) {
      final linkedIds = _matchRelatedTo(fact.relatedTo, existing);
      await _cache.addMemory(
        content: fact.content,
        memoryType: MemoryType.semantic,
        category: fact.category,
        key: fact.key,
        entities: EntityExtractor.extract(fact.content),
        linkedMemoryIds: linkedIds,
        confidence: fact.confidence,
        source: 'ai',
        sourceDetail: 'Instructor提取',
      );
    }

    // 2. Add episodic summary
    if (result.episodicSummary != null) {
      await _cache.addMemory(
        content: result.episodicSummary!,
        memoryType: MemoryType.episodic,
        category: 'episodic',
        confidence: 'high',
        source: 'ai',
        sourceDetail: '对话总结',
      );
    }

    // 3. Add procedural actions
    for (final action in result.proceduralActions) {
      final content = action.outcome.isNotEmpty
          ? 'Agent执行: ${action.action} — 结果: ${action.outcome}'
          : 'Agent执行: ${action.action}';
      await _cache.addMemory(
        content: content,
        memoryType: MemoryType.procedural,
        category: 'procedural',
        confidence: 'high',
        source: 'ai',
        sourceDetail: 'Agent行为记录',
      );
    }

    // 4. Legacy: tasks still go through old path (backward compat)
    for (final task in result.newTasks) {
      await _cache.addTask(task);
    }
  }

  // ===== Time hint parsing =====

  DateTime? _parseTimeHint(String input) {
    final now = DateTime.now();
    if (input.contains('明天')) return now.add(const Duration(days: 1));
    if (input.contains('后天')) return now.add(const Duration(days: 2));
    if (input.contains('今天')) return now;

    final weekMatch = RegExp(r'下周([一二三四五六日])').firstMatch(input);
    if (weekMatch != null) {
      final dayMap = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7};
      final target = dayMap[weekMatch.group(1)] ?? 1;
      final daysUntil = (target - now.weekday + 7) % 7;
      return now.add(Duration(days: daysUntil == 0 ? 7 : daysUntil));
    }
    if (input.contains('下个月')) {
      return DateTime(now.year, now.month + 1, now.day > 28 ? 28 : now.day);
    }

    final mdMatch = RegExp(r'(\d{1,2})月(\d{1,2})[日号]').firstMatch(input);
    if (mdMatch != null) {
      final month = int.tryParse(mdMatch.group(1)!);
      final day = int.tryParse(mdMatch.group(2)!);
      if (month != null && day != null) {
        var date = DateTime(now.year, month, day);
        if (date.isBefore(now)) date = DateTime(now.year + 1, month, day);
        return date;
      }
    }

    final timeMatch = RegExp(r'(\d{1,2})[点:时](\d{0,2})?[分]?').firstMatch(input);
    if (timeMatch != null) {
      final hour = int.tryParse(timeMatch.group(1)!) ?? 9;
      final minute = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
      var date = DateTime(now.year, now.month, now.day, hour, minute);
      if (date.isBefore(now)) date = date.add(const Duration(days: 1));
      return date;
    }
    return null;
  }
}

// ===== Result types =====

class _FactItem {
  _FactItem({
    required this.content,
    required this.category,
    this.key,
    this.confidence = 'medium',
    this.relatedTo = const [],
  });
  final String content;
  final String category;
  final String? key;
  final String confidence;
  final List<String> relatedTo;
}

class _ProceduralAction {
  _ProceduralAction({required this.action, this.outcome = ''});
  final String action;
  final String outcome;
}

class MemoryUpdateResult {
  final List<_FactItem> newFacts = [];
  final List<_ProceduralAction> proceduralActions = [];
  String? episodicSummary;

  // Old-format backward compat
  final Map<String, String> updates = {};
  final Map<String, _PendingItem> pending = {};
  final List<Map<String, dynamic>> newTasks = [];
  int _seq = 0;

  void addFact({
    required String content,
    required String category,
    String? key,
    String confidence = 'medium',
    List<String>? relatedTo,
  }) {
    newFacts.add(_FactItem(
      content: content,
      category: category,
      key: key,
      confidence: confidence,
      relatedTo: relatedTo ?? const [],
    ));
  }

  void addProceduralAction(String action, String outcome) {
    proceduralActions.add(_ProceduralAction(action: action, outcome: outcome));
  }

  // Old API
  void add(String type, String key, String value) {
    addFact(content: value, category: type, key: key, confidence: 'high');
  }

  void addPending(String type, String key, String value, {String confidence = 'medium', String source = 'regex', String detail = ''}) {
    final mapKey = '$type:$key';
    if (updates.containsKey(mapKey) || pending.containsKey(mapKey)) return;
    pending[mapKey] = _PendingItem(type: type, key: key, value: value, confidence: confidence, source: source, detail: detail);
    _seq++;
  }

  void addTask(String title, String description, DateTime? dueDate) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final seq = ++_seq;
    newTasks.add({
      'id': 'task_${now}_$seq', 'type': 'task', 'key': 'task_${now}_$seq',
      'value': jsonEncode({'title': title, 'description': description, 'taskType': 'scheduled', 'intervalSeconds': 0}),
      'due_time': dueDate?.millisecondsSinceEpoch, 'status': 'pending',
      'created_at': now, 'updated_at': now, 'is_active': 1,
    });
  }

  bool get hasUpdates => newFacts.isNotEmpty || episodicSummary != null || proceduralActions.isNotEmpty || pending.isNotEmpty || newTasks.isNotEmpty;
  int get count => newFacts.length + pending.length + newTasks.length;
}

class _PendingItem {
  _PendingItem({required this.type, required this.key, required this.value, this.confidence = 'medium', this.source = 'regex', this.detail = ''});
  final String type, key, value, confidence, source, detail;
}
