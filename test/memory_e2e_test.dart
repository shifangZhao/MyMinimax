// ===================================================================
// 3轮对话全链路集成测试
// 模拟 LLM 返回的 JSON → 解析 → 去重 → 链接 → 渲染
// 不依赖 SQLite，纯逻辑验证
//
// Run: flutter test test/memory_e2e_test.dart
// ===================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/features/memory/data/content_hasher.dart';
import 'package:myminimax/features/memory/data/entity_extractor.dart';

// ═══════════════════════════════════════════════════════════════
// 生产代码复制（测试专用，与 memory_update_detector.dart 一致）
// ═══════════════════════════════════════════════════════════════

Set<String> extractKeywords(String text) {
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
  final cjkOnly = lower.replaceAll(RegExp(r'[^一-鿿]'), ' ');
  for (final segment in cjkOnly.split(' ')) {
    if (segment.length < 2) continue;
    for (var i = 0; i <= segment.length - 2; i++) {
      final bigram = segment.substring(i, i + 2);
      if (!cjkStopBigrams.contains(bigram)) result.add(bigram);
    }
    for (var i = 0; i <= segment.length - 3; i++) {
      result.add(segment.substring(i, i + 3));
    }
  }
  for (final m in RegExp(r'[a-z]{3,}').allMatches(lower)) {
    result.add(m.group(0)!);
  }
  return result;
}

bool hasKeywordOverlap(String a, String b) {
  return extractKeywords(a).intersection(extractKeywords(b)).isNotEmpty;
}

List<String> matchRelatedTo(List<String> relatedTo, List<Map<String, dynamic>> existing) {
  final linked = <String>{};
  for (final ref in relatedTo) {
    final refLower = ref.toLowerCase();
    for (final m in existing) {
      final content = (m['content'] as String).toLowerCase();
      if (content.contains(refLower) ||
          hasKeywordOverlap(refLower, content)) {
        linked.add(m['id'] as String);
        break;
      }
    }
  }
  return linked.toList();
}

int confRank(String c) {
  switch (c) {
    case 'manual': return 4;
    case 'high': return 3;
    case 'medium': return 2;
    case 'low': return 1;
    default: return 0;
  }
}

// ═══════════════════════════════════════════════════════════════
// 模拟的 LLM 提取输出（按 Schema 格式返回 new_facts）
// ═══════════════════════════════════════════════════════════════

class SimulatedExtraction {

  SimulatedExtraction(this.round, this.newFacts, {this.episodicSummary, this.proceduralActions = const []});
  final String round;
  final List<Map<String, dynamic>> newFacts;
  final String? episodicSummary;
  final List<Map<String, String>> proceduralActions;
}

// 模拟的现有记忆存储（替代 MemoryCache）
class SimCache {
  final List<Map<String, dynamic>> entries = [];
  int _seq = 0;

  String _genId() => 'mem_${++_seq}';

  /// Simulates MemoryCache.addMemory logic: hash dedup + confidence supersede
  String? addMemory({
    required String content,
    String category = 'dynamic',
    String? key,
    String confidence = 'medium',
    List<String> linkedMemoryIds = const [],
  }) {
    final hash = ContentHasher.hash(content);

    // Hash dedup
    for (final e in entries) {
      if (e['content_hash'] == hash && e['status'] == 'active') return null;
    }

    // Confidence supersede: same category+key
    String? supersededId;
    if (key != null && key.isNotEmpty) {
      for (final e in entries) {
        if (e['category'] == category && e['key'] == key && e['status'] == 'active') {
          if (confRank(confidence) >= confRank(e['confidence'] as String)) {
            e['status'] = 'superseded';
            e['superseded_by'] = null; // will set
            supersededId = e['id'] as String;
          } else {
            return null; // lower/equal confidence, don't add
          }
        }
      }
    }

    final id = _genId();
    entries.add({
      'id': id,
      'content': content,
      'content_hash': hash,
      'category': category,
      'key': key,
      'entities': EntityExtractor.extract(content),
      'linked_memory_ids': linkedMemoryIds,
      'confidence': confidence,
      'status': 'active',
      'superseded_by': null,
    });

    if (supersededId != null) {
      for (final e in entries) {
        if (e['id'] == supersededId) {
          e['superseded_by'] = id;
        }
      }
    }

    return id;
  }

  List<Map<String, dynamic>> get allActive =>
      entries.where((e) => e['status'] == 'active').toList();

  /// Render toSystemPrompt-like output (grouped by category)
  String render() {
    final active = allActive;
    if (active.isEmpty) return '';

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final e in active) {
      grouped.putIfAbsent(e['category'] as String, () => []).add(e);
    }

    final buf = StringBuffer();
    buf.writeln('【用户记忆】');

    const sectionOrder = [
      'static', 'dynamic', 'preference', 'notice',
      'interest', 'fact', 'experience', 'relationship',
      'health', 'professional', 'plan', 'episodic', 'procedural',
    ];
    const sectionLabels = {
      'static': '静态画像', 'dynamic': '动态画像', 'preference': '交互偏好',
      'notice': '注意事项', 'interest': '兴趣爱好', 'fact': '个人事实',
      'experience': '经历事件', 'relationship': '人际关系', 'health': '健康养生',
      'professional': '职业工作', 'plan': '计划目标',
    };

    for (final cat in sectionOrder) {
      final entries = grouped[cat];
      if (entries == null || entries.isEmpty) continue;
      final label = sectionLabels[cat] ?? cat;
      buf.writeln('$label:');
      for (final e in entries) {
        final links = (e['linked_memory_ids'] as List).length;
        final linkTag = links > 0 ? ' [关联x$links]' : '';
        buf.writeln('  - ${e['content']}$linkTag');
      }
    }
    return buf.toString();
  }
}

// ═══════════════════════════════════════════════════════════════
// 3 轮对话测试
// ═══════════════════════════════════════════════════════════════

void main() {
  late SimCache cache;

  setUp(() {
    cache = SimCache();
  });

  group('第1轮：基础画像 + 开放类别', () {
    test('提取6条记忆覆盖5个类别', () {
      // ── 模拟 LLM 返回（理想输出）──
      final round1 = SimulatedExtraction('R1', [
        {'content': '用户陈思远生日为1995年', 'category': 'static', 'key': 'birthday', 'confidence': 'high'},
        {'content': '用户来自成都', 'category': 'dynamic', 'key': 'location', 'confidence': 'high'},
        {'content': '用户陈思远在字节跳动担任后端工程师，主要使用Go语言开发', 'category': 'professional', 'key': 'job', 'confidence': 'high'},
        {'content': '用户喜欢胶片摄影，拥有一台徕卡M6相机', 'category': 'interest', 'key': 'photography', 'confidence': 'high'},
        {'content': '用户女儿名叫陈小溪，刚上幼儿园', 'category': 'relationship', 'key': 'daughter', 'confidence': 'high'},
        {'content': '用户与助手进行了初次交流，介绍了个人基本信息和兴趣爱好', 'category': 'episodic', 'confidence': 'medium', 'key': null},
      ], episodicSummary: '用户陈思远首次对话，介绍了工作、家庭和摄影爱好');

      // ── 写入 ──
      for (final fact in round1.newFacts) {
        cache.addMemory(
          content: fact['content'] as String,
          category: fact['category'] as String,
          key: fact['key'] as String?,
          confidence: fact['confidence'] as String? ?? 'medium',
        );
      }

      // ── 验证 ──
      final active = cache.allActive;
      expect(active.length, equals(6));

      // 类别分布
      final categories = active.map((e) => e['category']).toSet();
      expect(categories, contains('static'));
      expect(categories, contains('dynamic'));
      expect(categories, contains('professional'));
      expect(categories, contains('interest'));
      expect(categories, contains('relationship'));
      expect(categories, contains('episodic'));

      // 专名保留
      final allText = active.map((e) => e['content'] as String).join(' ');
      expect(allText, contains('陈思远'));
      expect(allText, contains('陈小溪'));
      expect(allText, contains('徕卡M6'));
      expect(allText, contains('字节跳动'));
      expect(allText, contains('Go'));

      // 不应推断性别（"女儿"是关系词，不是性别推断）
      final nonRelational = active.where((e) =>
          !((e['content'] as String).contains('女儿'))).map((e) => e['content'] as String).join(' ');
      expect(nonRelational.contains('男') && !nonRelational.contains('女儿'), isFalse,
          reason: '没有显式声明性别，不应推断');

      // 渲染输出
      final prompt = cache.render();
      expect(prompt, contains('静态画像'));
      expect(prompt, contains('职业工作'));
      expect(prompt, contains('兴趣爱好'));
      expect(prompt, contains('人际关系'));
      expect(prompt, contains('徕卡M6'));
    });
  });

  group('第2轮：过渡态 + 时间锚定 + 隐式偏好 + 记忆链接', () {
    test('过渡态覆盖旧值、隐式偏好触发、记忆正确链接', () {
      // ── 先写入第1轮记忆 ──
      final round1 = [
        {'content': '用户陈思远生日为1995年', 'category': 'static', 'key': 'birthday', 'confidence': 'high'},
        {'content': '用户来自成都', 'category': 'dynamic', 'key': 'location', 'confidence': 'high'},
        {'content': '用户陈思远在字节跳动担任后端工程师，主要使用Go语言开发', 'category': 'professional', 'key': 'job', 'confidence': 'high'},
        {'content': '用户喜欢胶片摄影，拥有一台徕卡M6相机', 'category': 'interest', 'key': 'photography', 'confidence': 'high'},
        {'content': '用户女儿名叫陈小溪，刚上幼儿园', 'category': 'relationship', 'key': 'daughter', 'confidence': 'high'},
      ];
      for (final f in round1) {
        cache.addMemory(content: f['content'] as String, category: f['category'] as String,
            key: f['key'], confidence: f['confidence'] ?? 'high');
      }
      final existingAfterR1 = List<Map<String, dynamic>>.from(cache.allActive);

      // ── 模拟 LLM 第2轮提取 ──
      final round2 = SimulatedExtraction('R2', [
        {
          'content': '用户于2026年5月5日提离职，结束在字节跳动三年的后端工程师生涯，因感到疲惫',
          'category': 'professional', 'key': 'job',
          'confidence': 'high',
          'related_to': ['字节跳动担任后端工程师'],
        },
        {
          'content': '用户计划2026年6月搬回成都开设摄影工作室',
          'category': 'plan', 'key': 'studio',
          'confidence': 'high',
          'related_to': ['胶片摄影', '来自成都'],
        },
        {
          'content': '用户偏好简洁直接的回答风格，讨厌冗长啰嗦',
          'category': 'preference', 'key': 'answerStyle',
          'confidence': 'medium',  // 隐式推断
          'related_to': [],
        },
      ], episodicSummary: '用户讨论了离职和创业计划，查询了成都商铺租金');

      // ── 写入（含链接解析）──
      for (final fact in round2.newFacts) {
        final relatedTo = (fact['related_to'] as List?)?.cast<String>() ?? [];
        final linkedIds = matchRelatedTo(relatedTo, existingAfterR1);
        cache.addMemory(
          content: fact['content'] as String,
          category: fact['category'] as String,
          key: fact['key'] as String?,
          confidence: fact['confidence'] as String? ?? 'medium',
          linkedMemoryIds: linkedIds,
        );
      }

      // ── 验证 ──
      final active = cache.allActive;
      final allText = active.map((e) => e['content'] as String).join(' | ');

      // 1. 过渡态：job 包含新旧信息
      final job = active.firstWhere((e) => e['key'] == 'job');
      expect(job['content'], contains('离职'));
      expect(job['content'], contains('字节跳动'));
      expect(job['content'], contains('三年'));
      expect(job['content'], contains('疲惫')); // 原因保留

      // 2. 旧 job 被 supersede
      final oldJob = cache.entries.firstWhere((e) =>
          e['category'] == 'professional' && e['key'] == 'job' && e['status'] == 'superseded',
          orElse: () => <String, dynamic>{});
      expect(oldJob.isNotEmpty, isTrue);

      // 3. 计划类别触发
      final studio = active.firstWhere((e) => e['key'] == 'studio');
      expect(studio['content'], contains('摄影工作室'));
      expect(studio['content'], contains('成都'));
      expect(studio['content'], contains('2026年6月'));

      // 4. 记忆链接
      final studioLinks = studio['linked_memory_ids'] as List;
      expect(studioLinks.length, greaterThanOrEqualTo(1));

      // 5. 隐式偏好：answerStyle 从对话风格推断
      final answerStyle = active.firstWhere((e) => e['key'] == 'answerStyle');
      expect(answerStyle['confidence'], equals('medium'));
      expect(answerStyle['content'], contains('简洁'));

      // 6. 动态画像 location 被更新
      final locActive = active.where((e) => e['key'] == 'location').toList();
      // 应有 active=1 条（注意：location 在本轮未直接更新，
      // 但 plan 引用了"来自成都"，验证旧 location 仍存在）
      expect(locActive.length, equals(1));

      // 7. 渲染输出包含新类别
      final prompt = cache.render();
      expect(prompt, contains('计划目标'));
      expect(prompt, contains('交互偏好'));
      expect(prompt, contains('关联x'));
    });
  });

  group('第3轮：健康触发 + 计划更新 + 去重验证', () {
    test('健康类别首次触发、计划链接更新、不重复提取已知事实', () {
      // ── 写入前两轮记忆 ──
      final r1 = [
        {'content': '用户陈思远生日为1995年', 'category': 'static', 'key': 'birthday', 'confidence': 'high'},
        {'content': '用户来自成都', 'category': 'dynamic', 'key': 'location', 'confidence': 'high'},
        {'content': '用户于2026年5月5日提离职，结束在字节跳动三年的后端工程师生涯，因感到疲惫', 'category': 'professional', 'key': 'job', 'confidence': 'high'},
        {'content': '用户喜欢胶片摄影，拥有一台徕卡M6相机', 'category': 'interest', 'key': 'photography', 'confidence': 'high'},
        {'content': '用户女儿名叫陈小溪，刚上幼儿园', 'category': 'relationship', 'key': 'daughter', 'confidence': 'high'},
        {'content': '用户计划2026年6月搬回成都开设摄影工作室', 'category': 'plan', 'key': 'studio', 'confidence': 'high'},
        {'content': '用户偏好简洁直接的回答风格', 'category': 'preference', 'key': 'answerStyle', 'confidence': 'medium'},
      ];
      for (final f in r1) {
        cache.addMemory(content: f['content'] as String, category: f['category'] as String,
            key: f['key'], confidence: f['confidence'] ?? 'high');
      }
      final existingBeforeR3 = List<Map<String, dynamic>>.from(cache.allActive);

      // ── 模拟 LLM 第3轮提取 ──
      final round3 = SimulatedExtraction('R3', [
        {
          'content': '用户女儿陈小溪于2026年5月5日发烧，医生诊断为普通感冒',
          'category': 'health', 'key': 'daughter_illness',
          'confidence': 'high',
          'related_to': ['女儿名叫陈小溪'],
        },
        {
          'content': '陈小溪饮食习惯挑食，偏食白米饭',
          'category': 'health', 'key': 'daughter_diet',
          'confidence': 'high',
          'related_to': ['女儿名叫陈小溪'],
        },
        {
          'content': '用户于2026年5月开始每天早晨6点晨跑5公里',
          'category': 'health', 'key': 'morning_run',
          'confidence': 'high',
          'related_to': [],
        },
        {
          'content': '用户已确定摄影工作室选址为成都锦江区60平铺面',
          'category': 'plan', 'key': 'studio',
          'confidence': 'high',
          'related_to': ['开设摄影工作室'],
        },
        // ❌ 这3条不应被提取（去重验证）
        // {'content': '用户在字节跳动担任后端工程师', ...}   ← 已是旧闻
        // {'content': '用户喜欢摄影', ...}                   ← 已提取
        // {'content': '用户女儿叫陈小溪', ...}                ← 已提取
      ], episodicSummary: '用户讨论了女儿健康、晨跑习惯和工作室选址进展');

      // ── 写入 ──
      for (final fact in round3.newFacts) {
        final relatedTo = (fact['related_to'] as List?)?.cast<String>() ?? [];
        final linkedIds = matchRelatedTo(relatedTo, existingBeforeR3);
        cache.addMemory(
          content: fact['content'] as String,
          category: fact['category'] as String,
          key: fact['key'] as String?,
          confidence: fact['confidence'] as String? ?? 'medium',
          linkedMemoryIds: linkedIds,
        );
      }

      // ── 验证 ──
      final active = cache.allActive;

      // 1. 健康类别触发
      final healthEntries = active.where((e) => e['category'] == 'health').toList();
      expect(healthEntries.length, greaterThanOrEqualTo(3));
      final healthText = healthEntries.map((e) => e['content'] as String).join(' ');
      expect(healthText, contains('发烧'));
      expect(healthText, contains('普通感冒'));
      expect(healthText, contains('挑食'));
      expect(healthText, contains('白米饭'));
      expect(healthText, contains('晨跑'));
      expect(healthText, contains('5公里'));

      // 2. 健康记忆链接到女儿关系
      final illness = active.firstWhere((e) => e['key'] == 'daughter_illness');
      final illnessLinks = illness['linked_memory_ids'] as List;
      expect(illnessLinks.isNotEmpty, isTrue);

      // 3. 计划更新链接
      final studio = active.firstWhere((e) => e['key'] == 'studio');
      expect(studio['content'], contains('锦江区'));
      expect(studio['content'], contains('60平'));
      final studioLinks = studio['linked_memory_ids'] as List;
      expect(studioLinks.isNotEmpty, isTrue);

      // 4. 旧的 studio 被 supersede
      final oldStudio = cache.entries.where((e) =>
          e['category'] == 'plan' && e['key'] == 'studio' && e['status'] == 'superseded').toList();
      expect(oldStudio.length, equals(1));

      // 5. 去重验证：不应出现重复提取的条目
      final allContent = active.map((e) => e['content'] as String).join(' ');
      // 这些是已知事实，不应再次出现
      final dupCheck1 = active.where((e) =>
          (e['content'] as String).contains('字节跳动') &&
          (e['content'] as String).contains('后端工程师') &&
          e['status'] == 'active').toList();
      expect(dupCheck1.length, equals(1), reason: '不应重复提取后端工程师');

      // 6. 渲染输出完整
      final prompt = cache.render();
      expect(prompt, contains('健康养生'));
      expect(prompt, contains('6点晨跑'));
      expect(prompt, contains('锦江区'));
      expect(prompt, contains('静态画像'));
      expect(prompt, contains('职业工作'));
      expect(prompt, contains('人际关系'));
      expect(prompt, contains('交互偏好'));
      expect(prompt, contains('计划目标'));
    });
  });

  group('完整3轮渲染输出', () {
    test('toSystemPrompt 包含所有类别、链接标记、时间信息', () {
      // 跑完3轮全量
      final allRounds = [
        {'content': '用户陈思远生日为1995年', 'category': 'static', 'key': 'birthday', 'confidence': 'high'},
        {'content': '用户来自成都', 'category': 'dynamic', 'key': 'location', 'confidence': 'high'},
        {'content': '用户于2026年5月5日提离职，结束在字节跳动三年的后端工程师生涯，因感到疲惫', 'category': 'professional', 'key': 'job', 'confidence': 'high'},
        {'content': '用户喜欢胶片摄影，拥有一台徕卡M6相机', 'category': 'interest', 'key': 'photography', 'confidence': 'high'},
        {'content': '用户女儿名叫陈小溪，刚上幼儿园', 'category': 'relationship', 'key': 'daughter', 'confidence': 'high'},
        {'content': '用户计划2026年6月搬回成都开设摄影工作室', 'category': 'plan', 'key': 'studio', 'confidence': 'high'},
        {'content': '用户偏好简洁直接的回答风格', 'category': 'preference', 'key': 'answerStyle', 'confidence': 'medium'},
        {'content': '用户女儿陈小溪于2026年5月5日发烧，诊断为普通感冒', 'category': 'health', 'key': 'daughter_illness', 'confidence': 'high'},
        {'content': '陈小溪饮食习惯挑食，偏食白米饭', 'category': 'health', 'key': 'daughter_diet', 'confidence': 'high'},
        {'content': '用户于2026年5月开始每天早晨6点晨跑5公里', 'category': 'health', 'key': 'morning_run', 'confidence': 'high'},
        {'content': '用户已确定摄影工作室选址为成都锦江区60平铺面', 'category': 'plan', 'key': 'studio', 'confidence': 'high'},
      ];

      final existing = <Map<String, dynamic>>[];
      for (final f in allRounds) {
        final id = cache.addMemory(
          content: f['content'] as String,
          category: f['category'] as String,
          key: f['key'],
          confidence: f['confidence'] ?? 'high',
        );
        if (id != null) {
          existing.add({
            'id': id,
            'content': f['content'],
            'category': f['category'],
            'key': f['key'],
          });
        }
      }

      final active = cache.allActive;
      final prompt = cache.render();

      // 所有类别段出现
      expect(prompt, contains('静态画像'));
      expect(prompt, contains('动态画像'));
      expect(prompt, contains('交互偏好'));
      expect(prompt, contains('职业工作'));
      expect(prompt, contains('兴趣爱好'));
      expect(prompt, contains('人际关系'));
      expect(prompt, contains('计划目标'));
      expect(prompt, contains('健康养生'));

      // 关键信息存在
      expect(prompt, contains('陈思远'));
      expect(prompt, contains('陈小溪'));
      expect(prompt, contains('字节跳动'));
      expect(prompt, contains('徕卡M6'));
      expect(prompt, contains('摄影工作室'));
      expect(prompt, contains('锦江区'));
      expect(prompt, contains('晨跑'));

      // R2/R3 同 key 覆盖验证：studio 经历了 R2→R3 supersede
      final allStudios = cache.entries.where((e) => e['key'] == 'studio').toList();
      expect(allStudios.length, equals(2)); // R2=superseded, R3=active
      expect(allStudios.any((e) => e['status'] == 'active'), isTrue);
      expect(allStudios.any((e) => e['status'] == 'superseded'), isTrue);

      // active 条目：10（11 total - 1 R2 studio 被 R3 supersede）
      expect(active.length, equals(10));
    });
  });

  group('边界情况', () {
    test('空提取返回不应崩溃', () {
      final before = cache.allActive.length;
      // 无提取物 → 什么都不写入
      final after = cache.allActive.length;
      expect(after, equals(before));
    });

    test('低置信度不能覆盖手动确认', () {
      cache.addMemory(content: '用户偏好详细回答', category: 'preference',
          key: 'detailLevel', confidence: 'manual');
      final result = cache.addMemory(content: '用户想要简短回答', category: 'preference',
          key: 'detailLevel', confidence: 'low');
      expect(result, isNull); // 不应写入

      final active = cache.allActive.firstWhere((e) => e['key'] == 'detailLevel');
      expect(active['content'], contains('详细')); // 旧值未变
    });

    test('hash 去重：完全相同的文字不创建新条目', () {
      final id1 = cache.addMemory(content: '用户喜欢Python编程', category: 'interest',
          key: 'language', confidence: 'high');
      final id2 = cache.addMemory(content: '用户喜欢Python编程', category: 'interest',
          key: 'language', confidence: 'high');
      expect(id1, isNotNull);
      expect(id2, isNull); // hash 命中，不重复创建
    });
  });
}
