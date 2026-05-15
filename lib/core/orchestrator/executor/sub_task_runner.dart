import 'dart:convert';
import 'package:dio/dio.dart';
import '../../api/minimax_client.dart';
import '../../tools/tool_registry.dart';
import '../../tools/tool_groups.dart';
import '../models/task_model.dart';
import '../models/working_memory.dart';
import '../orchestrator_types.dart';
class SubTaskResult {
  SubTaskResult({
    required this.taskId,
    required this.success,
    this.output,
    this.extractedData = const {},
    this.toolCallCount = 0,
    this.tokenCount = 0,
    this.error,
  });

  final String taskId;
  final bool success;
  final String? output;
  final Map<String, dynamic> extractedData;
  final int toolCallCount;
  final int tokenCount;
  final String? error;
}

/// Callback to execute a tool and produce a result.
/// Executes a single sub-task in an isolated context.
///
/// Each sub-task gets:
/// - A fresh LLM conversation (new chatStream call)
/// - Only the tool groups specified in [task.requiredToolGroups]
/// - Task-specific inference parameters
/// - Working memory context injected into system prompt
class SubTaskRunner {
  SubTaskRunner({required MinimaxClient client})
      : _client = client;

  final MinimaxClient _client;

  /// Max rounds per sub-task based on complexity.
  int _maxRoundsFor(ComplexityTier tier) => tier.maxToolRounds;

  /// Execute a single sub-task in a fresh context.
  Future<SubTaskResult> run(
    TaskNode task,
    WorkingMemory memory, {
    required ExecuteToolFn executeTool,
    List<String> dependencyIds = const [],
    CancelToken? cancelToken,
  }) async {
    final maxRounds = _maxRoundsFor(task.complexity);
    final apiMessages = <Map<String, dynamic>>[];

    // Build tool schemas: only the groups this sub-task needs
    final toolSchemas = _buildToolSchemas(task.requiredToolGroups);

    // Build system prompt with working memory context
    final wmContext = memory.buildContextString(task.id, dependencyIds: dependencyIds);
    final systemPrompt = wmContext.isNotEmpty
        ? '${task.description}\n\n$wmContext'
        : task.description;

    int toolCallCount = 0;
    int totalTokens = 0;

    for (int round = 0; round < maxRounds; round++) {
      if (cancelToken != null && cancelToken.isCancelled) {
        return SubTaskResult(
          taskId: task.id,
          success: false,
          error: '取消',
          toolCallCount: toolCallCount,
          tokenCount: totalTokens,
        );
      }

      String fullText = '';
      final toolUseBlocks = <Map<String, dynamic>>[];

      // LLM call
      await for (final chunk in _client.chatStream(
        '',
        systemPrompt: round == 0 ? systemPrompt : null,
        tools: toolSchemas,
        directMessages: apiMessages,
        temperature: (task.params['temperature'] as num?)?.toDouble() ?? 1.0,
        maxTokens: (task.params['maxTokens'] as int?) ?? 16384,
        thinkingBudgetTokens: (task.params['thinkingBudgetTokens'] as int?) ?? 2000,
      )) {
        if (chunk.hasContent && chunk.content != null) {
          fullText = chunk.content!;
        }
        if (chunk.isToolCall && chunk.toolName != null) {
          toolUseBlocks.add({
            'toolName': chunk.toolName,
            'toolUseId': chunk.toolUseId,
            'toolInput': chunk.toolInput ?? '',
          });
        }
        if (chunk.isToolCallFinished) {
          toolCallCount++;
        }
      }

      // No tool calls — task is done
      if (toolUseBlocks.isEmpty) {
        // Extract structured data markers from output
        final extracted = _extractWorkingMemoryMarkers(fullText);
        return SubTaskResult(
          taskId: task.id,
          success: true,
          output: fullText,
          extractedData: extracted,
          toolCallCount: toolCallCount,
          tokenCount: totalTokens,
        );
      }

      // Build assistant message
      final assistantContent = <Map<String, dynamic>>[];
      if (fullText.isNotEmpty) {
        assistantContent.add({'type': 'text', 'text': fullText});
      }
      for (final block in toolUseBlocks) {
        assistantContent.add({
          'type': 'tool_use',
          'id': block['toolUseId'],
          'name': block['toolName'],
          'input': _parseInput(block['toolInput'] as String),
        });
        apiMessages.add({'role': 'assistant', 'content': assistantContent});
      }

      // Execute tools and collect results
      final toolResultBlocks = <Map<String, dynamic>>[];
      for (final block in toolUseBlocks) {
        final toolName = block['toolName'] as String;
        final toolInput = block['toolInput'] as String;
        final toolUseId = block['toolUseId'] as String;

        Map<String, dynamic> result;
        try {
          final args = _parseInput(toolInput);
          result = await executeTool(toolName, args);
        } catch (e) {
          print('[sub] error: \$e');
          result = {'success': false, 'output': '工具执行失败: $e'};
        }

        final resultContent = result['success'] == true
            ? (result['output'] as String?) ?? 'ok'
            : (result['output'] as String?) ?? 'error';

        toolResultBlocks.add({
          'type': 'tool_result',
          'tool_use_id': toolUseId.toString(),
          'content': resultContent,
        });
      }

      // Feed results back
      apiMessages.add({'role': 'user', 'content': toolResultBlocks});
    }

    // Hit round limit
    return SubTaskResult(
      taskId: task.id,
      success: true,
      output: '(达到最大轮次限制)',
      toolCallCount: toolCallCount,
      tokenCount: totalTokens,
    );
  }

  /// Build tool schemas filtered to only the requested groups.
  List<Map<String, dynamic>> _buildToolSchemas(List<String> groupNames) {
    final allSchemas = ToolRegistry.instance.anthropicSchemas;
    final groups = groupNames
        .map((g) => ToolGroup.values.where((tg) => tg.label == g).firstOrNull)
        .whereType<ToolGroup>()
        .toSet();
    groups.add(ToolGroup.basic); // basic is always included

    final activeToolNames = ToolGroupRegistry.toolNamesInGroups(groups);
    return allSchemas
        .where((s) => activeToolNames.contains(s['name'] as String?))
        .toList();
  }

  /// Parse tool input JSON, with repair fallback.
  Map<String, dynamic> _parseInput(String input) {
    try {
      return jsonDecode(input) as Map<String, dynamic>;
    } catch (_) {
      return {'text': input};
    }
  }

  /// Extract [WM:key=value] markers from output.
  Map<String, dynamic> _extractWorkingMemoryMarkers(String text) {
    final result = <String, dynamic>{};
    final regex = RegExp(r'\[WM:(\w+)=((?:[^\]]|\\\])+)\]');
    for (final match in regex.allMatches(text)) {
      final key = match.group(1)!;
      final value = match.group(2)!.replaceAll(r'\]', ']');
      result[key] = value;
    }
    return result;
  }
}
