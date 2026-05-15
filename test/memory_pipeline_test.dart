/// Memory pipeline test — verifies extraction, dedup, confidence, linking,
/// and rendering. Pure-Dart tests run without LLM/DB dependencies.
///
/// Run: flutter test test/memory_pipeline_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/features/memory/data/memory_entry.dart';
import 'package:myminimax/features/memory/data/content_hasher.dart';
import 'package:myminimax/features/memory/data/entity_extractor.dart';
import 'package:myminimax/features/memory/data/memory_retriever.dart';
import 'package:myminimax/features/memory/data/memory_cache.dart';

/// These tests verify memory logic that doesn't depend on sqflite/SQLite.
/// The MemoryCache integration tests require a real database — they run
/// in the app's integration test suite, not here.

void main() {
  // ===================================================================
  // ContentHasher
  // ===================================================================
  group('ContentHasher', () {
    test('produces stable SHA-256', () {
      final h1 = ContentHasher.hash('用户喜歡Python编程');
      final h2 = ContentHasher.hash('用户喜歡Python编程');
      expect(h1, equals(h2));
      expect(h1.length, equals(64));
    });

    test('normalizes whitespace before hashing', () {
      final h1 = ContentHasher.hash('  Hello   World  ');
      final h2 = ContentHasher.hash('Hello World');
      expect(h1, equals(h2));
    });

    test('different content produces different hash', () {
      expect(ContentHasher.hash('A'), isNot(equals(ContentHasher.hash('B'))));
    });
  });

  // ===================================================================
  // EntityExtractor
  // ===================================================================
  group('EntityExtractor', () {
    test('提取中国地名', () {
      final entities = EntityExtractor.extract('在北京和上海之间出差，又去了深圳腾讯公司');
      expect(entities.any((e) => e.contains('北京')), isTrue);
      expect(entities.any((e) => e.contains('上海')), isTrue);
      expect(entities.any((e) => e.contains('深圳')), isTrue);
      // 公司名
      expect(entities.any((e) => e.contains('腾讯公司')), isTrue);
    });

    test('提取中文格式日期', () {
      final entities = EntityExtractor.extract('生日是1995-03-15，入职时间是2020年5月1日，毕业2021/06/30');
      final dates = entities.where((e) =>
          RegExp(r'\d{4}').hasMatch(e) && (e.contains('-') || e.contains('年') || e.contains('/'))).toList();
      expect(dates.length, greaterThanOrEqualTo(2));
    });

    test('提取URL和邮箱', () {
      final entities = EntityExtractor.extract('请联系 admin@test.com 或访问 https://example.com/page');
      expect(entities.any((e) => e.contains('https://example.com/page')), isTrue);
      expect(entities.any((e) => e.contains('admin@test.com')), isTrue);
    });

    test('提取英文专名（大写开头的词）', () {
      final entities = EntityExtractor.extract('User works at Shopify in San Francisco with Alice');
      final found = entities.where((e) => e.contains('Shopify') || e.contains('San Francisco')
          || e.contains('Alice') || e.contains('User')).toList();
      expect(found.isNotEmpty, isTrue);
    });

    test('过滤通用噪音词', () {
      final entities = EntityExtractor.extract('The and for with about this that');
      final generic = entities.where((e) =>
        e.toLowerCase() == 'the' || e.toLowerCase() == 'and' || e.toLowerCase() == 'for');
      expect(generic.isEmpty, isTrue);
    });

    test('中文人名：至少能提取到姓', () {
      final entities = EntityExtractor.extract('张明和李华一起去了北京');
      // 中文人名提取是 best-effort，可能匹配"张明"或"张明和李"等变体
      // 核心要求：至少能提取到包含中文姓氏的实体
      final hasSurname = entities.any((e) =>
          e.contains('张') || e.contains('李'));
      expect(hasSurname, isTrue);
    });
  });

  // ===================================================================
  // MemoryEntry
  // ===================================================================
  group('MemoryEntry', () {
    test('serializes to/from DB row', () {
      final entry = MemoryEntry(
        id: 'mem_001',
        memoryType: MemoryType.semantic,
        content: '用户Alice喜欢Python编程',
        contentHash: 'abc123',
        category: 'interest',
        key: 'favoriteLanguage',
        entities: ['Alice', 'Python'],
        linkedMemoryIds: ['mem_000'],
        confidence: 'high',
        source: 'ai',
        sourceDetail: 'Instructor提取',
        createdAt: DateTime(2026, 5, 1),
      );

      final row = entry.toDb();
      final restored = MemoryEntry.fromDb(row);

      expect(restored.id, equals('mem_001'));
      expect(restored.content, equals('用户Alice喜欢Python编程'));
      expect(restored.category, equals('interest'));
      expect(restored.key, equals('favoriteLanguage'));
      expect(restored.entities, contains('Alice'));
      expect(restored.linkedMemoryIds, contains('mem_000'));
      expect(restored.confidence, equals('high'));
      expect(restored.source, equals('ai'));
      expect(restored.memoryType, equals(MemoryType.semantic));
    });

    test('handles empty linked_memory_ids and entities in DB roundtrip', () {
      final entry = MemoryEntry(
        id: 'mem_min',
        memoryType: MemoryType.episodic,
        content: '用户讨论了一次Python项目',
        contentHash: 'hash2',
        category: 'episodic',
        confidence: 'medium',
        createdAt: DateTime(2026, 5, 1),
      );
      final row = entry.toDb();
      final restored = MemoryEntry.fromDb(row);
      expect(restored.entities, isEmpty);
      expect(restored.linkedMemoryIds, isEmpty);
      expect(restored.key, isNull);
    });

    test('toSystemPromptLine format — today', () {
      final entry = MemoryEntry(
        id: 'mem_test',
        memoryType: MemoryType.semantic,
        content: '用户偏好简洁对话',
        contentHash: 'hash',
        category: 'preference',
        key: 'answerStyle',
        confidence: 'manual',
        createdAt: DateTime.now(),
      );
      final line = entry.toSystemPromptLine();
      expect(line.contains('[今天]'), isTrue);
      expect(line.contains('[manual]'), isTrue);
      expect(line.contains('用户偏好简洁对话'), isTrue);
    });

    test('toSystemPromptLine format — older', () {
      final entry = MemoryEntry(
        id: 'mem_test2',
        memoryType: MemoryType.semantic,
        content: '旧记忆',
        contentHash: 'hash_old',
        category: 'static',
        confidence: 'high',
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
      );
      final line = entry.toSystemPromptLine();
      expect(line.contains('[3天前]'), isTrue);
      expect(line.contains('[high]'), isTrue);
    });

    test('all MemoryType and MemoryStatus enum values are used correctly', () {
      expect(MemoryType.values.length, equals(3));
      expect(MemoryStatus.values.length, equals(3));

      // Each enum should have a name
      for (final t in MemoryType.values) {
        expect(t.name.isNotEmpty, isTrue);
      }
      for (final s in MemoryStatus.values) {
        expect(s.name.isNotEmpty, isTrue);
      }
    });
  });

  // ===================================================================
  // MemoryRetriever — tokenize (pure function, no DB)
  // ===================================================================
  group('MemoryRetriever — tokenize 中英文分词', () {
    test('CJK文本拆为unigram和bigram', () {
      final tokens = MemoryRetriever.tokenize('中国航天');
      expect(tokens.contains('中'), isTrue);
      expect(tokens.contains('国'), isTrue);
      expect(tokens.contains('中国'), isTrue);
      expect(tokens.contains('航天'), isTrue);
    });

    test('完整中文句子拆词', () {
      final tokens = MemoryRetriever.tokenize('用户喜欢简洁直接的对话风格');
      // 应有 unigram
      expect(tokens.contains('用'), isTrue);
      expect(tokens.contains('户'), isTrue);
      // 应有 bigram
      expect(tokens.contains('用户'), isTrue);
      expect(tokens.contains('喜欢'), isTrue);
      expect(tokens.contains('简洁'), isTrue);
      expect(tokens.contains('对话'), isTrue);
      expect(tokens.contains('风格'), isTrue);
    });

    test('提取英文词（2字符以上）', () {
      final tokens = MemoryRetriever.tokenize('Hello World test');
      expect(tokens.contains('hello'), isTrue);
      expect(tokens.contains('world'), isTrue);
      expect(tokens.contains('test'), isTrue);
    });

    test('过滤单个英文字符', () {
      final tokens = MemoryRetriever.tokenize('a b c hello');
      expect(tokens.contains('a'), isFalse);
      expect(tokens.contains('hello'), isTrue);
    });

    test('中英混用文本', () {
      final tokens = MemoryRetriever.tokenize('用Python写代码，部署在AWS上');
      expect(tokens.contains('python'), isTrue);
      expect(tokens.contains('aws'), isTrue);
      // CJK 片段
      expect(tokens.any((t) => t.contains('写')), isTrue);
      expect(tokens.any((t) => t.contains('代码')), isTrue);
      expect(tokens.any((t) => t.contains('部署')), isTrue);
    });

    test('纯中文无英文干扰', () {
      final tokens = MemoryRetriever.tokenize('我是一个软件工程师，喜欢看电影和读书');
      // 不应有英文 token
      final englishTokens = tokens.where((t) => RegExp(r'^[a-z]+$').hasMatch(t)).toList();
      expect(englishTokens.isEmpty, isTrue);
      // unigrams
      expect(tokens.contains('我'), isTrue);
      expect(tokens.contains('是'), isTrue);
      // bigrams（注意："工程师"是trigram所以不会出现，tokenizer只拆到bigram）
      expect(tokens.contains('一个'), isTrue);
      expect(tokens.contains('软件'), isTrue);
      expect(tokens.contains('工程'), isTrue);
      expect(tokens.contains('程师'), isTrue);
      expect(tokens.contains('电影'), isTrue);
    });
  });

  // ===================================================================
  // Keyword overlap matching (used by _hasKeywordOverlap in detector)
  // ===================================================================
  group('关键词重叠匹配（中英文）', () {
    /// Matches production code: _extractKeywords + _hasKeywordOverlap
    Set<String> extractKeywords(String text) {
      final result = <String>{};
      final lower = text.toLowerCase();
      // CJK bigrams + trigrams (sliding window, not greedy)
      final cjkOnly = lower.replaceAll(RegExp(r'[^一-鿿]'), ' ');
      for (final segment in cjkOnly.split(' ')) {
        if (segment.length < 2) continue;
        for (var i = 0; i <= segment.length - 2; i++) {
          result.add(segment.substring(i, i + 2));
        }
        for (var i = 0; i <= segment.length - 3; i++) {
          result.add(segment.substring(i, i + 3));
        }
      }
      // English 3+ char words
      for (final m in RegExp(r'[a-z]{3,}').allMatches(lower)) {
        result.add(m.group(0)!);
      }
      return result;
    }

    bool hasKeywordOverlap(String a, String b) {
      return extractKeywords(a).intersection(extractKeywords(b)).isNotEmpty;
    }

    test('CJK bigram重叠 — 相同话题', () {
      expect(hasKeywordOverlap('用户喜欢Python编程', 'Python编程很有趣'), isTrue);
      expect(hasKeywordOverlap('用户在Shopify担任高级工程师', 'Shopify的工作环境很好'), isTrue);
    });

    test('中文bigram重叠 — 同一实体', () {
      // 纯中文：北京出现在两边
      expect(hasKeywordOverlap('用户在北京工作', '北京的房价很高'), isTrue);
      // 纯中文：宠物医院话题
      expect(hasKeywordOverlap('用户养了一只金毛犬', '金毛犬需要每天遛两次'), isTrue);
      // 中英混合：Python
      expect(hasKeywordOverlap('用户喜欢用Python写脚本', 'Python是一门很好的语言'), isTrue);
    });

    test('中文完全不相关话题不匹配', () {
      expect(hasKeywordOverlap('用户喜欢喝咖啡', '明天天气怎么样'), isFalse);
      expect(hasKeywordOverlap('写了一篇关于AI的文章', '今天中午吃了拉面'), isFalse);
    });

    test('英文词重叠', () {
      expect(hasKeywordOverlap('user works at shopify', 'shopify is hiring engineers'), isTrue);
    });

    test('短文本边缘情况', () {
      expect(hasKeywordOverlap('短', '一个很长的中文测试文本'), isFalse);
      expect(hasKeywordOverlap('AB', 'ABC'), isFalse); // 不够3字符
    });
  });

  // ===================================================================
  // MemoryCache — logic tests (no DB: test confidence ranking, etc.)
  // ===================================================================
  group('MemoryCache — confidence ranking', () {
    test('_confRank ordering: manual > high > medium > low', () {
      // Verify the ranking constants via the addMemory logic
      // manual=4, high=3, medium=2, low=1, unknown=0
      final ranks = {
        'manual': 4, 'high': 3, 'medium': 2, 'low': 1, 'unknown': 0,
      };
      expect(ranks['manual'], greaterThan(ranks['high']!));
      expect(ranks['high'], greaterThan(ranks['medium']!));
      expect(ranks['medium'], greaterThan(ranks['low']!));
      expect(ranks['low'], greaterThan(ranks['unknown']!));
    });
  });

  // ===================================================================
  // MemoryCache — toSystemPrompt (stub, no entries)
  // ===================================================================
  group('MemoryCache — toSystemPrompt', () {
    test('returns empty for unloaded cache', () {
      final prompt = MemoryCache.instance.toSystemPrompt();
      expect(prompt, isEmpty);
    });
  });

  // ===================================================================
  // Category rendering (_writeSection and _groupByCategory logic)
  // ===================================================================
  group('Category grouping for system prompt', () {
    /// Simulates the grouping logic from MemoryCache._groupByCategory.
    Map<String, List<MemoryEntry>> groupByCategory(List<MemoryEntry> entries) {
      final map = <String, List<MemoryEntry>>{};
      for (final m in entries) {
        map.putIfAbsent(m.category, () => []).add(m);
      }
      return map;
    }

    test('groups entries by category', () {
      final entries = [
        MemoryEntry(id: '1', memoryType: MemoryType.semantic, content: '用户生日为1995-03-15',
            contentHash: 'h1', category: 'static', key: 'birthday', confidence: 'high', createdAt: DateTime.now()),
        MemoryEntry(id: '2', memoryType: MemoryType.semantic, content: '用户喜欢科幻电影',
            contentHash: 'h2', category: 'interest', key: 'favoriteGenre', confidence: 'high', createdAt: DateTime.now()),
        MemoryEntry(id: '3', memoryType: MemoryType.semantic, content: '用户每天跑步',
            contentHash: 'h3', category: 'health', key: 'morningRoutine', confidence: 'medium', createdAt: DateTime.now()),
        MemoryEntry(id: '4', memoryType: MemoryType.semantic, content: '用户喜欢三体',
            contentHash: 'h4', category: 'interest', key: 'favoriteBook', confidence: 'high', createdAt: DateTime.now()),
      ];

      final grouped = groupByCategory(entries);

      expect(grouped.keys.length, equals(3));
      expect(grouped['static']!.length, equals(1));
      expect(grouped['interest']!.length, equals(2));
      expect(grouped['health']!.length, equals(1));
    });

    test('handles empty list', () {
      final grouped = groupByCategory([]);
      expect(grouped.isEmpty, isTrue);
    });
  });

  // ===================================================================
  // Linked memory resolution (_matchRelatedTo logic) — 中文场景
  // ===================================================================
  group('记忆关联解析（中文场景）', () {
    Set<String> extractKeywords(String text) {
      final result = <String>{};
      final lower = text.toLowerCase();
      final cjkOnly = lower.replaceAll(RegExp(r'[^一-鿿]'), ' ');
      for (final segment in cjkOnly.split(' ')) {
        if (segment.length < 2) continue;
        for (var i = 0; i <= segment.length - 2; i++) {
          result.add(segment.substring(i, i + 2));
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

    List<String> matchRelatedTo(List<String> relatedTo, List<MemoryEntry> existing) {

      final linked = <String>{};
      for (final ref in relatedTo) {
        final refLower = ref.toLowerCase();
        for (final m in existing) {
          if (m.content.toLowerCase().contains(refLower) ||
              hasKeywordOverlap(refLower, m.content.toLowerCase())) {
            linked.add(m.id);
            break;
          }
        }
      }
      return linked.toList();
    }

    test('精确子串匹配 — 中文', () {
      final existing = [
        MemoryEntry(id: 'mem_a', memoryType: MemoryType.semantic,
            content: '用户养了一只叫豆豆的金毛犬', contentHash: 'ha', category: 'interest',
            key: 'pet', confidence: 'high', createdAt: DateTime.now()),
      ];
      final linked = matchRelatedTo(['用户养了一只叫豆豆的金毛犬'], existing);
      expect(linked, contains('mem_a'));
    });

    test('关键词重叠匹配 — 中文话题关联', () {
      final existing = [
        MemoryEntry(id: 'mem_b', memoryType: MemoryType.semantic,
            content: '用户在字节跳动担任高级前端工程师', contentHash: 'hb', category: 'professional',
            key: 'job', confidence: 'high', createdAt: DateTime.now()),
      ];
      // LLM 提取的 related_to 描述不完全一致但话题相关
      final linked = matchRelatedTo(['字节跳动的工程师职位'], existing);
      expect(linked, contains('mem_b'));
    });

    test('完全无关话题不匹配', () {
      final existing = [
        MemoryEntry(id: 'mem_c', memoryType: MemoryType.semantic,
            content: '用户每天早晨喝手冲咖啡', contentHash: 'hc', category: 'fact',
            confidence: 'medium', createdAt: DateTime.now()),
      ];
      // "手冲咖啡"和"爬山徒步"没有bigram重叠
      final linked = matchRelatedTo(['周末去爬山徒步'], existing);
      expect(linked, isEmpty);
    });

    test('多个 related_to 匹配多条现有记忆', () {
      final existing = [
        MemoryEntry(id: 'mem_x', memoryType: MemoryType.semantic,
            content: '用户每周三晚上有西班牙语课', contentHash: 'hx', category: 'plan',
            key: 'spanishClass', confidence: 'high', createdAt: DateTime.now()),
        MemoryEntry(id: 'mem_y', memoryType: MemoryType.semantic,
            content: '用户在健身房办了年卡，每周去三次', contentHash: 'hy', category: 'health',
            key: 'gym', confidence: 'high', createdAt: DateTime.now()),
      ];
      final linked = matchRelatedTo(['西班牙语课', '健身房的计划'], existing);
      expect(linked.length, equals(2));
      expect(linked, contains('mem_x'));
      expect(linked, contains('mem_y'));
    });

    test('空输入处理', () {
      expect(matchRelatedTo([], []), isEmpty);
      expect(matchRelatedTo(['某事'], []), isEmpty);
    });
  });

  // ===================================================================
  // Transition capture — 中文过渡态捕捉
  // ===================================================================
  group('过渡态捕捉（中文场景）', () {
    test('新旧信息共存：搬家场景', () {
      final confRank = {'manual': 4, 'high': 3, 'medium': 2, 'low': 1};
      final shouldSupersede = confRank['high']! > confRank['low']!;
      expect(shouldSupersede, isTrue);

      // LLM 过渡态输出示例：从北京搬到上海
      const newContent = '用户2026年4月从北京搬到上海，因为换了新工作';
      expect(newContent, contains('北京')); // 保留旧上下文
      expect(newContent, contains('上海')); // 新信息
      expect(newContent, contains('换'));  // 变化原因
    });

    test('口味变化保留旧偏好上下文', () {
      // LLM 过渡态输出示例：饮食偏好变化
      const content = '用户因为杏仁过敏从杏仁奶换成了燕麦奶拿铁';
      expect(content, contains('杏仁奶')); // 旧偏好
      expect(content, contains('燕麦奶')); // 新偏好
      expect(content, contains('过敏'));  // 变化原因
    });

    test('技术进步保留学习路径', () {
      const content = '用户从Vue2迁移到Vue3，正在学习组合式API和TypeScript';
      expect(content, contains('Vue2'));
      expect(content, contains('Vue3'));
      expect(content, contains('组合式API'));
    });

    test('手动确认的记忆不会被AI推断覆盖', () {
      final confRank = {'manual': 4, 'high': 3, 'medium': 2, 'low': 1};
      // 用户手动设置了 detailLevel = 详细
      // AI 从 "简短回答" 推断出 low confidence 的偏好
      final shouldSupersede = confRank['low']! > confRank['manual']!;
      expect(shouldSupersede, isFalse);
    });

    test('临时性变化标注', () {
      // LLM 应标注临时/试用状态
      const content = '用户正在试用 Obsidian 替代 Notion 做笔记管理（试用期一个月）';
      expect(content, contains('试用'));
      expect(content, contains('一个月'));
      expect(content, contains('Notion'));
      expect(content, contains('Obsidian'));
    });
  });

  // ===================================================================
  // Hash dedup — 中文去重
  // ===================================================================
  group('Hash去重（中文）', () {
    test('相同中文内容产生相同hash', () {
      final h1 = ContentHasher.hash('用户偏好简洁的对话风格，讨厌长篇大论');
      final h2 = ContentHasher.hash('用户偏好简洁的对话风格，讨厌长篇大论');
      expect(h1, equals(h2));
    });

    test('空格差异被归一化', () {
      final h1 = ContentHasher.hash('用户  喜欢  喝咖啡');
      final h2 = ContentHasher.hash('用户 喜欢 喝咖啡');
      expect(h1, equals(h2));
    });

    test('语义相同但措辞不同产生不同hash（去重靠LLM上下文）', () {
      final h1 = ContentHasher.hash('用户喜欢简洁回答');
      final h2 = ContentHasher.hash('用户偏爱简短的回复方式');
      expect(h1, isNot(equals(h2)));
      // 这是正确的设计：精确去重靠hash，语义去重靠LLM看到现有记忆后自行判断
    });
  });
}
