import 'dart:convert';
import '../api/minimax_client.dart';
import '../instructor/instructor.dart';
import '../engine/conversation_session.dart';
import 'adapters/browser_tool_adapter.dart';
import 'detectors/action_loop_detector.dart';
import 'detectors/page_stagnation_detector.dart';
class StepRecord {
  const StepRecord(this.number, this.url, this.description, this.isError);
  final int number;
  final String url;
  final String description;
  final bool isError;
}

class WebAgentResult {

  WebAgentResult({
    required this.success,
    required this.summary,
    this.data,
    this.screenshots = const [],
    this.judgeReasoning,
    this.judgeVerdict,
    this.reachedCaptcha = false,
    this.impossibleTask = false,
    this.steps = const [],
  });
  final bool success;
  final String summary;
  final Map<String, dynamic>? data;
  final List<String> screenshots;
  final String? judgeReasoning;
  final bool? judgeVerdict;
  final bool reachedCaptcha;
  final bool impossibleTask;
  final List<StepRecord> steps;

  bool get judgeAgrees => judgeVerdict == true;
}

class WebAgent {

  WebAgent({
    required MinimaxClient client,
    required IBrowserBackend backend,
    Map<String, dynamic>? outputSchema,
    bool? useVision,
    bool flash = false,
    bool debug = false,
    bool useJudge = true,
    this.onHumanAssist,
    this.onLog,
  })  : _client = client,
        _backend = backend,
        _outputSchema = outputSchema,
        _useVision = useVision ?? MinimaxClient.isTokenPlanKey(client.apiKey),
        _flash = flash,
        _debug = debug,
        _useJudge = useJudge {
    _backend.onHumanAssist = onHumanAssist;
  }
  final MinimaxClient _client;
  final IBrowserBackend _backend;
  final Map<String, dynamic>? _outputSchema;
  final bool _useVision;

  static const _safetyLimit = 100;
  static const _maxFailures = 5;
  static const _compactThreshold = 12000;

  // Per-run mutable state
  Set<String> _previousElementKeys = {};
  Set<int>? _previousBackendNodeIds; // CDP: stable tracking
  String _plan = '';
  String? _compactedMemory;
  String? _screenshotDescription;

  // Loop detection — dedicated classes
  final ActionLoopDetector _loopDetector = ActionLoopDetector(windowSize: 20);
  final PageStagnationDetector _stagnationDetector = PageStagnationDetector();

  // Callback for human-in-the-loop.
  Future<String?> Function(String reason, String? prompt)? onHumanAssist;

  final bool _flash;
  final bool _debug;
  final bool _useJudge;
  void Function(String)? onLog;

  void _log(String msg) {
    if (_debug) {
      if (onLog != null) {
        onLog!(msg);
      } else {
        // ignore: avoid_print
        print('[WebAgent] $msg');
      }
    }
  }

  // ============================================================
  // Main execution loop
  // ============================================================

  Future<WebAgentResult> execute({
    required String task,
    String? startUrl,
    PauseToken? pauseToken,
  }) async {
    final steps = <StepRecord>[];
    int consecutiveFailures = 0;

    if (startUrl != null && startUrl.isNotEmpty) {
      await _backend.execute('browser_navigate', {'url': startUrl});
    }

    for (int i = 0; i < _safetyLimit; i++) {
      // 暂停检测：用户主动暂停时，保存当前进度后停止
      if (pauseToken != null && pauseToken.isPaused) {
        return WebAgentResult(
          success: false,
          summary: 'Paused at step ${steps.length}',
          steps: steps,
          impossibleTask: false,
        );
      }

      final stepNum = i + 1;
      final isLastStep = stepNum >= _safetyLimit;
      final isForceDone = consecutiveFailures >= _maxFailures;

      _log('══════ Step $stepNum ══════');
      final state = await _captureState();
      final currentUrl = state['url'] as String;
      _log('URL: $currentUrl');
      _log('Elements: ${state['elements'].toString().split('\n').length} lines');

      // Compaction check
      await _maybeCompact(steps);

      // Build dynamic nudges + plan display
      final nudges = _buildNudges(stepNum, steps, currentUrl,
          consecFails: consecutiveFailures,
          forceDone: isForceDone,
          isLastStep: isLastStep);
      final planBlock = _buildPlanBlock();
      final captchaDownloadBlock = _buildCaptchaAndDownloads(state);

      final response = await _askNextAction(
        task, state, stepNum, steps, nudges, '$planBlock\n$captchaDownloadBlock',
        forceDone: isForceDone || isLastStep,
      );

      // Parse plan update if present
      if (response['plan'] is String) {
        _plan = response['plan'] as String;
      }

      _log('AI: next_goal="${response['next_goal'] ?? ''}"');
      _log('AI: eval="${response['evaluation_previous_goal'] ?? ''}"');

      if (response['done'] == true) {
        _log('AI: DONE — ${response['summary'] ?? ''}');
        final agentSuccess = !isForceDone && (response['success'] as bool? ?? true);
        final summary = response['summary'] as String? ?? (isForceDone ? 'Forced done after $_maxFailures consecutive failures.' : 'Task completed.');

        // Run judge evaluation
        String? judgeReasoning;
        bool? judgeVerdict;
        if (_useJudge && !isForceDone) {
          final judgeResult = await _judge(task, summary, steps, agentSuccess);
          judgeReasoning = judgeResult['reasoning'] as String?;
          judgeVerdict = judgeResult['verdict'] as bool?;
          _log('JUDGE: verdict=${judgeVerdict ?? "N/A"} reasoning="${judgeReasoning ?? ""}"');
          if (judgeVerdict == false && agentSuccess) {
            _log('WARNING: Agent reported success but judge found failure.');
          }
        }

        return WebAgentResult(
          success: !isForceDone && agentSuccess,
          summary: summary,
          data: response['data'] is Map<String, dynamic>
              ? response['data'] as Map<String, dynamic>
              : null,
          judgeReasoning: judgeReasoning,
          judgeVerdict: judgeVerdict,
          steps: steps,
        );
      }

      // Force-done: if the agent decided NOT to call done but we're in force-done mode, override
      if (isForceDone || isLastStep) {
        steps.add(StepRecord(stepNum, currentUrl,
            isForceDone ? 'FORCE DONE: reached $_maxFailures consecutive failures.' : 'FORCE DONE: safety limit reached.',
            true));
        return WebAgentResult(
          success: false,
          summary: isForceDone
              ? 'Stopped after $_maxFailures consecutive failures. Last URL: $currentUrl'
              : 'Reached safety limit ($_safetyLimit steps). Last URL: $currentUrl',
          steps: steps,
        );
      }

      // Extract actions (backward compat: also accept single tool/params)
      List actions;
      if (response['actions'] is List && (response['actions'] as List).isNotEmpty) {
        actions = response['actions'] as List;
      } else if (response['tool'] is String && (response['tool'] as String).isNotEmpty) {
        actions = [{'tool': response['tool'], 'params': response['params'] ?? {}}];
      } else {
        steps.add(StepRecord(stepNum, currentUrl, 'AI returned no action — stopping.', false));
        break;
      }

      // Execute actions sequentially, stop on page change
      final actionResults = <String>[];
      String? finalUrl;
      bool anyError = false;
      bool pageChanged = false;

      for (int ai = 0; ai < actions.length; ai++) {
        final action = actions[ai] as Map<String, dynamic>;
        final toolName = action['tool'] as String?;
        final params = (action['params'] as Map<String, dynamic>?) ?? {};

        // Small settle delay between chained actions (skipped before first action)
        if (ai > 0) {
          await Future.delayed(const Duration(milliseconds: 150));
        }

        if (pageChanged) {
          actionResults.add('$toolName → SKIPPED (page changed)');
          continue;
        }

        try {
          final result = await _backend
              .execute(toolName!, params)
              .timeout(const Duration(seconds: 30));

          String? newUrl;
          try {
            final urlResult = await _backend.execute('browser_get_url', {});
            newUrl = urlResult.success ? urlResult.output : null;
          } catch (_) {}

          final urlChanged = newUrl != null && newUrl != currentUrl;
          final outcome = result.success
              ? 'OK: ${result.output.length > 200 ? '${result.output.substring(0, 200)}...' : result.output}'
              : 'ERR: ${result.error}';
          actionResults.add('$toolName(${_briefParams(params)}) → $outcome');
          _log('  Action: $toolName(${_briefParams(params)}) → $outcome');

          if (urlChanged) {
            pageChanged = true;
            finalUrl = newUrl;
            _previousElementKeys.clear();
          }
          if (!result.success) anyError = true;

          // Screenshot → vision
          if ((toolName == 'browser_screenshot' || toolName == 'browser_screenshot_element') && result.success && _useVision) {
            if (result.data != null && result.data!.isNotEmpty) {
              try {
                _screenshotDescription = await _client.vision(result.data!,
                  'Describe this screenshot in detail for a web automation agent.');
              } catch (_) {}
            }
          }

          // Stop on page-changing actions
          const pageChangers = ['browser_navigate', 'browser_go_back', 'browser_go_forward', 'browser_open_tab'];
          if (pageChangers.contains(toolName)) {
            pageChanged = true;
            finalUrl = newUrl;
          }

          // Action hash for loop detection
          _loopDetector.record(toolName, params);
        } catch (e) {
          print('[web] error: \$e');
          actionResults.add('$toolName → TIMEOUT/ERROR: $e');
          anyError = true;
        }
      }

      // Build compact step description
      final buf = StringBuffer();
      if (response['next_goal'] is String && (response['next_goal'] as String).isNotEmpty) {
        var g = response['next_goal'] as String;
        if (g.length > 80) g = '${g.substring(0, 80)}...';
        buf.write('[$g] ');
      }
      for (int ai = 0; ai < actionResults.length; ai++) {
        if (ai > 0) buf.write(' | ');
        var ar = actionResults[ai];
        if (ar.length > 150) ar = '${ar.substring(0, 150)}...';
        buf.write(ar);
      }
      if (pageChanged) buf.write(' ⚡PAGE');

      steps.add(StepRecord(stepNum, finalUrl ?? currentUrl, buf.toString().trim(), anyError));

      // Track consecutive failures
      if (anyError) {
        consecutiveFailures++;
      } else {
        consecutiveFailures = 0;
      }

      // Auto-recovery: if all actions failed with "not found", add delay + clear stale keys
      // Auto-recovery: if all errors are specifically element-not-found, clear stale keys
      if (anyError && actionResults.isNotEmpty &&
          actionResults.every((a) => a.contains('→ ERR: Element with index') || a.contains('→ ERR: Element not found:'))) {
        _previousElementKeys.clear();
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }

    final buf2 = StringBuffer();
    buf2.writeln('Agent reached safety limit ($_safetyLimit steps):');
    for (final s in steps) {
      buf2.writeln('[Step ${s.number}] ${s.description}');
    }
    return WebAgentResult(success: false, summary: buf2.toString(), steps: steps);
  }

  // ============================================================
  // State capture
  // ============================================================

  Future<Map<String, dynamic>> _captureState() async {
    final pageState = await _backend.capturePageState(
      previousElementKeys: _previousElementKeys,
    );

    final elements = pageState.elements;
    final url = pageState.url;
    String elementsFormatted = '(no interactive elements found)';

    if (elements.isNotEmpty) {
      final currentKeys = <String>{};
      final currentBackendIds = <int>{};
      final buf = StringBuffer();
      final hasPrev = _previousElementKeys.isNotEmpty;
      buf.writeln('${elements.length} elements.');
      if (hasPrev) buf.writeln('(* = new since last step)');

      // Compute relative depth
      int minDepth = 999;
      for (final e in elements.take(50)) {
        if (e.depth < minDepth) minDepth = e.depth;
      }

      for (final e in elements.take(50)) {
        final key = '${e.tag}|${e.text}|${e.id}|${e.ariaLabel}';
        currentKeys.add(key);
        if (e.backendNodeId != null) currentBackendIds.add(e.backendNodeId!);

        final isNew = e.isNew;
        final newMark = isNew ? '*' : ' ';
        final indent = '\t' * ((e.depth - minDepth).clamp(0, 5));

        final parts = <String>[];
        if (e.scrollable) parts.add(e.scrollInfo);
        if (e.disabled) parts.add('(DISABLED)');
        if (e.id.isNotEmpty) parts.add('#${e.id}');
        if (e.type.isNotEmpty) parts.add('type=${e.type}');
        if (e.placeholder.isNotEmpty) parts.add('placeholder="${e.placeholder}"');
        if (e.ariaLabel.isNotEmpty) parts.add('aria-label="${e.ariaLabel}"');
        if (e.text.isNotEmpty) parts.add('"${e.text}"');
        if (e.href.isNotEmpty) parts.add('href=${e.href}');
        if (e.listeners.isNotEmpty) parts.add('listeners:${e.listeners.join(",")}');

        buf.writeln('$indent$newMark[${e.index}] <${e.tag}> ${parts.join(' ')}');
      }

      if (elements.length > 50) {
        buf.writeln('  ... and ${elements.length - 50} more (scroll or use browser_get_content)');
      }

      _previousElementKeys = currentKeys;
      if (currentBackendIds.isNotEmpty) _previousBackendNodeIds = currentBackendIds;
      elementsFormatted = buf.toString();
    }

    // Page text — truncate for context window
    final text = pageState.pageText.isNotEmpty
        ? (pageState.pageText.length > 4000
            ? '${pageState.pageText.substring(0, 4000)}\n\n[Truncated.]'
            : pageState.pageText)
        : '(no content)';

    // Page fingerprint for stagnation detection
    _stagnationDetector.record(url, elementsFormatted.split('\n').length, text);

    return {
      'url': url,
      'text': text,
      'elements': elementsFormatted,
      'captcha': pageState.captchaWarning,
      'downloads': pageState.downloadsInfo ?? '',
    };
  }

  // ============================================================
  // Plan system
  // ============================================================

  String _buildPlanBlock() {
    if (_plan.isEmpty) return '';
    return '''
Plan (your current task breakdown):
$_plan

Legend: [>] = current step, [x] = done, [ ] = pending, [-] = skipped
Update the plan in your JSON response with {"plan": "..."} when steps are completed.''';
  }

  // ============================================================
  // Dynamic nudges
  // ============================================================

  String _buildNudges(int stepNum, List<StepRecord> steps, String currentUrl, {int consecFails = 0, bool forceDone = false, bool isLastStep = false}) {
    final nudges = <String>[];

    // Force-done nudge — highest priority
    if (forceDone) {
      nudges.add('<nudge>FORCE DONE: $_maxFailures consecutive failures. You MUST call done now with success=false and report what happened. Do NOT try more actions.</nudge>');
    }
    if (isLastStep && !forceDone) {
      nudges.add('<nudge>FINAL STEP: This is the last step. You MUST call done now — report partial results with success=false, or success=true if truly complete.</nudge>');
    }

    // Budget warning at ~75% step usage
    if (stepNum >= (_safetyLimit * 0.75).round() && stepNum < _safetyLimit) {
      nudges.add('<nudge>Step budget: $stepNum/$_safetyLimit used. Plan to finish soon.</nudge>');
    }

    // Analyze recent failures for patterns
    int consecFails = 0;
    String? failPattern;
    for (int i = steps.length - 1; i >= 0; i--) {
      if (steps[i].isError) {
        consecFails++;
        final desc = steps[i].description;
        if (desc.contains('not found') || desc.contains('Element with index')) {
          failPattern = 'element_not_found';
        } else if (desc.contains('TIMEOUT')) {
          failPattern = 'timeout';
        } else if (desc.contains('cross-origin') || desc.contains('blocked')) {
          failPattern = 'cross_origin';
        }
      } else {
        break;
      }
    }

    if (consecFails >= 3) {
      if (failPattern == 'element_not_found') {
        nudges.add('<nudge>$consecFails consecutive element-not-found errors. The page DOM has changed or indices are stale. Call browser_get_elements to refresh ALL indices, then use the CURRENT index numbers.</nudge>');
      } else if (failPattern == 'timeout') {
        nudges.add('<nudge>$consecFails consecutive timeouts. The page may be slow or unresponsive. Try browser_wait_for with a longer timeout, or browser_check_errors to diagnose.</nudge>');
      } else if (failPattern == 'cross_origin') {
        nudges.add('<nudge>$consecFails consecutive cross-origin failures. Cannot access iframe content from a different domain. Call browser_human_assist — the user must interact with this manually.</nudge>');
      } else {
        nudges.add('<nudge>$consecFails consecutive failures. Call browser_get_elements to refresh, then try a completely different approach. If the task is impossible, call done and explain why.</nudge>');
      }
    }

    // Page fingerprint stagnation detection
    final stagNudge = _stagnationDetector.nudgeMessage;
    if (stagNudge != null) nudges.add('<nudge>$stagNudge</nudge>');

    // Action hash loop detection
    final loopNudge = _loopDetector.nudgeMessage;
    if (loopNudge != null) nudges.add('<nudge>$loopNudge</nudge>');

    // URL loop detection
    if (steps.length >= 3) {
      final last3 = steps.sublist(steps.length - 3);
      if (last3.every((s) => s.url == currentUrl && !s.isError)) {
        nudges.add('<nudge>Stuck on "$currentUrl" for 3+ steps with no progress. Try: scrolling to reveal hidden content, hovering to open menus, using browser_find to locate text, or calling done if complete.</nudge>');
      }
    }

    // Same-action loop detection (string-based, catches most cases)
    if (steps.length >= 3) {
      final last3 = steps.sublist(steps.length - 3);
      final allSame = last3.length == 3 &&
          last3[0].description.substring(0, 30) == last3[1].description.substring(0, 30) &&
          last3[1].description.substring(0, 30) == last3[2].description.substring(0, 30);
      if (allSame) {
        nudges.add('<nudge>You have repeated the same action 3 times. It is not producing different results. Try something completely different.</nudge>');
      }
    }

    // Periodic mindfulness
    if (stepNum >= 20 && stepNum % 10 == 0) {
      nudges.add('<nudge>Step $stepNum. Do you have enough info to call done? If yes, finish the task.</nudge>');
    }

    return nudges.join('\n');
  }

  String _buildCaptchaAndDownloads(Map<String, dynamic> state) {
    final buf = StringBuffer();
    if (state['captcha'] != null) {
      buf.writeln('<captcha_warning>');
      buf.writeln('CAPTCHA DETECTED on this page!');
      buf.writeln(state['captcha'] as String);
      buf.writeln('Call browser_human_assist to ask the user to solve it, or try browser_screenshot_element to capture the captcha image.</captcha_warning>');
    }
    if (state['downloads'] is String && (state['downloads'] as String).isNotEmpty) {
      buf.writeln('<downloads>');
      buf.writeln(state['downloads'] as String);
      buf.writeln('</downloads>');
    }
    return buf.toString();
  }

  // ============================================================
  // Message compaction
  // ============================================================

  Future<void> _maybeCompact(List<StepRecord> steps) async {
    if (steps.length < 8) return;

    final historyText = steps.map((s) => '[Step ${s.number}] ${s.description}').join('\n');

    // First compaction: history exceeds threshold
    if (_compactedMemory == null && historyText.length < _compactThreshold) return;

    // Subsequent compactions: only the recent tail matters, compact when it grows
    final recentStart = steps.length > 6 ? steps.length - 6 : 0;
    final recentText = steps.sublist(recentStart).map((s) => '[Step ${s.number}] ${s.description}').join('\n');
    if (_compactedMemory != null && recentText.length < _compactThreshold ~/ 3) return;

    // Run compaction with a cheap prompt
    try {
      final compactPrompt = '''Summarize this browser automation history concisely. Capture:
- What page(s) were visited
- What actions were taken (login, search, extraction, etc.)
- Key findings or data obtained
- Errors encountered and whether they were resolved

Be brief. This summary replaces the full history in the agent's context window.

History:
$historyText''';

      _compactedMemory = await _client.chatCollect(
        compactPrompt,
        maxTokens: 1024,
        temperature: 0.0,
      );
    } catch (_) {
      // Compaction failure is non-fatal — keep old compacted memory
    }
  }

  // ── Schema for forcing structured agent actions via Instructor ──

  static final _actionSchema = SchemaDefinition(
    name: 'web_agent_action',
    description: 'Decide the next action(s) to accomplish the task. Chain safe actions together for efficiency.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'thinking': {
          'type': 'string',
          'description': '1-3 sentences of reasoning: analyze history, evaluate last action, plan next move.',
        },
        'evaluation_previous_goal': {
          'type': 'string',
          'description': 'One-sentence verdict on last step: Success/Failure/Uncertain and why.',
        },
        'memory': {
          'type': 'string',
          'description': '1-2 sentences tracking overall progress: pages visited, items found, steps completed.',
        },
        'next_goal': {
          'type': 'string',
          'description': 'What this step aims to achieve, in one clear sentence.',
        },
        'done': {'type': 'boolean', 'description': 'True when the task is fully complete or impossible to continue.'},
        'summary': {'type': 'string', 'description': 'Complete final report if done.'},
        'actions': {
          'type': 'array',
          'description': 'List of actions to execute in order. Put page-changing actions LAST (navigate, go_back). Safe to chain: type+type+click, hover+click, type+press_key. Max 3 actions.',
          'items': {
            'type': 'object',
            'properties': {
              'tool': {'type': 'string', 'description': 'Browser tool name.'},
              'params': {'type': 'object', 'description': 'Tool parameters.'},
            },
            'required': ['tool'],
          },
        },
        'plan': {
          'type': 'string',
          'description': 'Plan with [>]current [x]done [ ]pending markers. Optional.',
        },
        'data': {
          'type': 'object',
          'description': 'Structured data extracted from the page. Omit if not applicable.',
        },
      },
      'required': ['thinking', 'evaluation_previous_goal', 'memory', 'next_goal', 'done'],
    },
    fromJson: (json) => json,
  );

  // Lighter schema for flash mode — thinking fields optional
  static final _actionSchemaFlash = SchemaDefinition(
    name: 'web_agent_action_flash',
    description: 'Fast action decision. Skip reasoning for simple operations.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'done': {'type': 'boolean', 'description': 'True when done or impossible.'},
        'summary': {'type': 'string', 'description': 'Final report if done.'},
        'actions': {
          'type': 'array',
          'description': 'Actions to execute. Max 3, put page-changing actions last.',
          'items': {
            'type': 'object',
            'properties': {
              'tool': {'type': 'string'},
              'params': {'type': 'object'},
            },
            'required': ['tool'],
          },
        },
        'data': {'type': 'object', 'description': 'Structured data if requested.'},
      },
      'required': ['done'],
    },
    fromJson: (json) => json,
  );

  // ============================================================
  // AI interaction
  // ============================================================

  Future<Map<String, dynamic>> _askNextAction(
    String task,
    Map<String, dynamic> state,
    int step,
    List<StepRecord> history,
    String nudges,
    String planBlock, {
    bool forceDone = false,
  }) async {
    final systemContent = _buildSystemPrompt();

    // Build history block
    final historyBuf = StringBuffer();
    if (_compactedMemory != null) {
      historyBuf.writeln('<compacted_memory>\n$_compactedMemory\n</compacted_memory>\n');
      final recentStart = history.length > 6 ? history.length - 6 : 0;
      if (recentStart > 0) {
        historyBuf.writeln('<recent_steps>');
        for (final s in history.sublist(recentStart)) {
          historyBuf.writeln('[Step ${s.number}] ${s.description}');
        }
        historyBuf.writeln('</recent_steps>');
      }
    } else if (history.isNotEmpty) {
      historyBuf.writeln('<agent_history>');
      for (final s in history) {
        historyBuf.writeln('[Step ${s.number}] ${s.description}');
      }
      historyBuf.writeln('</agent_history>');
    }

    final screenshotBlock = _screenshotDescription != null
        ? '\n<screenshot_analysis>\n$_screenshotDescription\n</screenshot_analysis>\n'
        : '';
    _screenshotDescription = null;

    final prompt = '''
<task>
$task
</task>

<step_info>
Step $step | URL: ${state['url']}
$planBlock</step_info>

<browser_state>
<interactive_elements>
${state['elements']}
</interactive_elements>

<page_text>
${state['text']}
</page_text>
</browser_state>

${forceDone ? '<force_done>You MUST call done now. No more actions allowed.</force_done>\n' : ''}$screenshotBlock${historyBuf.toString()}$nudges
Respond with JSON only. Required fields: thinking, evaluation_previous_goal, memory, next_goal, done. If done=false, include tool+params. If done=true, include summary.''';

    try {
      final instructor = Instructor.fromClient(_client);
      final response = await instructor.complete(
        schema: _flash ? _actionSchemaFlash : _actionSchema,
        systemPrompt: systemContent,
        messages: [
          Message.user(prompt),
        ],
      );
      if (response.hasToolCalls) {
        return response.firstToolCall!.input;
      }
      // LLM returned a response but not as a structured tool call.
      // This usually means the model sent plain text instead of JSON.
      final fallbackText = response.text?.isNotEmpty == true
          ? response.text!
          : '(empty response)';
      _log('WARNING: No tool call in response. Raw text: $fallbackText');
      return {
        'done': true,
        'summary': 'Agent returned unstructured response (no JSON tool call). '
            'Raw output: $fallbackText',
      };
    } catch (e) {
      print('[web] error: \$e');
      _log('ERROR: AI call failed: $e');
      return {'done': true, 'summary': 'AI call failed: $e'};
    }
  }

  List<Map<String, dynamic>> _buildSystemPrompt() {
    final buf = StringBuffer();

    buf.write('''
<intro>
You are an AI agent designed to automate browser tasks in an iterative loop. Your ultimate goal is accomplishing the task provided in <task>.
You excel at:
1. Navigating complex websites and extracting precise information
2. Automating form submissions and interactive web actions
3. Recognizing CAPTCHAs, errors, and situations requiring human help
4. Efficiently performing diverse web tasks on mobile browsers
You decide when a task is complete. Call done when the user's request is fully satisfied.
</intro>

<language_settings>
- Default working language: Match the user's language
- Always respond in the same language as the user request
</language_settings>

<input>
At every step, your input consists of:
1. <task>: The user's request — your ultimate objective, always visible.
2. <step_info>: Current step number and URL.
3. <browser_state>: <interactive_elements> with indexed elements and <page_text>.
4. <agent_history>: Chronological record of your previous actions and their results.
5. Optional: <screenshot_analysis> (if you took a screenshot last step), <captcha_warning>, <downloads>, <nudge> messages, <compacted_memory>.
</input>

<browser_state>
Interactive elements shown with tab-indented hierarchy (parent → child relationships):
  [1] <input> placeholder="Search..." type=text
  *[3] <button> "Submit"              ← * = NEW since last step
	[5] <a> href=/login "Login"       ← tab-indented = child of element above
  [7] <div> |SCROLL| 30% (150/500)   ← scrollable container, 30% scrolled

- Tab indentation shows parent/child DOM relationships.
- |SCROLL| marks scrollable containers with scroll position. Scroll to see more content.
- *[N] elements appeared because of your last action. E.g. after typing, *[4] <li> "suggestion" appears.
- After navigation: the entire list is refreshed. Old indices are invalid.
- (DISABLED) elements cannot be interacted with.
- ** CRITICAL: Indices change EVERY step. The [3] from 2 steps ago is NOT valid now. Use THIS step's numbers only. **
- Never memorize or reuse old indices. Each <interactive_elements> list is a fresh snapshot.
- Only elements with [N] indices are interactive. Use the CURRENT index number from THIS step.
</browser_state>

<screenshot_analysis>
If you took a screenshot in the previous step, an AI-generated text description will appear here.
This is your visual ground truth. Use it to verify what you see in the text elements list.
</screenshot_analysis>

<browser_rules>
Strictly follow these rules while using the browser:
- ** RULE #1: Indices are PER-STEP. Do NOT reuse [7] from a previous step — the list changes every step. Always use the CURRENT <interactive_elements>. **
- Only interact with elements that have a numeric [index] in THIS step's list. Use that exact index number.
- Elements marked *[N] appeared because of your previous action. Analyze them — they may be what you need.
- After navigation actions (navigate, go_back, go_forward): the entire list is refreshed. Old indices are stale garbage.
- By default, only elements near the visible viewport are listed. Scroll to reveal more.
- After filling an input field, suggestions may appear as new elements in the next step. Check for *[N] items.
- If you fill a field and press Enter but nothing changes, try clicking a search button or suggestion instead.
- For autocomplete/combobox fields: type text, then in the NEXT step check for *[N] suggestions. Click the right one.
- Handle popups, modals, cookie banners immediately. Look for close buttons (X, Close, Dismiss, Accept, Agree).
- If you get access denied (403), bot detection, or repeated failures, try a DIFFERENT approach or URL.
- Detect and break loops: if same URL for 3+ steps with no progress, change strategy.
- CAPTCHAs require human help. Call browser_human_assist immediately — do NOT try to solve them.
- Don't login unless you have credentials or the task requires it. Don't login just because a login button exists.
- The <task> is the ultimate goal. If the user specifies explicit steps, follow them precisely.
- If the task is open-ended, plan yourself and be creative.
- Do not repeatedly call browser_detect_form_result on the same page — call it once after form submission.
- Do not call browser_get_content on the same page multiple times without changes — use the data you already have.
</browser_rules>

<task_completion_rules>
Call done in one of these cases:
- You have fully completed the user request.
- It is absolutely impossible to continue (blocked, no credentials, fatal error).

Before calling done with success=true, you MUST verify:
1. Re-read the <task> — list every concrete requirement.
2. Check each requirement against your results. Did you extract the CORRECT number of items? Apply ALL filters?
3. Verify actions actually completed. If you submitted a form, did it succeed? Check browser_detect_form_result.
4. Verify data grounding: Every value you report must come from the page during this session. Do NOT use training knowledge to fill gaps. If information was not found, say so explicitly.
5. Blocking error check: If you hit an unresolved blocker → set success=false. Temporary obstacles (dismissed popups, retried actions) do NOT count.

Partial results with success=false are more valuable than claiming success when you're unsure.
Put ALL relevant findings in your summary when you call done.
</task_completion_rules>

<reasoning_rules>
You must reason explicitly at every step in your "thinking" field. Follow this pattern:
- Analyze <agent_history> to track progress toward the <task>.
- Explicitly state what you tried last step and whether it succeeded or failed.
- If the last action failed, state WHY and what you will do differently.
- Analyze which *[N] elements are new and what they mean.
- Analyze whether you are stuck — repeating the same actions without progress. If so, change strategy.
- When ready to finish, state you are preparing to call done and communicate results.
- Always compare your current trajectory against the original <task> — don't drift.
</reasoning_rules>

<error_recovery>
When encountering errors or unexpected states:
1. Verify the current state using <browser_state>. Is the page what you expected?
2. If an element is not found, the indices changed. Use the CURRENT <interactive_elements> list.
3. Check if a popup, modal, or overlay is blocking interaction.
4. If an action fails repeatedly (2-3 times), try an alternative approach — different element, different method.
5. If blocked by login/403, consider alternative sites or call browser_human_assist.
6. If stuck in a loop, explicitly acknowledge it in thinking and change strategy.
7. If the page seems broken, call browser_check_errors to diagnose.
</error_recovery>

<tools>
Navigation:  browser_navigate(url) | browser_go_back | browser_go_forward | browser_open_tab
             browser_search(query, engine?)  — search DuckDuckGo (default), Google, Bing
             browser_switch_tab(tabIndex) — switch to another open tab
Discovery:   browser_get_elements (ALWAYS first) | browser_search_page(text, regex?, case_sensitive?) | browser_find_elements(selector)
Content:     browser_get_content(selector?) | browser_scroll_and_collect(maxScreens?)
Interaction: browser_click(index) | browser_type(index, text, clear?) | browser_hover(index)
             browser_press_key(key, index?) | browser_drag(fromIndex, toIndex?, dx?, dy?)
             browser_scroll(direction) | browser_wait(timeout?)
             browser_select_dropdown(index, text) | browser_get_dropdown_options(index)
             browser_upload_file(index) — triggers native file picker on a file input
Forms:       browser_detect_form_result | browser_wait_for(text?, selector?, disappear?)
Clipboard:   browser_clipboard_copy(index?) | browser_clipboard_paste(index?)
Vision:      browser_screenshot | browser_screenshot_element(index)
Session:     browser_save_cookies | browser_restore_cookies | browser_list_downloads
Diagnostics: browser_check_errors | browser_detect_captcha | browser_get_iframe(index?)
Utility:     browser_find(text) | browser_execute_js(code) | browser_get_url | browser_get_title
             browser_load_html | browser_human_assist(reason, prompt?) | browser_close_tab
             browser_save_as_pdf(landscape?) — opens print dialog
</tools>

<action_efficiency>
You can output multiple actions in ONE step using the "actions" array. They execute sequentially.

ACTION CATEGORIES:
- Page-changing (always put LAST): browser_navigate, browser_go_back, browser_go_forward.
  After these, remaining actions are SKIPPED.
- Safe-to-chain: browser_type, browser_hover, browser_scroll, browser_wait_for,
  browser_search_page, browser_find_elements, browser_detect_form_result.
- Potentially page-changing: browser_click, browser_press_key(Enter).
  If URL changes after these, remaining actions are skipped.

RECOMMENDED CHAINS (max 3 actions):
- type(index=1, text) + type(index=2, text) + click(index=3) → fill form & submit
- hover(index=5) + click(index=8) → open dropdown & select option
- type(index=1, text) + press_key(key="Enter") → search query & submit
- type + type + type → fill multiple fields

Put page-changing actions LAST. Max 3 actions per step.
</action_efficiency>

<critical_reminders>
1. ALWAYS verify action success using the elements list and page state before proceeding
2. ALWAYS handle popups/modals/cookie banners before other actions
3. NEVER repeat the same failing action more than 2-3 times — try alternatives
4. NEVER assume success — verify from the page state
5. CAPTCHAs require browser_human_assist — do not attempt to solve them
6. Put ALL relevant findings in the done summary
7. Track progress in memory to avoid loops
8. Always compare current trajectory against the user's original request
9. Data must come from the page, not from training knowledge
</critical_reminders>

<examples>
Here are examples of good output patterns:

Task: "Log into example.com with user admin / pass123"
Step 1 thinking: "Starting login task. Need to navigate to login page first."
Step 2 thinking: "Page loaded. See username field [1], password field [2], login button [3]. Will fill credentials."
Step 3 thinking: "Typed username. Now fill password."
Step 4 thinking: "Credentials filled. Now click login button [3]."
Step 5 thinking: "Clicked submit. Need to check if login succeeded."
Step 6 (calls browser_detect_form_result → "Invalid password"):
  thinking: "Login failed — incorrect password. Reporting to user."
  -> {"done": true, "summary": "Login failed: the server returned 'Invalid password'. The credentials may be incorrect."}

Task: "Find iPhone 15 price on a shopping site"
Step 1: navigate → get_elements → type "iPhone 15" in search [5] → press Enter
Step 2: get_elements → *[42] appears! "iPhone 15 - \$6999"
  thinking: "Search complete. New element *[42] shows iPhone 15 with price \$6999. Data verified from page."
  -> {"done": true, "summary": "iPhone 15 price: \$6999"}
</examples>
''');

    if (_outputSchema != null) {
      buf.write('\n<structured_output>\n');
      buf.write('When calling done, your response MUST include "data" matching this JSON Schema:\n');
      buf.write(jsonEncode(_outputSchema));
      buf.write('\nFormat: {"done": true, "summary": "...", "data": {<matching schema>}}');
      buf.write('\n</structured_output>\n');
    }

    if (_useVision) {
      buf.write('\n<vision>\n');
      buf.write('Visual analysis is available. Call browser_screenshot or browser_screenshot_element to capture images.\n');
      buf.write('The screenshot will be analyzed and a description injected as <screenshot_analysis> in the next step.\n');
      buf.write('Use this for: CAPTCHA reading, layout understanding, image content, visual verification.\n');
      buf.write('</vision>\n');
    }

    if (_flash) {
      buf.write('\n<flash_mode>\n');
      buf.write('FLASH MODE is active. Skip reasoning — act directly. Thinking fields are optional.\n');
      buf.write('Output: {"done": false, "actions": [{"tool": "...", "params": {...}}]}\n');
      buf.write('Or: {"done": true, "summary": "..."}\n');
      buf.write('</flash_mode>\n');
    } else {
      buf.write('\n<output>\n');
      buf.write('Respond with valid JSON. For actions (up to 3, put page-changers LAST):\n');
      buf.write('{"thinking": "...", "evaluation_previous_goal": "...", "memory": "...",\n');
      buf.write(' "next_goal": "...", "done": false,\n');
      buf.write(' "actions": [{"tool": "browser_type", "params": {"index": 1, "text": "admin"}},\n');
      buf.write('            {"tool": "browser_click", "params": {"index": 3}}]}\n');
      buf.write('\nFor completion:\n');
      buf.write('{"thinking": "...", "evaluation_previous_goal": "...", "memory": "...",\n');
      buf.write(' "next_goal": "Report results", "done": true, "summary": "Findings here"}\n');
      buf.write('\nRequired: thinking, evaluation_previous_goal, memory, next_goal, done.\n');
      buf.write('If done=false: include "actions" array. If done=true: include "summary".\n');
      buf.write('</output>\n');
    }

    return [
      {
        'type': 'text',
        'text': buf.toString(),
        'cache_control': {'type': 'ephemeral'},
      },
    ];
  }

  // ============================================================
  // Structured data extraction from page content
  // ============================================================

  /// Extract structured data from the current page or any text using
  /// Instructor's schema-driven extraction. Useful for scraping product
  /// listings, search results, contact info, etc. from web pages.
  ///
  /// Usage:
  /// ```dart
  /// final products = await agent.extractStructured(
  ///   schema: productSchema,
  ///   text: pageContent,
  /// );
  /// if (products.isSuccess) { ... }
  /// ```
  Future<Maybe<T>> extractStructured<T>({
    required SchemaDefinition schema,
    required String text,
    String? instruction,
    int maxRetries = 2,
  }) async {
    final instructor = Instructor.fromClient(_client);
    return instructor.extract<T>(
      schema: schema,
      messages: [
        Message.system('Extract structured data from the provided content.'),
        if (instruction != null) Message.user(instruction),
        Message.user('Content:\n\n$text'),
      ],
      maxRetries: maxRetries,
    );
  }

  // ============================================================
  // Utilities
  // ============================================================

  // ============================================================
  // Judge system — post-run evaluation
  // ============================================================

  /// Evaluates whether the agent truly completed the task.
  /// Returns {'verdict': bool, 'reasoning': String, 'reached_captcha': bool, 'impossible_task': bool}
  Future<Map<String, dynamic>> _judge(
    String task,
    String agentSummary,
    List<StepRecord> steps,
    bool agentReportedSuccess,
  ) async {
    final stepsText = steps.map((s) => '[Step ${s.number}] ${s.description}').join('\n');
    final judgePrompt = '''Evaluate this browser automation agent's performance.

<task>
$task
</task>

<agent_result>
Success reported: $agentReportedSuccess
Summary: $agentSummary
</agent_result>

<agent_trajectory>
$stepsText
</agent_trajectory>

Evaluate these criteria:
1. Task Satisfaction: Did the agent complete every explicit requirement?
2. Output Quality: Is the output accurate, complete, and grounded in page data?
3. Tool Effectiveness: Did the agent use appropriate tools effectively?
4. Agent Reasoning: Did the agent recover from errors and avoid loops?
5. Browser Handling: Did the agent handle popups, navigation, and page changes correctly?

Respond with JSON:
{"verdict": true/false, "reasoning": "...", "failure_reason": "...", "reached_captcha": true/false, "impossible_task": true/false}

- verdict=true: agent correctly completed the task
- verdict=false: agent failed, was blocked, or returned incomplete results
- impossible_task=true: task was fundamentally impossible (broken site, missing auth, 404)''';

    try {
      final result = await _client.chatCollect(
        judgePrompt,
        maxTokens: 1024,
        temperature: 0.0,
      );
      final jsonStart = result.indexOf('{');
      final jsonEnd = result.lastIndexOf('}');
      if (jsonStart >= 0 && jsonEnd > jsonStart) {
        final parsed = jsonDecode(result.substring(jsonStart, jsonEnd + 1)) as Map<String, dynamic>;
        return {
          'verdict': parsed['verdict'] as bool?,
          'reasoning': parsed['reasoning'] as String? ?? parsed['failure_reason'] as String?,
          'reached_captcha': parsed['reached_captcha'] as bool? ?? false,
          'impossible_task': parsed['impossible_task'] as bool? ?? false,
        };
      }
      return {'verdict': null, 'reasoning': 'Judge response not parseable.'};
    } catch (e) {
      print('[web] error: \$e');
      return {'verdict': null, 'reasoning': 'Judge call failed: $e'};
    }
  }

  String _briefParams(Map<String, dynamic> params) {
    if (params.isEmpty) return '';
    final entries = params.entries.take(2).map(
      (e) => '${e.key}=${e.value}'.length > 40 ? '${e.key}=...' : '${e.key}=${e.value}',
    );
    return entries.join(', ');
  }

}
