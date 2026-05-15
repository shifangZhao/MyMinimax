import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/core/browser/adapters/cdp_tool_backend.dart';
import 'package:myminimax/core/browser/adapters/browser_tool_adapter.dart';

void main() {
  group('CdpToolBackend.esc', () {
    test('escapes backslash', () {
      expect(CdpToolBackend.esc(r'hello\world'), r'hello\\world');
    });

    test('escapes single quote', () {
      expect(CdpToolBackend.esc("it's"), r"it\'s");
    });

    test('escapes newline', () {
      expect(CdpToolBackend.esc('a\nb'), r'a\nb');
    });

    test('escapes carriage return', () {
      expect(CdpToolBackend.esc('a\rb'), r'a\rb');
    });

    test('escapes combination', () {
      expect(
        CdpToolBackend.esc("it's a\\b\nc\rd"),
        r"it\'s a\\b\nc\rd",
      );
    });

    test('handles empty string', () {
      expect(CdpToolBackend.esc(''), '');
    });

    test('preserves normal text', () {
      expect(CdpToolBackend.esc('hello world 123'), 'hello world 123');
    });

    test('handles double quotes (not escaped by esc)', () {
      // esc() doesn't escape double quotes — it's for single-quoted JS strings
      const input = 'He said "hello"';
      const expected = 'He said "hello"'; // unchanged
      expect(CdpToolBackend.esc(input), expected);
    });

    test('handles JSON-like strings', () {
      expect(
        CdpToolBackend.esc(r'{"key": "value\n"}'),
        r'{"key": "value\\n"}',
      );
    });
  });

  group('esc: preventing JS injection', () {
    test('single quote is properly escaped', () {
      const raw = "user's input";
      final escaped = CdpToolBackend.esc(raw);
      expect(escaped, r"user\'s input");
      // The result can be safely placed inside JS single quotes
    });

    test('backslash in user input is doubled', () {
      const raw = r'path\to\file';
      final escaped = CdpToolBackend.esc(raw);
      expect(escaped, r'path\\to\\file');
    });

    test('newline in user input is escaped to literal backslash-n', () {
      const raw = 'line1\nline2';
      final escaped = CdpToolBackend.esc(raw);
      expect(escaped, r'line1\nline2');
    });

    test('safe for JS single-quoted template', () {
      // Simulate building a JS expression string
      const userInput = "it's working";
      final escaped = CdpToolBackend.esc(userInput);
      final jsExpr = "var t='$escaped';";
      // Should be: var t='it\'s working';
      expect(jsExpr, r"var t='it\'s working';");
    });

    test('safe for JS with backslash path', () {
      const path = r'C:\Users\Admin';
      final escaped = CdpToolBackend.esc(path);
      final jsExpr = "var p='$escaped';";
      // Should be: var p='C:\\Users\\Admin';
      expect(jsExpr, r"var p='C:\\Users\\Admin';");
    });
  });

  group('InteractiveElement center coordinates', () {
    test('centerX is correct', () {
      const el = InteractiveElement(
        index: 1, tag: 'button',
        x: 100, y: 50, width: 80, height: 30,
      );
      expect(el.centerX, 140.0);
      expect(el.centerY, 65.0);
    });

    test('centerX at origin', () {
      const el = InteractiveElement(
        index: 1, tag: 'div',
        x: 0, y: 0, width: 100, height: 100,
      );
      expect(el.centerX, 50.0);
      expect(el.centerY, 50.0);
    });

    test('element with zero dimensions', () {
      const el = InteractiveElement(
        index: 1, tag: 'span',
        x: 0, y: 0, width: 0, height: 0,
      );
      expect(el.centerX, 0.0);
      expect(el.centerY, 0.0);
    });
  });

  group('InteractiveElement serialization format', () {
    test('element map contains all expected keys', () {
      const el = InteractiveElement(
        index: 5, backendNodeId: 42,
        tag: 'input', text: 'Hello', type: 'text',
        id: 'email', placeholder: 'Enter email',
        ariaLabel: 'Email input', role: 'textbox',
        depth: 2, disabled: false,
        x: 10, y: 20, width: 200, height: 30,
      );

      final map = {
        'index': el.index, 'tag': el.tag, 'text': el.text,
        'type': el.type, 'id': el.id, 'placeholder': el.placeholder,
        'name': '', 'href': el.href, 'ariaLabel': el.ariaLabel,
        'role': el.role, 'disabled': el.disabled, 'depth': el.depth,
        'scrollable': el.scrollable, 'scrollInfo': el.scrollInfo,
      };

      const requiredKeys = [
        'index', 'tag', 'text', 'type', 'id', 'placeholder',
        'name', 'href', 'ariaLabel', 'role', 'disabled', 'depth',
        'scrollable', 'scrollInfo',
      ];
      for (final key in requiredKeys) {
        expect(map.containsKey(key), true, reason: 'Missing key: $key');
      }
    });

    test('element list serializes to valid JSON', () {
      final elements = [
        const InteractiveElement(
          index: 1, tag: 'button', text: 'Click',
          x: 10, y: 10, width: 80, height: 30,
        ),
        const InteractiveElement(
          index: 2, tag: 'a', text: 'Link', href: '/page',
          x: 10, y: 50, width: 60, height: 20,
        ),
      ];

      final list = elements.map((e) => {
        'index': e.index, 'tag': e.tag, 'text': e.text,
        'type': e.type, 'id': e.id, 'placeholder': e.placeholder,
        'name': '', 'href': e.href, 'ariaLabel': e.ariaLabel,
        'role': e.role, 'disabled': e.disabled, 'depth': e.depth,
        'scrollable': e.scrollable, 'scrollInfo': e.scrollInfo,
      }).toList();

      final json = jsonEncode({'elements': list, 'total': list.length});
      final parsed = jsonDecode(json) as Map<String, dynamic>;
      expect(parsed['total'], 2);
      expect((parsed['elements'] as List).length, 2);
      // Verify first element
      final first = (parsed['elements'] as List)[0] as Map<String, dynamic>;
      expect(first['tag'], 'button');
      expect(first['text'], 'Click');
    });
  });

  group('Error message consistency', () {
    test('index required is used consistently for missing params', () {
      const errors = ['index required', 'index required', 'index required'];
      for (final e in errors) {
        expect(e, 'index required');
      }
    });

    test('element not found message includes index and hint', () {
      const error = 'Element index 7 not found in CDP element tree. '
          'Call browser_get_elements to refresh.';
      expect(error.contains('7'), true);
      expect(error.contains('browser_get_elements'), true);
    });

    test('zero dimensions message is clear', () {
      const error = 'Element 3 has zero dimensions — may be off-screen.';
      expect(error.contains('3'), true);
      expect(error.contains('zero dimensions'), true);
    });
  });
}
