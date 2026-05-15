import 'dart:convert';

import '../api/minimax_client.dart';
import '../instructor/instructor.dart';
import '../../features/tools/domain/tool.dart';
import '../engine/conversation_session.dart';
import '../engine/judge.dart';

class MapStep {
  const MapStep(this.number, this.toolName, this.description, this.isError);
  final int number;
  final String toolName;
  final String description;
  final bool isError;
}

class MapAgentResult {
  MapAgentResult({
    required this.success,
    required this.summary,
    this.data,
    this.steps = const [],
    this.judgeReasoning,
    this.judgeVerdict,
  });
  final bool success;
  final String summary;
  final Map<String, dynamic>? data;
  final List<MapStep> steps;
  final String? judgeReasoning;
  final bool? judgeVerdict;

  bool get judgeAgreed => judgeVerdict == true;
}

typedef MapToolDispatch = Future<ToolResult> Function(
    String toolName, Map<String, dynamic> params);

class MapAgent {
  MapAgent({
    required MinimaxClient client,
    required MapToolDispatch dispatch,
    bool debug = false,
    bool useJudge = true,
    void Function(String)? onLog,
  })  : _client = client,
        _dispatch = dispatch,
        _debug = debug,
        _useJudge = useJudge {
    _onLog = onLog;
    if (_useJudge) {
      _judge = Judge(client: _client);
    }
  }

  final MinimaxClient _client;
  final MapToolDispatch _dispatch;
  final bool _debug;
  final bool _useJudge;
  Judge? _judge;
  void Function(String)? _onLog;

  static const _safetyLimit = 20;
  static const _maxConsecutiveFails = 5;
  static const _compactThreshold = 6000;

  // Per-run mutable state
  String _memory = '';
  String? _compactedMemory;

  void _log(String msg) {
    if (_debug) {
      if (_onLog != null) {
        _onLog!(msg);
      } else {
        // ignore: avoid_print
        print('[MapAgent] $msg');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Main entry point
  // ═══════════════════════════════════════════════════════════

  Future<MapAgentResult> execute({required String task, PauseToken? pauseToken}) async {
    final steps = <MapStep>[];
    int consecutiveFails = 0;

    for (int i = 0; i < _safetyLimit; i++) {
      // Pause check — stop early if paused
      if (pauseToken != null && pauseToken.isPaused) {
        return MapAgentResult(
          success: false,
          summary: 'Paused at step ${steps.length}',
          steps: steps,
        );
      }

      final stepNum = i + 1;
      final isLastStep = stepNum >= _safetyLimit;
      final isForceDone = consecutiveFails >= _maxConsecutiveFails;

      _log('══ Step $stepNum ══');

      // Compaction check
      await _maybeCompact(steps);

      // Build nudges — same pattern as WebAgent: nudge first, override later
      final nudges = _buildNudges(steps, consecutiveFails, isForceDone, isLastStep);
      final memoryBlock = _memory.isNotEmpty ? '\n<memory>\n$_memory\n</memory>' : '';

      final messages = _buildMessages(task, steps, nudges, memoryBlock, isForceDone || isLastStep);

      final response = await _askNextAction(messages);

      // Update memory if present
      if (response['memory'] is String && (response['memory'] as String).isNotEmpty) {
        _memory = response['memory'] as String;
      }

      _log('AI: tool="${response['tool'] ?? 'N/A'}" done=${response['done']}');

      // Agent called done — honour it
      if (response['done'] == true) {
        final agentSuccess = !isForceDone && (response['success'] as bool? ?? true);
        final summary = response['summary'] as String? ?? (isForceDone
            ? 'Forced done after $_maxConsecutiveFails consecutive failures.'
            : 'Task completed.');
        _log('DONE — $summary');

        // Run judge evaluation (if enabled and not force-done)
        String? judgeReasoning;
        bool? judgeVerdict;
        if (_useJudge && !isForceDone && _judge != null) {
          final judgeResult = await _judge!.evaluate(
            task: task,
            agentSummary: summary,
            steps: steps,
            agentReportedSuccess: agentSuccess,
          );
          judgeReasoning = judgeResult.reasoning;
          judgeVerdict = judgeResult.verdict;
          _log('JUDGE: verdict=${judgeVerdict ?? "N/A"} reasoning="${judgeReasoning ?? ""}"');
          if (judgeVerdict == false && agentSuccess) {
            _log('WARNING: Agent reported success but judge found failure.');
          }
        }

        return MapAgentResult(
          success: agentSuccess,
          summary: summary,
          data: response['data'] is Map<String, dynamic>
              ? response['data'] as Map<String, dynamic>
              : null,
          steps: steps,
          judgeReasoning: judgeReasoning,
          judgeVerdict: judgeVerdict,
        );
      }

      // Agent didn't call done but we're in force-done → override
      if (isForceDone || isLastStep) {
        steps.add(MapStep(stepNum, '',
            isForceDone
                ? 'FORCE DONE: reached $_maxConsecutiveFails consecutive failures.'
                : 'FORCE DONE: safety limit ($_safetyLimit) reached.',
            true));
        return MapAgentResult(
          success: false,
          summary: isForceDone
              ? 'Stopped after $_maxConsecutiveFails consecutive failures.'
              : 'Reached safety limit ($_safetyLimit steps).',
          steps: steps,
        );
      }

      final toolName = response['tool'] as String?;
      final params = (response['params'] as Map<String, dynamic>?) ?? {};
      if (toolName == null || toolName.isEmpty) {
        steps.add(MapStep(stepNum, '', 'Agent returned no tool — stopping.', false));
        return MapAgentResult(
          success: false,
          summary: 'Agent stopped without calling a tool.',
          steps: steps,
        );
      }

      // Execute the tool
      try {
        final result = await _dispatch(toolName, params);
        final ok = result.success ? 'OK' : 'ERR';
        final output = result.success
            ? result.output
            : (result.error ?? 'unknown error');
        var brief = output.length > 300 ? '${output.substring(0, 300)}...' : output;
        final desc = '$toolName → $ok: $brief';
        _log('  $desc');

        steps.add(MapStep(stepNum, toolName, desc, !result.success));

        if (result.success) {
          consecutiveFails = 0;
        } else {
          consecutiveFails++;
        }
      } catch (e) {
        print('[map] error: \$e');
        steps.add(MapStep(stepNum, toolName, 'EXCEPTION: $e', true));
        consecutiveFails++;
      }
    }

    // Safety limit reached — shouldn't normally get here (isLastStep handles it)
    return MapAgentResult(
      success: false,
      summary: 'Reached safety limit ($_safetyLimit steps).',
      steps: steps,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Nudges — layered, corrective, same pattern as WebAgent
  // ═══════════════════════════════════════════════════════════

  String _buildNudges(List<MapStep> steps, int consecFails,
      bool forceDone, bool isLastStep) {
    final nudges = <String>[];

    // Priority 1: force-done nudge (LLM sees this FIRST, can still call done gracefully)
    if (forceDone) {
      nudges.add('<nudge>FORCE DONE: $_maxConsecutiveFails consecutive failures. '
          'You MUST call done now with success=false. '
          'Report what happened and what you tried. Do NOT attempt more tools.</nudge>');
    }
    if (isLastStep && !forceDone) {
      nudges.add('<nudge>FINAL STEP: this is the last step. '
          'You MUST call done now — success=true if you have answers, '
          'success=false with partial results if not.</nudge>');
    }

    // Priority 2: budget warning
    final stepNum = steps.length + 1;
    if (stepNum >= (_safetyLimit * 0.75).round() && stepNum < _safetyLimit) {
      nudges.add('<nudge>Step budget: $stepNum/$_safetyLimit used. Plan to finish soon.</nudge>');
    }

    // Priority 3: failure pattern analysis
    if (consecFails >= 2) {
      // Look at the last few failures to identify patterns
      final recent = <String>[];
      for (int i = steps.length - 1; i >= 0 && recent.length < consecFails; i--) {
        if (steps[i].isError) recent.add(steps[i].description);
      }

      final allSameTool = recent.isNotEmpty &&
          recent.every((r) => r.startsWith(recent.first.split(' ').first));

      if (allSameTool) {
        final stuckTool = recent.first.split(' ').first;
        nudges.add('<nudge>$consecFails consecutive failures on "$stuckTool". '
            'This tool is not working for this task. Try a completely different approach: '
            'use a different tool, refine your parameters, or check if you have enough info to call done.</nudge>');
      } else {
        nudges.add('<nudge>$consecFails consecutive failures. '
            'Review what went wrong and try a different strategy. '
            'If the task seems impossible with available tools, call done with success=false.</nudge>');
      }
    }

    // Priority 4: same-tool loop detection (non-error repetition)
    if (steps.length >= 3) {
      final last3 = steps.sublist(steps.length - 3);
      final allSameTool = last3.length == 3 &&
          last3[0].toolName.isNotEmpty &&
          last3[0].toolName == last3[1].toolName &&
          last3[1].toolName == last3[2].toolName &&
          !last3.any((s) => s.isError);
      if (allSameTool) {
        nudges.add('<nudge>You have called "${last3[0].toolName}" 3 times in a row '
            'without errors but also without completing the task. '
            'Do you have enough information to call done? If not, try a DIFFERENT tool.</nudge>');
      }
    }

    // Priority 5: stuck with no progress
    if (steps.length >= 5) {
      final last5 = steps.sublist(steps.length - 5);
      final noProgress = last5.every((s) => s.isError);
      if (noProgress) {
        nudges.add('<nudge>5 consecutive steps with errors and no progress. '
            'Strongly consider calling done with success=false. '
            'Explain what you tried and why the task cannot be completed.</nudge>');
      }
    }

    // Priority 6: periodic mindfulness
    if (stepNum >= 12 && stepNum % 6 == 0) {
      nudges.add('<nudge>Step $stepNum. Review your progress. '
          'Do you have enough info to produce a complete answer? If yes, call done now.</nudge>');
    }

    return nudges.join('\n');
  }

  // ═══════════════════════════════════════════════════════════
  // Compaction — same pattern as WebAgent
  // ═══════════════════════════════════════════════════════════

  Future<void> _maybeCompact(List<MapStep> steps) async {
    if (steps.length < 10) return;

    final historyText =
        steps.map((s) => '[Step ${s.number}] ${s.description}').join('\n');

    if (_compactedMemory == null && historyText.length < _compactThreshold) return;

    final recentStart = steps.length > 6 ? steps.length - 6 : 0;
    final recentText = steps
        .sublist(recentStart)
        .map((s) => '[Step ${s.number}] ${s.description}')
        .join('\n');
    if (_compactedMemory != null && recentText.length < _compactThreshold ~/ 3) return;

    try {
      final compactPrompt = '''Summarize this map agent's execution history concisely:
- What was the user's task?
- What locations/addresses were resolved?
- What routes or places were found?
- What errors occurred and were they resolved?
- What information is still needed?

Be brief. This replaces the full history in the agent's context.

History:
$historyText''';

      _compactedMemory = await _client.chatCollect(
        compactPrompt,
        maxTokens: 512,
        temperature: 0.0,
      );
    } catch (_) {
      // Compaction failure is non-fatal
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Messages
  // ═══════════════════════════════════════════════════════════

  List<Message> _buildMessages(
      String task, List<MapStep> steps, String nudges, String memoryBlock,
      bool forceDone) {
    // Build history block (with compaction support)
    final historyBuf = StringBuffer();
    if (_compactedMemory != null) {
      historyBuf.writeln('<compacted_memory>\n$_compactedMemory\n</compacted_memory>\n');
      final recentStart = steps.length > 6 ? steps.length - 6 : 0;
      if (recentStart > 0) {
        historyBuf.writeln('<recent_steps>');
        for (final s in steps.sublist(recentStart)) {
          historyBuf.writeln('[Step ${s.number}] ${s.description}');
        }
        historyBuf.writeln('</recent_steps>');
      }
    } else if (steps.isNotEmpty) {
      historyBuf.writeln('<step_history>');
      for (final s in steps) {
        historyBuf.writeln('[Step ${s.number}] ${s.description}');
      }
      historyBuf.writeln('</step_history>');
    }

    final forceDoneLine = forceDone
        ? '\n<force_done>You MUST call done now. No more tools allowed.</force_done>\n'
        : '';

    return [
      Message.user(
        '<task>\n$task\n</task>$memoryBlock\n\n'
        '${historyBuf.toString()}$forceDoneLine\n'
        '$nudges\n\n'
        'Decide the next step. Respond with JSON only.',
      ),
    ];
  }

  // ═══════════════════════════════════════════════════════════
  // AI call
  // ═══════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> _askNextAction(
      List<Message> messages) async {
    try {
      final instructor = Instructor.fromClient(_client);
      final response = await instructor.complete(
        schema: _actionSchema,
        systemPrompt: _systemContent,
        messages: messages,
      );
      if (response.hasToolCalls) {
        return response.firstToolCall!.input;
      }
      // Fallback: try to parse JSON from text response
      if (response.text != null && response.text!.isNotEmpty) {
        final json = _tryExtractJson(response.text!);
        if (json != null) return json;
      }
      return {'done': true, 'summary': 'No structured response from agent.'};
    } catch (e) {
      print('[map] error: \$e');
      return {'done': true, 'summary': 'AI call failed: $e', 'success': false};
    }
  }

  /// Try to extract a JSON object from text that may contain markdown fences.
  static Map<String, dynamic>? _tryExtractJson(String text) {
    final trimmed = text.trim();
    // Try direct parse first
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    // Try extracting from ```json ... ``` fences
    final fenceMatch = RegExp(r'```(?:json)?\s*\n?([\s\S]*?)\n?```').firstMatch(trimmed);
    if (fenceMatch != null) {
      try {
        final decoded = jsonDecode(fenceMatch.group(1)!.trim());
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // Schemas
  // ═══════════════════════════════════════════════════════════

  static final _actionSchema = SchemaDefinition(
    name: 'map_agent_action',
    description: 'Decide the next map tool to call, or finish with a summary.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'thinking': {
          'type': 'string',
          'description': '1-3 sentences: analyze history, evaluate last result, plan next move.',
        },
        'evaluation_previous_goal': {
          'type': 'string',
          'description': 'One-sentence verdict on last step: succeeded / failed / partial, and why.',
        },
        'memory': {
          'type': 'string',
          'description': '1-2 sentences tracking overall progress: addresses resolved, routes found, key data gathered, remaining gaps.',
        },
        'next_goal': {
          'type': 'string',
          'description': 'What this step aims to achieve, in one clear sentence.',
        },
        'done': {
          'type': 'boolean',
          'description': 'True when task is fully complete or impossible to continue.',
        },
        'success': {
          'type': 'boolean',
          'description': 'Whether the task succeeded overall. Only when done=true.',
        },
        'summary': {
          'type': 'string',
          'description': 'Complete final answer if done. Include ALL findings with specific data.',
        },
        'tool': {
          'type': 'string',
          'description': 'Name of the map tool to call next (when done=false).',
        },
        'params': {
          'type': 'object',
          'description': 'Parameters for the tool (when done=false). Coordinates MUST be numbers.',
        },
        'data': {
          'type': 'object',
          'description': 'Structured data (when done=true).',
        },
      },
      'required': ['thinking', 'evaluation_previous_goal', 'memory', 'next_goal', 'done'],
    },
    fromJson: (json) => json,
  );

  // ═══════════════════════════════════════════════════════════
  // System prompt
  // ═══════════════════════════════════════════════════════════

  static final _systemContent = [
    {
      'type': 'text',
      'text': '''
<intro>
你是地图与位置 Agent。逐步调用地图工具，最后给出完整总结。
</intro>

<tools>
每步只调用一个工具。坐标必须是 JSON 数字: {"lng": 116.397}，禁止 {"lng": "116.397"}。

1. geocode — 地址转坐标。参数: address(必填), city(可选)
2. regeocode — 坐标转地址。参数: lng, lat(必填，数字)
3. search_places — 关键词搜POI。参数: keywords(必填), city, type(可选)
4. search_nearby — 附近搜索。参数: lng, lat, keywords(必填), radius_m(可选, 默认1000), type(可选)
5. plan_driving_route — 驾车路线。参数: origin_lng/lat, dest_lng/lat(必填), strategy(可选, 0-10)
6. plan_transit_route — 公交路线。参数: origin_lng/lat, dest_lng/lat(必填), city(可选), strategy(可选)
7. plan_walking_route — 步行路线。参数: origin_lng/lat, dest_lng/lat(必填)
8. plan_cycling_route — 骑行路线。参数: origin_lng/lat, dest_lng/lat(必填)
9. plan_electrobike_route — 电动车路线。参数: origin_lng/lat, dest_lng/lat(必填)
10. get_bus_arrival — 公交到站。参数: city, stop_name(必填), line_name(可选)
11. get_traffic_status — 实时路况。参数: lng, lat, radius(可选)，默认用设备位置
12. get_district_info — 行政区划。参数: adcode 或 name(二选一)
13. location_get — 获取GPS位置。参数: 无 ({})
14. poi_detail — POI详情。参数: poi_id(必填)
15. static_map — 静态地图。参数: lng, lat(必填), zoom(可选, 默认14), size(可选)
</tools>

<rules>
1. 用 geocode 先把地址转成坐标，再做路线或附近搜索。
2. 每步只调用一个工具。结果在 <step_history> 中查看。
3. 工具失败换另一个。同一工具连续两次失败: done 并 success=false。
4. 坐标和事实数据禁止编造。工具是你的唯一数据来源。
5. 在 memory 字段追踪进度。任务完成时调用 done 并给出完整总结。
</rules>

<output_format>
回复符合 map_agent_action schema 的有效 JSON。

调用工具:
{"thinking": "需要先解析坐标。", "evaluation_previous_goal": "开始任务。", "memory": "正在解析起点地址。", "next_goal": "解析起点坐标。", "done": false, "tool": "geocode", "params": {"address": "北京市朝阳区"}}

完成:
{"thinking": "已收集所有信息。", "evaluation_previous_goal": "路线已找到。", "memory": "任务完成。", "next_goal": "报告结果。", "done": true, "success": true, "summary": "查询结果:
1. 起点: ...
2. 路线: ...", "data": {}}
</output_format>
''',
      'cache_control': {'type': 'ephemeral'},
    },
  ];


}
