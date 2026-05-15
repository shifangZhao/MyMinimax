import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/minimax_client.dart';
import '../../core/tools/tool_registry.dart';
import '../../core/storage/database_helper.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../features/tools/data/tool_executor.dart';

/// 后台 FlutterEngine 的入口点
void backgroundAgentMain() {
  runApp(ProviderScope(child: BackgroundAgentApp()));
}

class BackgroundAgentApp extends StatelessWidget {
  const BackgroundAgentApp({super.key});
  @override
  Widget build(BuildContext context) => const BackgroundAgentWidget();
}

class BackgroundAgentWidget extends StatefulWidget {
  const BackgroundAgentWidget({super.key});
  @override
  State<BackgroundAgentWidget> createState() => _BackgroundAgentWidgetState();
}

class _BackgroundAgentWidgetState extends State<BackgroundAgentWidget> {
  static const _channel = MethodChannel('com.myminimax/agent_engine');

  MinimaxClient? _client;
  ToolExecutor? _executor;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleMethodCall);
    _init();
  }

  Future<void> _init() async {
    try {
      final settings = SettingsRepository();
      final apiKey = await settings.getActiveApiKey();
      final baseUrl = await settings.getBaseUrl();
      final model = await settings.getModel();

      _client = MinimaxClient(
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
      );

      _executor = ToolExecutor(
        settingsRepo: settings,
        db: DatabaseHelper(),
      );

      _initialized = true;
    } catch (e) {
      debugPrint('[BackgroundAgent] init failed: $e');
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (!_initialized) {
      return {'error': 'Agent not initialized'};
    }

    if (call.method == 'executeTask') {
      try {
        final args = call.arguments as Map<String, dynamic>;
        final result = await _executeTask(
          args['taskId'] as String,
          args['title'] as String,
          args['description'] as String,
        );
        return {'result': result};
      } catch (e) {
        print('[background] error: \$e');
        return {'result': '执行失败: $e'};
      }
    }
    throw MissingPluginException();
  }

  Future<String> _executeTask(
    String taskId,
    String title,
    String description,
  ) async {
    if (_client == null) return 'Agent 未初始化';

    final messages = <Map<String, dynamic>>[];

    // 定时任务就是模拟用户在未来时间发送的一条消息，不需要 system prompt
    final userContent = StringBuffer();
    if (title.isNotEmpty) {
      userContent.write('任务名称：$title');
    }
    if (description.isNotEmpty) {
      if (userContent.isNotEmpty) userContent.write('\n');
      userContent.write('任务描述：$description');
    }
    userContent.write('\n\n这是定时任务，请根据上述内容自主完成任务。');
    messages.add({
      'role': 'user',
      'content': [
        {'type': 'text', 'text': userContent.toString(), 'cache_control': {'type': 'ephemeral'}},
      ],
    });

    final allContent = <String>[];
    const maxRounds = 50;

    for (int round = 0; round < maxRounds; round++) {
      final toolUseBlocks = <Map<String, dynamic>>[];
      bool contentFinished = false;

      await for (final chunk in _client!.chatStream(
        '',
        tools: ToolRegistry.instance.anthropicSchemas,
        directMessages: messages,
      )) {
        // 捕获工具调用
        if (chunk.isToolCall && chunk.toolName != null && chunk.toolUseId != null) {
          toolUseBlocks.add({
            'id': chunk.toolUseId,
            'name': chunk.toolName,
            'input': chunk.toolInput ?? '',
          });
        }

        // 捕获内容（收集所有非空内容块，避免覆盖丢失）
        if (chunk.hasContent && (chunk.content?.isNotEmpty ?? false)) {
          allContent.add(chunk.content!);
        }

        // 检测结束
        if (chunk.isContentFinished) {
          contentFinished = true;
          break;
        }
      }

      // 无更多工具调用，当前内容就是最终结果
      if (toolUseBlocks.isEmpty) break;

      // 执行所有工具调用，收集结果
      for (final tool in toolUseBlocks) {
        final toolName = tool['name'] as String;
        final toolInput = tool['input'] as String;

        Map<String, dynamic> parsedInput = {};
        try {
          parsedInput = jsonDecode(toolInput) as Map<String, dynamic>;
        } catch (_) {}

        final toolResult = await _executor!.executeWithHooks(
          toolName,
          parsedInput,
          conversationId: taskId,
        );

        messages.add({
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': tool['id'],
              'content': toolResult.output.isNotEmpty ? toolResult.output : toolResult.error ?? '(无输出)',
            }
          ],
        });
      }

      if (contentFinished) break;
    }

    final finalContent = allContent.join('\n\n');
    return finalContent.isEmpty ? '执行完成（无内容返回）' : finalContent;
  }

  @override
  Widget build(BuildContext context) {
    // headless - 不渲染任何 UI
    return const SizedBox.shrink();
  }
}
