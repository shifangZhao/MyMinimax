/// Prompt 质量测试 — 用真实 LLM 评估编排器拆解质量。
///
/// 运行方式：
///   export MINIMAX_API_KEY=your_key_here
///   flutter test test/core/orchestrator/decomposition_quality_test.dart --dart-define=apiKey=$MINIMAX_API_KEY
///
/// 测试内容：
/// 1. JSON 可解析性
/// 2. 工具组分配正确性
/// 3. 无循环依赖
/// 4. 复杂度分档合理性
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/core/api/minimax_client.dart';
import 'package:myminimax/core/orchestrator/decomposer/decomposition_prompt.dart';
import 'package:myminimax/core/orchestrator/models/task_model.dart';
import 'package:myminimax/core/orchestrator/models/dag_model.dart';

/// 测试场景：覆盖日常任务、开发任务、多领域任务
final _testScenarios = [
  _Scenario(
    name: '天气查询（简单信息型）',
    request: '北京明天天气怎么样？',
    expectedGroups: ['basic'],
    expectedMinTasks: 1,
    expectedMaxTasks: 1,
  ),
  _Scenario(
    name: '多步信息收集（中等复杂度）',
    request: '帮我查一下北京明天的天气，然后规划一条从故宫到长城的路线，最后把结果保存到文件',
    expectedGroups: ['basic', 'map', 'file'],
    expectedMinTasks: 2,
    expectedMaxTasks: 5,
  ),
  _Scenario(
    name: '开发任务（实现功能）',
    request: '帮我实现一个 Flutter 表单页面，包含用户名和密码输入框，带表单验证功能。先分析需求，再实现代码，最后添加测试',
    expectedGroups: ['basic', 'file'],
    expectedMinTasks: 2,
    expectedMaxTasks: 5,
  ),
  _Scenario(
    name: '多领域复杂任务',
    request: '帮我查一下从北京到上海的高铁时刻表，同时查一下上海明天天气，然后对比两种出行方式（高铁 vs 飞机）的时间和价格给我一个出行建议',
    expectedGroups: ['basic', 'train', 'browser'],
    expectedMinTasks: 2,
    expectedMaxTasks: 6,
  ),
  _Scenario(
    name: '文件操作+通知（跨模块）',
    request: '读取桌面上 todos.md 里的待办事项，然后给张三发短信提醒他有3个未完成的任务',
    expectedGroups: ['basic', 'file', 'phone'],
    expectedMinTasks: 2,
    expectedMaxTasks: 4,
  ),
];

class _Scenario {
  final String name;
  final String request;
  final List<String> expectedGroups;
  final int expectedMinTasks;
  final int expectedMaxTasks;

  const _Scenario({
    required this.name,
    required this.request,
    required this.expectedGroups,
    required this.expectedMinTasks,
    required this.expectedMaxTasks,
  });
}

/// Valid tool group names that the decomposer should recognize.
const _validToolGroups = {
  'basic', 'map', 'browser', 'file', 'phone',
  'cron', 'express', 'generation', 'trend', 'train',
};

void main() {
  final apiKey = const String.fromEnvironment('apiKey');
  if (apiKey.isEmpty) {
    print('⚠️  未设置 API Key。跳过真实 LLM 调用测试。');
    print('   使用: flutter test test/core/orchestrator/decomposition_quality_test.dart --dart-define=apiKey=YOUR_KEY');
    return;
  }

  final client = MinimaxClient(apiKey: apiKey, model: 'MiniMax-M2.7');

  // 拆解质量评估结果
  final results = <_ScenarioResult>[];

  for (final scenario in _testScenarios) {
    test(scenario.name, () async {
      final prompt = DecompositionPrompt.build(scenario.request);
      expect(prompt, isNotEmpty, reason: 'Prompt 模板应该生成非空内容');

      // 调用 LLM
      String rawResponse;
      try {
        rawResponse = await client.chatCollect(
          prompt,
          temperature: 0.3,
          maxTokens: 4096,
          thinkingBudgetTokens: 0,
        );
      } catch (e) {
        fail('LLM 调用失败: $e');
      }

      expect(rawResponse, isNotEmpty, reason: 'LLM 应该返回非空响应');

      // 去除 markdown 代码块标记
      var json = rawResponse.trim();
      if (json.startsWith('```')) {
        final start = json.indexOf('\n');
        final end = json.lastIndexOf('```');
        if (start > 0 && end > start) {
          json = json.substring(start, end).trim();
        }
      }

      // 验证 JSON 可解析
      Map<String, dynamic> data;
      try {
        data = jsonDecode(json) as Map<String, dynamic>;
      } catch (e) {
        fail('JSON 解析失败: $e\n原始响应:\n$rawResponse');
      }

      // 验证复杂度挡位
      expect(data.containsKey('complexityTier'), true,
          reason: '应包含 complexityTier 字段');
      final tierStr = (data['complexityTier'] as String?)?.toLowerCase();
      expect(['trivial', 'small', 'medium', 'large'], contains(tierStr),
          reason: 'complexityTier 应为 trivial/small/medium/large 之一');

      // 验证 tasks 字段
      expect(data.containsKey('tasks'), true, reason: '应包含 tasks 字段');
      final tasks = data['tasks'] as List<dynamic>;
      expect(tasks.length, greaterThanOrEqualTo(scenario.expectedMinTasks),
          reason: '任务数应 >= ${scenario.expectedMinTasks}');
      expect(tasks.length, lessThanOrEqualTo(scenario.expectedMaxTasks),
          reason: '任务数应 <= ${scenario.expectedMaxTasks}');

      // 验证每个任务的结构
      final allToolGroups = <String>{};
      final taskIds = <String>{};
      final depMap = <String, List<String>>{};

      for (final task in tasks) {
        final t = task as Map<String, dynamic>;

        // 必填字段
        expect(t.containsKey('id'), true, reason: '每个任务应有 id');
        expect(t.containsKey('label'), true, reason: '每个任务应有 label');
        expect(t.containsKey('description'), true, reason: '每个任务应有 description');

        final id = t['id'] as String;
        expect(taskIds.contains(id), false, reason: '任务 ID 应唯一: $id');
        taskIds.add(id);

        // 验证工具组
        final groups = (t['requiredToolGroups'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ?? [];
        allToolGroups.addAll(groups);
        for (final g in groups) {
          expect(_validToolGroups.contains(g), true,
              reason: '工具组 "$g" 不在白名单中');
        }

        // 依赖
        final deps = (t['dependsOn'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ?? [];
        depMap[id] = deps;
      }

      // 验证依赖引用的 ID 都存在
      for (final entry in depMap.entries) {
        for (final dep in entry.value) {
          expect(taskIds.contains(dep), true,
              reason: '任务 ${entry.key} 依赖的 $dep 不存在');
        }
      }

      // 验证无循环依赖（通过构建 TaskGraph）
      try {
        final nodes = tasks.map((t) {
          final task = t as Map<String, dynamic>;
          return TaskNode(
            id: task['id'] as String,
            label: task['label'] as String? ?? '',
            description: task['description'] as String? ?? '',
            dependsOn: (task['dependsOn'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ?? [],
            requiredToolGroups: (task['requiredToolGroups'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ?? [],
            complexity: ComplexityTier.small,
          );
        }).toList();
        final graph = TaskGraph(nodes: nodes);
        graph.topologicalLayers(); // 会抛出 StateError 如果有循环
      } on StateError {
        fail('任务依赖存在循环依赖');
      }

      // 验证预期工具组被包含（根据场景，至少一个任务使用它）
      for (final expected in scenario.expectedGroups) {
        if (expected == 'basic') continue; // basic 总是有，跳过
        expect(allToolGroups.contains(expected), true,
            reason: '场景 "${scenario.name}" 应使用 $expected 工具组，但实际使用了: $allToolGroups');
      }

      // 记录结果
      results.add(_ScenarioResult(
        name: scenario.name,
        success: true,
        taskCount: tasks.length,
        toolGroups: allToolGroups,
        complexityTier: tierStr!,
      ));
    });
  }

  // 汇总报告
  tearDownAll(() {
    if (results.isEmpty) return;

    print('\n═══════════════════════════════════════════');
    print('  拆解质量测试报告');
    print('═══════════════════════════════════════════');
    int passed = 0;
    int failed = 0;
    for (final r in results) {
      final icon = r.success ? '✅' : '❌';
      print('  $icon ${r.name}');
      print('     任务数: ${r.taskCount} | 挡位: ${r.complexityTier} | 工具组: ${r.toolGroups.join(", ")}');
      if (r.success) {
        passed++;
      } else {
        failed++;
      }
    }
    print('───────────────────────────────────────────');
    print('  总计: ${results.length} | 通过: $passed | 失败: $failed');
    print('═══════════════════════════════════════════\n');
  });
}

class _ScenarioResult {
  final String name;
  final bool success;
  final int taskCount;
  final Set<String> toolGroups;
  final String complexityTier;

  _ScenarioResult({
    required this.name,
    required this.success,
    required this.taskCount,
    required this.toolGroups,
    required this.complexityTier,
  });
}
