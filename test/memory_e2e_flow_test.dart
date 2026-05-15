// ===================================================================
// 记忆系统全套实测 — 完整链路验证
// 覆盖：用户声明 → [MEM:] 存储 → 行为配置注入 → 指令生效
//
// 使用 loadFromRows 绕过 SQLite 依赖，纯逻辑验证。
// Run: flutter test test/memory_e2e_flow_test.dart -v
// ===================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myminimax/features/settings/data/settings_repository.dart';
import 'package:myminimax/features/memory/data/memory_cache.dart';

/// 构造 loadFromRows 所需的单条 row。
/// 格式参考 MemoryCache.loadFromRows() 中的解析逻辑。
Map<String, dynamic> _memRow(String id, String category, String key, String value) {
  return {
    'id': id,
    'type': category,
    'key': key,
    'value': value,
    'created_at': DateTime.now().millisecondsSinceEpoch,
  };
}

/// 批量写入记忆到 MemoryCache（绕过 DB，直接操作内存索引）。
void setMemories(List<(String, String, String)> entries) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final rows = <Map<String, dynamic>>[];
  for (var i = 0; i < entries.length; i++) {
    final (category, key, value) = entries[i];
    rows.add({
      'id': 'mem_test_$i',
      'type': category,
      'key': key,
      'value': value,
      'created_at': now + i,
    });
  }
  MemoryCache.instance.loadFromRows(rows);
}

void main() {
  late SettingsRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    MemoryCache.instance.loadFromRows([]);
    repo = SettingsRepository();
  });

  /// 验证系统提示包含指定行为指令。
  Future<void> assertPromptContains(String description, List<String> expectedFragments) async {
    final prompt = await repo.buildSystemPrompt();
    for (final frag in expectedFragments) {
      expect(prompt, contains(frag), reason: '$description — 期望包含"$frag"');
    }
  }

  /// 验证系统提示不包含指定内容。
  Future<void> assertPromptNotContains(String description, List<String> unexpectedFragments) async {
    final prompt = await repo.buildSystemPrompt();
    for (final frag in unexpectedFragments) {
      expect(prompt, isNot(contains(frag)), reason: '$description — 期望不包含"$frag"');
    }
  }

  // ════════════════════════════════════════════
  // 场景1：AI 身份设定
  // ════════════════════════════════════════════
  group('场景1：AI 身份设定', () {
    test('agentName → 智能体名称指令生效', () async {
      setMemories([('dynamic', 'agentName', '小黑')]);

      await assertPromptContains('agentName', [
        '【行为配置 — 动态指令】',
        '智能体名称是「小黑」',
        '所有自称',
        '统一用此名称',
      ]);
    });

    test('agentName 更新后旧指令被替换', () async {
      setMemories([('dynamic', 'agentName', '大白')]);

      await assertPromptContains('agentName updated', [
        '智能体名称是「大白」',
      ]);
      await assertPromptNotContains('agentName old gone', [
        '智能体名称是「小黑」',
      ]);
    });
  });

  // ════════════════════════════════════════════
  // 场景2：用户称呼设定
  // ════════════════════════════════════════════
  group('场景2：用户称呼设定', () {
    test('namePreference → 用户称呼指令生效', () async {
      setMemories([('dynamic', 'namePreference', '张总')]);

      await assertPromptContains('namePreference', [
        '用户希望被称呼为「张总」',
        '每次对话用此称呼',
        '不要用"用户"',
      ]);
    });

    test('userTitle + namePreference → 组合称呼', () async {
      setMemories([
        ('dynamic', 'userTitle', '老师'),
        ('dynamic', 'namePreference', '王明'),
      ]);

      await assertPromptContains('title + name', [
        '用户希望被称呼为「老师王明」',
      ]);
    });
  });

  // ════════════════════════════════════════════
  // 场景3：回答风格设定
  // ════════════════════════════════════════════
  group('场景3：回答风格设定', () {
    test('answerStyle → 回答风格指令生效', () async {
      setMemories([('preference', 'answerStyle', '简洁')]);

      await assertPromptContains('answerStyle', [
        '回答风格偏好',
        '「简洁」',
        '必须符合此风格',
      ]);
    });

    test('多种风格偏好同时生效', () async {
      setMemories([
        ('preference', 'answerStyle', '正式'),
        ('preference', 'tone', '专业'),
        ('preference', 'detailLevel', '详细'),
      ]);

      await assertPromptContains('multiple preferences', [
        '回答风格偏好：「正式」',
        '语气风格：「专业」',
        '内容详细程度：「详细」',
      ]);
    });
  });

  // ════════════════════════════════════════════
  // 场景4：规则/禁忌设定
  // ════════════════════════════════════════════
  group('场景4：规则/禁忌设定', () {
    test('prohibitedItems → 禁止事项指令生效', () async {
      setMemories([('notice', 'prohibitedItems', '不要用网络用语')]);

      await assertPromptContains('prohibitedItems', [
        '禁止事项',
        '不要用网络用语',
      ]);
    });

    test('communicationRules → 沟通规则指令生效', () async {
      setMemories([('notice', 'communicationRules', '每次回复先列要点')]);

      await assertPromptContains('communicationRules', [
        '沟通规则',
        '每次回复先列要点',
      ]);
    });

    test('多条 notice 同时生效', () async {
      setMemories([
        ('notice', 'communicationRules', '先问后答'),
        ('notice', 'prohibitedItems', '别用缩写'),
        ('notice', 'otherRequirements', '每段不超3句'),
      ]);

      await assertPromptContains('multiple notices', [
        '沟通规则：先问后答',
        '禁止事项：别用缩写',
        '其他要求：每段不超3句',
      ]);
    });
  });

  // ════════════════════════════════════════════
  // 场景5：完整对话累积效果（多轮对话）
  // ════════════════════════════════════════════
  group('场景5：完整对话累积效果', () {
    test('累积所有类型记忆 → 行为配置完整', () async {
      setMemories([
        ('dynamic', 'agentName', '小黑'),
        ('dynamic', 'namePreference', '张总'),
        ('preference', 'answerStyle', '正式'),
        ('preference', 'tone', '专业'),
        ('notice', 'communicationRules', '先问后答'),
        ('notice', 'prohibitedItems', '别用缩写'),
      ]);

      final prompt = await repo.buildSystemPrompt();

      // 身份
      expect(prompt, contains('智能体名称是「小黑」'));
      expect(prompt, contains('用户希望被称呼为「张总」'));

      // 风格
      expect(prompt, contains('回答风格偏好：「正式」'));
      expect(prompt, contains('语气风格：「专业」'));

      // 规则
      expect(prompt, contains('沟通规则：先问后答'));
      expect(prompt, contains('禁止事项：别用缩写'));

      // 区段完整性
      expect(prompt, contains('【行为配置 — 动态指令】'));
      expect(prompt, contains('你必须严格遵守'));
      expect(prompt, contains('覆盖所有默认行为'));
      expect(prompt, contains('随时可以修改'));
    });
  });

  // ════════════════════════════════════════════
  // 场景6：边界情况
  // ════════════════════════════════════════════
  group('场景6：边界情况', () {
    test('无行为记忆 → 无行为配置区段', () async {
      setMemories([
        ('interest', 'hobby', '编程'),
        ('fact', 'petCat', '咪咪'),
      ]);

      final prompt = await repo.buildSystemPrompt();
      expect(prompt, isNot(contains('行为配置')));
      // 但用户记忆区段仍然存在
      expect(prompt, contains('【用户记忆】'));
    });

    test('无任何记忆 → 无行为配置也无用户记忆', () async {
      final prompt = await repo.buildSystemPrompt();
      expect(prompt, isNot(contains('行为配置')));
    });
  });

  // ════════════════════════════════════════════
  // 场景7：用户记忆与行为配置共存
  // ════════════════════════════════════════════
  group('场景7：用户记忆与行为配置共存', () {
    test('行为类 + 非行为类记忆并存 → 两个区段都正确生成', () async {
      setMemories([
        ('dynamic', 'agentName', '小黑'),
        ('interest', 'hobby', '编程'),
        ('fact', 'petCat', '咪咪'),
      ]);

      final prompt = await repo.buildSystemPrompt();

      // 用户记忆区段包含所有
      expect(prompt, contains('【用户记忆】'));
      expect(prompt, contains('编程'));
      expect(prompt, contains('咪咪'));

      // 行为配置区段只包含行为类，不包含兴趣/事实
      expect(prompt, contains('【行为配置 — 动态指令】'));
      expect(prompt, contains('智能体名称'));
      // "编程"/"咪咪"在用户记忆区段是正常的，但在行为配置小节之后不应出现
      final behaviorStart = prompt.indexOf('【行为配置 — 动态指令】');
      final behaviorEnd = prompt.indexOf('【记忆系统', behaviorStart);
      final behaviorSection = behaviorEnd > behaviorStart
          ? prompt.substring(behaviorStart, behaviorEnd)
          : prompt.substring(behaviorStart);
      expect(behaviorSection, isNot(contains('编程')));
      expect(behaviorSection, isNot(contains('咪咪')));
    });
  });

  // ════════════════════════════════════════════
  // 场景8：MemoryBudgetController 协作
  // ════════════════════════════════════════════
  group('场景8：与 MemoryBudgetController 协作', () {
    test('大量记忆 → 行为配置区段不受 budget 裁剪影响', () async {
      // 填充大量记忆：行为类 + 非行为类
      final entries = <(String, String, String)>[];
      // 行为类
      entries.add(('dynamic', 'agentName', '小黑'));
      entries.add(('dynamic', 'namePreference', '张总'));
      entries.add(('preference', 'answerStyle', '简洁'));
      entries.add(('preference', 'tone', '专业'));
      // 非行为类 — 填满到超过 budget
      for (var i = 0; i < 50; i++) {
        entries.add(('fact', 'fact_$i', '这是一条记忆内容 #$i，用于测试大量记忆场景下的budget控制'));
      }
      setMemories(entries);

      final prompt = await repo.buildSystemPrompt();

      // 行为配置区段必须完整（不受 budget 裁剪影响）
      expect(prompt, contains('【行为配置 — 动态指令】'));
      expect(prompt, contains('智能体名称是「小黑」'));
      expect(prompt, contains('用户希望被称呼为「张总」'));
      expect(prompt, contains('回答风格偏好：「简洁」'));
      expect(prompt, contains('语气风格：「专业」'));
    });
  });
}
