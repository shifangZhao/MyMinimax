import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/core/hooks/hook_pipeline.dart';

void main() {
  group('HookPipeline', () {
    late HookPipeline pipeline;

    setUp(() {
      pipeline = HookPipeline.empty();
      HookPipeline.setTestInstance(pipeline);
    });

    tearDown(() {
      HookPipeline.reset();
    });

    group('register and execute', () {
      test('executes registered handler for matching event', () async {
        final calls = <String>[];
        pipeline.register(
          HookEvent.beforeSend,
          (ctx) async => calls.add('beforeSend'),
          name: 'test_hook_exec',
        );

        await pipeline.execute(
          HookEvent.beforeSend,
          HookContext(HookEvent.beforeSend, {}),
        );

        expect(calls, ['beforeSend']);
        pipeline.unregister('test_hook_exec');
      });

      test('does not execute handler for non-matching event', () async {
        final calls = <String>[];
        pipeline.register(
          HookEvent.beforeSend,
          (ctx) async => calls.add('should not fire'),
          name: 'test_hook_nonmatch',
        );

        await pipeline.execute(
          HookEvent.afterReceive,
          HookContext(HookEvent.afterReceive, {}),
        );

        expect(calls, isEmpty);
        pipeline.unregister('test_hook_nonmatch');
      });

      test('executes hooks in priority order', () async {
        final order = <String>[];
        pipeline.register(
          HookEvent.beforeSend,
          (ctx) async => order.add('low'),
          name: 'low_priority',
          priority: 200,
        );
        pipeline.register(
          HookEvent.beforeSend,
          (ctx) async => order.add('high'),
          name: 'high_priority',
          priority: 50,
        );

        await pipeline.execute(
          HookEvent.beforeSend,
          HookContext(HookEvent.beforeSend, {}),
        );

        expect(order, ['high', 'low']);
        pipeline.unregister('low_priority');
        pipeline.unregister('high_priority');
      });
    });

    group('error handling', () {
      test('hook error does not block subsequent hooks', () async {
        final calls = <String>[];
        pipeline.register(
          HookEvent.beforeSend,
          (ctx) async => throw Exception('boom'),
          name: 'failing_hook',
        );
        pipeline.register(
          HookEvent.beforeSend,
          (ctx) async => calls.add('survivor'),
          name: 'survivor_hook',
          priority: 200,
        );

        await pipeline.execute(
          HookEvent.beforeSend,
          HookContext(HookEvent.beforeSend, {}),
        );

        expect(calls, ['survivor']);
        pipeline.unregister('failing_hook');
        pipeline.unregister('survivor_hook');
      });

      test('error is captured in context data', () async {
        pipeline.register(
          HookEvent.beforeSend,
          (ctx) async => throw Exception('captured_error'),
          name: 'err_hook',
        );

        final ctx = HookContext(HookEvent.beforeSend, {});
        await pipeline.execute(HookEvent.beforeSend, ctx);

        expect(ctx.data['_hookError_err_hook'], contains('captured_error'));
        pipeline.unregister('err_hook');
      });
    });

    group('unregister', () {
      test('removes registered hook', () async {
        final calls = <String>[];
        pipeline.register(
          HookEvent.beforeSend,
          (ctx) async => calls.add('first'),
          name: 'removable_hook',
        );
        pipeline.unregister('removable_hook');

        await pipeline.execute(
          HookEvent.beforeSend,
          HookContext(HookEvent.beforeSend, {}),
        );

        expect(calls, isEmpty);
      });
    });

    group('forProfile', () {
      test('minimal profile only includes session hooks', () {
        pipeline.register(HookEvent.onSessionStart, (ctx) async {}, name: 'session_start');
        pipeline.register(HookEvent.beforeSend, (ctx) async {}, name: 'safety_check');

        final filtered = pipeline.forProfile(HookProfile.minimal);

        expect(filtered.getRegisteredNames(HookEvent.onSessionStart), ['session_start']);
        expect(filtered.getRegisteredNames(HookEvent.beforeSend), isEmpty);

        pipeline.unregister('session_start');
        pipeline.unregister('safety_check');
      });

      test('standard profile includes safety, logging, mcp, etc.', () {
        pipeline.register(HookEvent.beforeSend, (ctx) async {}, name: 'safety_check');
        pipeline.register(HookEvent.beforeSend, (ctx) async {}, name: 'logging_hook');
        pipeline.register(HookEvent.beforeSend, (ctx) async {}, name: 'mcp_health');
        pipeline.register(HookEvent.beforeSend, (ctx) async {}, name: 'custom_feature');

        final filtered = pipeline.forProfile(HookProfile.standard);

        expect(filtered.getRegisteredNames(HookEvent.beforeSend), contains('safety_check'));
        expect(filtered.getRegisteredNames(HookEvent.beforeSend), contains('logging_hook'));
        expect(filtered.getRegisteredNames(HookEvent.beforeSend), contains('mcp_health'));
        expect(filtered.getRegisteredNames(HookEvent.beforeSend), isNot(contains('custom_feature')));

        pipeline.unregister('safety_check');
        pipeline.unregister('logging_hook');
        pipeline.unregister('mcp_health');
        pipeline.unregister('custom_feature');
      });
    });

    group('HookContext', () {
      test('convenience accessors return correct values', () {
        final ctx = HookContext(HookEvent.beforeToolUse, {
          'toolName': 'search',
          'params': {'query': 'test'},
          'conversationId': 'conv_123',
        });

        expect(ctx.toolName, 'search');
        expect(ctx.toolParams?['query'], 'test');
        expect(ctx.conversationId, 'conv_123');
        expect(ctx.isBlocked, false);
      });

      test('isBlocked and blockReason accessors', () {
        final ctx = HookContext(HookEvent.beforeToolUse, {
          'blocked': true,
          'blockReason': 'safety violation',
        });

        expect(ctx.isBlocked, true);
        expect(ctx.blockReason, 'safety violation');
      });
    });

    group('getRegisteredNames', () {
      test('returns empty list for event with no hooks', () {
        final names = pipeline.getRegisteredNames(HookEvent.beforeSend);
        expect(names, isA<List<String>>());
      });
    });

    group('setTestInstance override', () {
      test('instance getter returns test instance when overridden', () {
        expect(HookPipeline.instance, same(pipeline));
      });

      test('reset restores default instance', () {
        expect(HookPipeline.instance, same(pipeline));
        HookPipeline.reset();
        expect(HookPipeline.instance, isNot(same(pipeline)));
        // re-set for tearDown
        HookPipeline.setTestInstance(pipeline);
      });
    });
  });
}
