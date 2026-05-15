import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/core/tools/tool_registry.dart';
import 'package:myminimax/core/tools/tool_groups.dart';
import 'package:myminimax/features/tools/domain/tool.dart';

void main() {
  group('ToolRegistry', () {
    late ToolRegistry registry;

    setUp(() {
      // Create a fresh instance for each test
      registry = ToolRegistry.createForTest();
      registry.init();
      ToolRegistry.setTestInstance(registry);
    });

    tearDown(() {
      ToolRegistry.reset();
    });

    group('init and lookup', () {
      test('init registers builtin tools', () {
        expect(registry.builtinToolCount, greaterThan(20));
      });

      test('getTool returns definition for known tool', () {
        final tool = registry.getTool('readFile');
        expect(tool, isNotNull);
        expect(tool!.name, 'readFile');
        expect(tool.category, ToolCategory.file);
      });

      test('getTool returns null for unknown tool', () {
        expect(registry.getTool('nonexistent_tool_xyz'), isNull);
      });

      test('getToolRequired throws for unknown tool', () {
        expect(
          () => registry.getToolRequired('nonexistent_tool_xyz'),
          throwsA(isA<TypeError>()),
        );
      });

      test('exists returns true for registered tool', () {
        expect(registry.exists('readFile'), true);
        expect(registry.exists('nonexistent_tool_xyz'), false);
      });

      test('allTools includes builtin tools', () {
        final names = registry.allTools.map((t) => t.name).toSet();
        expect(names, contains('readFile'));
        expect(names, contains('writeFile'));
        expect(names, contains('webSearch'));
      });

      test('instance getter returns test instance when overridden', () {
        expect(ToolRegistry.instance, same(registry));
      });
    });

    group('anthropicSchemas', () {
      test('returns enabled tool schemas', () {
        final schemas = registry.anthropicSchemas;
        expect(schemas, isNotEmpty);
        for (final s in schemas) {
          expect(s, contains('name'));
          expect(s, contains('description'));
          expect(s, contains('input_schema'));
        }
      });
    });

    group('setEnabled', () {
      test('disabling a tool removes it from schemas', () {
        final before = registry.anthropicSchemas.length;
        registry.setEnabled('readFile', false);
        final after = registry.anthropicSchemas.length;
        expect(after, before - 1);
        registry.setEnabled('readFile', true);
      });

      test('re-enabling a tool adds it back', () {
        registry.setEnabled('readFile', false);
        registry.setEnabled('readFile', true);
        final names = registry.anthropicSchemas.map((s) => s['name']).toSet();
        expect(names, contains('readFile'));
      });
    });

    group('MCP tools', () {
      test('injectMcpTools adds tools with mcp source', () {
        registry.injectMcpTools([
          {
            'name': 'custom_mcp_tool',
            'description': 'A custom MCP tool',
            'input_schema': <String, dynamic>{'type': 'object', 'properties': <String, dynamic>{}},
          },
        ]);

        expect(registry.mcpToolCount, greaterThanOrEqualTo(1));
        final tool = registry.getTool('custom_mcp_tool');
        expect(tool, isNotNull);
        expect(tool!.isMcp, true);
        expect(tool.source, ToolSource.mcp);
      });

      test('clearMcpTools removes all MCP tools', () {
        registry.injectMcpTools([
          <String, dynamic>{
            'name': 'mcp1',
            'description': '',
            'input_schema': <String, dynamic>{'type': 'object', 'properties': <String, dynamic>{}},
          },
        ]);
        registry.clearMcpTools();
        expect(registry.mcpToolCount, 0);
      });
    });

    group('browser tools', () {
      test('injectBrowserTools adds browser tools', () {
        final tool = ToolDefinition(
          name: 'browser_navigate',
          description: 'Navigate to URL',
          category: ToolCategory.search,
          inputSchema: {},
          source: ToolSource.browser,
        );
        registry.injectBrowserTools([tool]);
        expect(registry.browserToolCount, greaterThanOrEqualTo(1));
        expect(registry.getTool('browser_navigate')!.isBrowser, true);
      });

      test('clearBrowserTools removes all browser tools', () {
        registry.injectBrowserTools([
          ToolDefinition(
            name: 'browser_test', description: '',
            category: ToolCategory.search, inputSchema: {}, source: ToolSource.browser,
          ),
        ]);
        registry.clearBrowserTools();
        expect(registry.browserToolCount, 0);
      });
    });

    group('getToolsByCategory', () {
      test('filters tools by category', () {
        final fileTools = registry.getToolsByCategory(ToolCategory.file);
        expect(fileTools, isNotEmpty);
        for (final t in fileTools) {
          expect(t.category, ToolCategory.file);
        }
      });
    });

    group('ToolDefinition', () {
      test('toAnthropicSchema produces valid format', () {
        final def = ToolDefinition(
          name: 'test_tool', description: 'A test', category: ToolCategory.system,
          inputSchema: {
            'type': 'object',
            'properties': {'q': {'type': 'string'}},
            'required': ['q'],
          },
        );
        final schema = def.toAnthropicSchema();
        expect(schema['name'], 'test_tool');
        expect(schema['description'], 'A test');
        expect(schema['input_schema'], contains('properties'));
      });
    });
  });
}
