import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/core/engine/tool_execution_handler.dart';
import 'package:myminimax/core/engine/tool_loop_detector.dart';
import 'package:myminimax/features/tools/domain/tool.dart';

void main() {
  group('ToolExecutionHandler', () {
    late ToolExecutionHandler handler;

    setUp(() {
      handler = ToolExecutionHandler();
    });

    test('executes single tool successfully', () async {
      final result = await handler.executeTools(
        blocks: [
          {'id': 't1', 'name': 'readFile', 'input': {'path': '/tmp/test.txt'}},
        ],
        executeTool: (name, args) async => ToolResult(
          toolName: name,
          success: true,
          output: 'file contents here',
        ),
      );

      expect(result.fatalError, isNull);
      expect(result.toolResultBlocks.length, 1);
      expect(result.toolResultBlocks.first['content'], 'file contents here');
    });

    test('retries on transient error', () async {
      int calls = 0;
      final result = await handler.executeTools(
        blocks: [
          {'id': 't1', 'name': 'webSearch', 'input': {'query': 'test'}},
        ],
        executeTool: (name, args) async {
          calls++;
          if (calls == 1) {
            return ToolResult(toolName: name, success: false, output: '', error: 'Connection timeout');
          }
          return ToolResult(toolName: name, success: true, output: 'search results');
        },
      );

      expect(calls, 2); // original + retry
      expect(result.toolResultBlocks.first['content'], 'search results');
    });

    test('injects nudge after 3 consecutive failures', () async {
      final results = <ToolExecutionResult>[];
      for (int i = 0; i < 3; i++) {
        results.add(await handler.executeTools(
          blocks: [
            {'id': 't$i', 'name': 'browser_click', 'input': {'index': 3}},
          ],
          executeTool: (name, args) async => ToolResult(
            toolName: name, success: false, output: '', error: 'Element not found',
          ),
        ));
      }

      final lastContent = results.last.toolResultBlocks.first['content'] as String;
      expect(lastContent, contains('[SYSTEM: TOOL FAILURE DIAGNOSIS]'));
      expect(lastContent, contains('Element not found'));
      expect(lastContent, contains('已连续失败 3 次'));
    });

    test('hard stops after 6 consecutive failures', () async {
      ToolExecutionResult? last;
      for (int i = 0; i < 6; i++) {
        last = await handler.executeTools(
          blocks: [
            {'id': 't$i', 'name': 'broken_tool', 'input': {}},
          ],
          executeTool: (name, args) async => ToolResult(
            toolName: name, success: false, output: '', error: 'Fatal error',
          ),
        );
      }

      expect(last!.fatalError, isNotNull);
    });

    test('success resets error streak', () async {
      // Fail twice
      for (int i = 0; i < 2; i++) {
        await handler.executeTools(
          blocks: [
            {'id': 't$i', 'name': 'flaky_tool', 'input': {}},
          ],
          executeTool: (name, args) async => ToolResult(
            toolName: name, success: false, output: '', error: 'Oops',
          ),
        );
      }

      // Succeed
      await handler.executeTools(
        blocks: [
          {'id': 't_ok', 'name': 'flaky_tool', 'input': {}},
        ],
        executeTool: (name, args) async => ToolResult(
          toolName: name, success: true, output: 'recovered',
        ),
      );

      // Fail again — should be count 1, not 3
      final result = await handler.executeTools(
        blocks: [
          {'id': 't_new', 'name': 'flaky_tool', 'input': {}},
        ],
        executeTool: (name, args) async => ToolResult(
          toolName: name, success: false, output: '', error: 'Oops again',
        ),
      );

      final content = result.toolResultBlocks.first['content'] as String;
      expect(content, isNot(contains('[SYSTEM: TOOL FAILURE]'))); // no nudge yet
    });

    test('records to loop detector', () async {
      final detector = ToolLoopDetector(windowSize: 10);
      await handler.executeTools(
        blocks: [
          {'id': 't1', 'name': 'webSearch', 'input': {'query': 'test'}},
        ],
        executeTool: (name, args) async => ToolResult(
          toolName: name, success: true, output: 'results',
        ),
        loopDetector: detector,
      );

      // Detector should have 1 entry
      final nudge = detector.check();
      expect(nudge, isNull); // 1 call doesn't trigger loop detection
    });

    test('handles truncated tool block', () async {
      final result = await handler.executeTools(
        blocks: [
          {'id': 't1', 'name': 'webSearch', 'input': {}, '_truncated': true},
        ],
        executeTool: (name, args) async => ToolResult(
          toolName: name, success: false, output: '', error: 'incomplete input',
        ),
      );

      final content = result.toolResultBlocks.first['content'] as String;
      expect(content, contains('truncated'));
    });

    test('executes multiple tools in one round independently', () async {
      final result = await handler.executeTools(
        blocks: [
          {'id': 't1', 'name': 'readFile', 'input': {'path': 'a.txt'}},
          {'id': 't2', 'name': 'readFile', 'input': {'path': 'b.txt'}},
        ],
        executeTool: (name, args) async => ToolResult(
          toolName: name, success: true, output: 'content of ${args['path']}',
        ),
      );

      expect(result.toolResultBlocks.length, 2);
      expect(result.toolResultBlocks[0]['content'], 'content of a.txt');
      expect(result.toolResultBlocks[1]['content'], 'content of b.txt');
    });
  });
}
