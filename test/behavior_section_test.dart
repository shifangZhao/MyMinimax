// ===================================================================
// 行为配置区段 — 逻辑模拟测试
// 不依赖 SQLite/SharedPreferences，直接验证指令格式化逻辑
// ===================================================================

import 'package:flutter_test/flutter_test.dart';

/// 模拟 _buildBehaviorSection 的核心逻辑
String buildBehaviorSection({
  String? agentName,
  String? namePreference,
  String? userTitle,
  Map<String, String> preferences = const {},
  Map<String, String> notices = const {},
  String? behaviorHabits,
}) {
  final directives = <String>[];

  // ── 身份覆盖 ──
  if (agentName != null && agentName.isNotEmpty) {
    directives.add('你的智能体名称是「$agentName」。所有自称（我、本助手等）统一用此名称。回答中的署名也用此名。');
  }

  if (namePreference != null && namePreference.isNotEmpty) {
    final title = userTitle ?? '';
    final address = title.isNotEmpty ? '$title$namePreference' : namePreference;
    directives.add('用户希望被称呼为「$address」。每次对话用此称呼，不要用"用户""主人"等泛指。');
  } else if (userTitle != null && userTitle.isNotEmpty) {
    directives.add('对用户的尊称是「$userTitle」，在称呼用户时加上此尊称。');
  }

  // ── 风格偏好 ──
  if (preferences.containsKey('answerStyle') && preferences['answerStyle']!.isNotEmpty) {
    final v = preferences['answerStyle']!;
    directives.add('回答风格偏好：「$v」——你的回复必须符合此风格，这是用户明确要求的。');
  }
  if (preferences.containsKey('detailLevel') && preferences['detailLevel']!.isNotEmpty) {
    final v = preferences['detailLevel']!;
    directives.add('内容详细程度：「$v」。例如"详细"意味着充分展开说明，"简洁"意味着只给结论。');
  }
  if (preferences.containsKey('formatPreference') && preferences['formatPreference']!.isNotEmpty) {
    final v = preferences['formatPreference']!;
    directives.add('输出格式偏好：「$v」。优先使用此格式组织回答。');
  }
  if (preferences.containsKey('tone') && preferences['tone']!.isNotEmpty) {
    final v = preferences['tone']!;
    directives.add('语气风格：「$v」——所有对话遵循此语气。');
  }

  // ── 规则/禁忌 ──
  for (final entry in notices.entries) {
    final label = switch (entry.key) {
      'communicationRules' => '沟通规则',
      'prohibitedItems' => '禁止事项',
      'otherRequirements' => '其他要求',
      String k => k,
    };
    directives.add('$label：${entry.value}');
  }

  // ── 行为习惯 ──
  if (behaviorHabits != null && behaviorHabits.isNotEmpty) {
    directives.add('用户行为习惯：$behaviorHabits');
  }

  if (directives.isEmpty) return '';

  final buf = StringBuffer();
  buf.writeln('【行为配置 — 动态指令】');
  buf.writeln('以下指令基于用户设定的记忆生成，你必须严格遵守，覆盖所有默认行为：');
  for (final d in directives) {
    buf.writeln('- $d');
  }
  buf.writeln();
  buf.writeln('用户随时可以修改以上任何设置。当用户更改时，立即更新记忆并遵循新指令。');
  return buf.toString();
}

void main() {
  group('身份覆盖', () {
    test('agentName → 智能体名称指令', () {
      final result = buildBehaviorSection(agentName: '小黑');
      expect(result, contains('智能体名称是「小黑」'));
    });

    test('namePreference → 用户称呼指令', () {
      final result = buildBehaviorSection(namePreference: '小明');
      expect(result, contains('用户希望被称呼为「小明」'));
    });

    test('userTitle + namePreference → 组合称呼', () {
      final result = buildBehaviorSection(
        userTitle: '老师',
        namePreference: '王明',
      );
      expect(result, contains('用户希望被称呼为「老师王明」'));
    });

    test('只有 userTitle 没有 namePreference → 仅尊称指令', () {
      final result = buildBehaviorSection(userTitle: '先生');
      expect(result, contains('对用户的尊称是「先生」'));
      expect(result, isNot(contains('用户希望被称呼为')));
    });
  });

  group('风格偏好', () {
    test('answerStyle → 回答风格指令', () {
      final result = buildBehaviorSection(preferences: {'answerStyle': '简洁'});
      expect(result, contains('回答风格偏好'));
      expect(result, contains('「简洁」'));
      expect(result, contains('必须符合此风格'));
    });

    test('tone → 语气指令', () {
      final result = buildBehaviorSection(preferences: {'tone': '正式'});
      expect(result, contains('语气风格'));
      expect(result, contains('「正式」'));
      expect(result, contains('所有对话遵循此语气'));
    });

    test('多种偏好同时生效', () {
      final result = buildBehaviorSection(preferences: {
        'answerStyle': '详细',
        'tone': '专业',
        'formatPreference': 'markdown',
      });
      expect(result, contains('「详细」'));
      expect(result, contains('「专业」'));
      expect(result, contains('「markdown」'));
    });
  });

  group('规则/禁忌', () {
    test('communicationRules → 沟通规则指令', () {
      final result = buildBehaviorSection(notices: {
        'communicationRules': '每次汇报先说结论',
      });
      expect(result, contains('沟通规则'));
      expect(result, contains('每次汇报先说结论'));
    });

    test('prohibitedItems → 禁止事项指令', () {
      final result = buildBehaviorSection(notices: {
        'prohibitedItems': '不要用网络用语',
      });
      expect(result, contains('禁止事项'));
      expect(result, contains('不要用网络用语'));
    });

    test('多条 notice 同时生效', () {
      final result = buildBehaviorSection(notices: {
        'communicationRules': '先问后答',
        'prohibitedItems': '不用缩写',
        'otherRequirements': '每段不超过3句',
      });
      expect(result, contains('沟通规则：先问后答'));
      expect(result, contains('禁止事项：不用缩写'));
      expect(result, contains('其他要求：每段不超过3句'));
    });
  });

  group('完整场景', () {
    test('用户设定 AI 名称 + 称呼 + 风格', () {
      final result = buildBehaviorSection(
        agentName: '小黑',
        namePreference: '张总',
        preferences: {'answerStyle': '正式', 'tone': '商务'},
        notices: {'communicationRules': '每次回复先列要点'},
      );

      expect(result, contains('智能体名称是「小黑」'));
      expect(result, contains('用户希望被称呼为「张总」'));
      expect(result, contains('回答风格偏好：「正式」'));
      expect(result, contains('语气风格：「商务」'));
      expect(result, contains('沟通规则：每次回复先列要点'));
    });

    test('空输入 → 空输出', () {
      expect(buildBehaviorSection(), isEmpty);
    });

    test('只设 agentName → 只有身份指令', () {
      final result = buildBehaviorSection(agentName: '助手');
      expect(result, isNot(contains('回答风格偏好')));
      expect(result, isNot(contains('用户希望被称呼为')));
      expect(result, contains('智能体名称'));
    });

    test('behaveHabits → 习惯指令', () {
      final result = buildBehaviorSection(behaviorHabits: '早起工作');
      expect(result, contains('用户行为习惯：早起工作'));
    });
  });

  group('覆盖语义', () {
    test('指令包含"必须遵守"和"覆盖默认"', () {
      final result = buildBehaviorSection(
        agentName: '小黑',
        namePreference: '小明',
      );
      expect(result, contains('严格遵守'));
      expect(result, contains('覆盖所有默认行为'));
    });

    test('指令允许用户随时修改', () {
      final result = buildBehaviorSection(namePreference: '朋友');
      expect(result, contains('随时可以修改'));
      expect(result, contains('更新记忆并遵循'));
    });

    test('agentName 指令明确要求覆盖自称', () {
      final result = buildBehaviorSection(agentName: '小黑');
      expect(result, contains('所有自称'));
      expect(result, contains('统一用此名称'));
    });
  });
}
