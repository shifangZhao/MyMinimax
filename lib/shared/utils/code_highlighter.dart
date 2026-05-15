import 'package:flutter/material.dart';
import '../../app/theme.dart';

class CodeHighlighter {
  const CodeHighlighter();

  static Color getLanguageColor(String? lang) {
    switch (lang?.toLowerCase()) {
      case 'dart': return const Color(0xFF4F6EF7);
      case 'python': return const Color(0xFF3572A5);
      case 'javascript': return const Color(0xFFF7DF1E);
      case 'bash': return const Color(0xFF89E051);
      case 'json': return const Color(0xFFF5A623);
      case 'yaml': return const Color(0xFFCB171E);
      case 'html': return const Color(0xFFE34F26);
      case 'css': return const Color(0xFF1572B6);
      case 'sql': return const Color(0xFFE38C00);
      case 'markdown': return const Color(0xFF083FA1);
      default: return const Color(0xFF6B7280);
    }
  }

  static String getLanguageDisplayName(String? lang) {
    switch (lang?.toLowerCase()) {
      case 'dart': return 'Dart';
      case 'python': return 'Python';
      case 'javascript': return 'JavaScript';
      case 'bash': return 'Bash';
      case 'json': return 'JSON';
      case 'yaml': return 'YAML';
      case 'html': return 'HTML';
      case 'css': return 'CSS';
      case 'sql': return 'SQL';
      case 'markdown': return 'Markdown';
      default: return lang ?? 'Code';
    }
  }

  static final _languagePatterns = <String, List<_HighlightRule>>{
    'dart': [
      _HighlightType.keyword.r(r'\b(import|export|class|extends|implements|mixin|enum|typedef|abstract|static|final|const|var|late|required|super|this|new|return|if|else|for|while|do|switch|case|break|continue|throw|try|catch|finally|async|await|yield|true|false|null|void|int|double|String|bool|List|Map|Set|Future|Stream|dynamic|Function|is|as|in|assert|with|on|library|part|hide|show|get|set|operator|factory|sealed|base|interface|final)\b'),
      _HighlightType.className.r(r'\b([A-Z][a-zA-Z]*)\b'),
      _HighlightType.string.r(r'"[^"]*"|' "'" r'[^' "'" r']*' + "'"),
      _HighlightType.number.r(r'\b(\d+\.?\d*)\b'),
      _HighlightType.comment.r(r'//[^\n]*'),
      _HighlightType.comment.r(r'/\*[\s\S]*?\*/'),
      _HighlightType.annotation.r(r'\b(@\w+)\b'),
      _HighlightType.builtin.r(r'\b(Widget|BuildContext|State|StatelessWidget|StatefulWidget|Scaffold|Container|Column|Row|Text|Icon|Padding|SizedBox|GestureDetector|InkWell|Navigator|Theme|MediaQuery|ClipRRect|BorderRadius|EdgeInsets|BoxDecoration|TextStyle|FontWeight|Color|Colors|MainAxisAlignment|CrossAxisAlignment|TextEditingController|VoidCallback|ValueChanged|Key|Stream|Duration)\b'),
    ],
    'python': [
      _HighlightType.keyword.r(r'\b(def|class|return|if|elif|else|for|while|import|from|as|try|except|finally|raise|with|yield|lambda|pass|break|continue|and|or|not|in|is|None|True|False|self|async|await|global|nonlocal|assert|del|print)\b'),
      _HighlightType.className.r(r'\b([A-Z][a-zA-Z]*)\b'),
      _HighlightType.string.r(r'"[^"]*"|' "'" r'[^' "'" r']*' + "'"),
      _HighlightType.comment.r(r'#[^\n]*'),
      _HighlightType.number.r(r'\b(\d+\.?\d*)\b'),
      _HighlightType.annotation.r(r'\b(@\w+)\b'),
    ],
    'javascript': [
      _HighlightType.keyword.r(r'\b(const|let|var|function|return|if|else|for|while|do|switch|case|break|continue|throw|try|catch|finally|new|this|class|extends|import|export|default|from|async|await|of|in|typeof|instanceof|true|false|null|undefined|yield|static|get|set|super|debugger)\b'),
      _HighlightType.string.r(r'"[^"]*"|' "'" r'[^' "'" r']*' + "'" + r'|`[^`]*`'),
      _HighlightType.comment.r(r'//[^\n]*'),
      _HighlightType.comment.r(r'/\*[\s\S]*?\*/'),
      _HighlightType.number.r(r'\b(\d+\.?\d*)\b'),
      _HighlightType.builtin.r(r'\b(console|document|window|Math|JSON|Promise|Array|Object|String|Number|Boolean|fetch|setTimeout|setInterval|require|module|process|__dirname|Buffer|Map|Set|Symbol|Proxy|Reflect|Intl|Error|TypeError|RegExp)\b'),
    ],
    'bash': [
      _HighlightType.keyword.r(r'\b(if|then|else|elif|fi|for|while|do|done|case|esac|in|function|return|exit|export|local|readonly|source|alias|unalias|echo|printf|cd|ls|pwd|mkdir|rm|cp|mv|cat|grep|sed|awk|chmod|chown|sudo|curl|wget|git|docker|npm|yarn|pip|python|node|flutter|export|set|unset|shift|trap|declare|typeset|eval|exec|test|true|false)\b'),
      _HighlightType.string.r(r'"[^"]*"|' "'" r'[^' "'" r']*' + "'"),
      _HighlightType.comment.r(r'#[^\n]*'),
      _HighlightType.builtin.r(r'\$\{?[\w_]+\}?'),
      _HighlightType.annotation.r(r'^(\$|\w+@\w+:|/>)\s'),
    ],
    'json': [
      _HighlightType.keyword.r(r'"([^"\\]|\\.)*"\s*:'),
      _HighlightType.string.r(r':\s*"([^"\\]|\\.)*"'),
      _HighlightType.number.r(r':\s*(\d+\.?\d*)'),
      _HighlightType.builtin.r(r':\s*(true|false|null)'),
    ],
    'yaml': [
      _HighlightType.keyword.r(r'^[a-zA-Z_][\w]*:'),
      _HighlightType.string.r(r':\s*"[^"]*"'),
      _HighlightType.comment.r(r'#[^\n]*'),
      _HighlightType.number.r(r':\s*(\d+\.?\d*)'),
    ],
    'html': [
      _HighlightType.keyword.r(r'</?\w+[^>]*>'),
      _HighlightType.string.r(r'\w+="[^"]*"|' r"\w+='" r"[^']*'"),
      _HighlightType.comment.r(r'<!--[\s\S]*?-->'),
    ],
    'css': [
      _HighlightType.keyword.r(r'[.#]?[\w-]+\s*\{'),
      _HighlightType.string.r(r':\s*[^;]+'),
      _HighlightType.comment.r(r'/\*[\s\S]*?\*/'),
      _HighlightType.number.r(r'\b(\d+\.?\d*(?:px|em|rem|%|vh|vw|s|ms)?)\b'),
    ],
    'sql': [
      _HighlightType.keyword.r(r'\b(SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|ADD|COLUMN|INDEX|DROP|JOIN|LEFT|RIGHT|INNER|OUTER|ON|AND|OR|NOT|NULL|IS|IN|LIKE|BETWEEN|ORDER|BY|GROUP|HAVING|LIMIT|OFFSET|UNION|ALL|AS|DISTINCT|COUNT|SUM|AVG|MAX|MIN|PRIMARY|KEY|FOREIGN|REFERENCES|CASCADE|DEFAULT|TEXT|INTEGER|VARCHAR|BOOLEAN|TIMESTAMP|BEGIN|COMMIT|ROLLBACK|TRANSACTION|EXISTS|IF|THEN|ELSE|END|CASE|WHEN|ASC|DESC)\b', caseSensitive: false),
      _HighlightType.number.r(r'\b(\d+\.?\d*)\b'),
      _HighlightType.string.r(r'"[^"]*"|' "'" r'[^' "'" r']*' + "'"),
      _HighlightType.comment.r(r'--[^\n]*'),
    ],
    'markdown': [
      _HighlightType.keyword.r(r'^#{1,6}\s.*$'),
      _HighlightType.string.r(r'\[.*?\]\(.*?\)'),
      _HighlightType.string.r(r'`[^`]+`'),
      _HighlightType.builtin.r(r'\*\*.*?\*\*'),
    ],
  };

  TextSpan highlight(String code, String? language, {bool isDark = false}) {
    final patterns = _languagePatterns[language?.toLowerCase()] ??
        _languagePatterns['dart']!;

    final spans = <TextSpan>[];
    _highlightLines(code, patterns, spans, isDark);

    return TextSpan(
      style: TextStyle(
        fontFamily: 'JetBrains Mono',
        fontSize: 13,
        height: 1.5,
        color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary,
      ),
      children: spans,
    );
  }

  void _highlightLines(
    String code,
    List<_HighlightRule> patterns,
    List<TextSpan> spans,
    bool isDark,
  ) {
    final lines = code.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: '\n'));
      _highlightLine(lines[i], patterns, spans, isDark);
    }
  }

  void _highlightLine(
    String line,
    List<_HighlightRule> patterns,
    List<TextSpan> spans,
    bool isDark,
  ) {
    if (line.isEmpty) return;

    final matches = <_Match>[];
    for (final rule in patterns) {
      for (final match in rule.pattern.allMatches(line)) {
        matches.add(_Match(match.start, match.end, rule.type));
      }
    }
    matches.sort((a, b) => a.start.compareTo(b.start));

    int pos = 0;
    for (final m in matches) {
      if (m.start < pos) continue;
      if (m.start > pos) {
        spans.add(TextSpan(text: line.substring(pos, m.start)));
      }
      spans.add(TextSpan(
        text: line.substring(m.start, m.end),
        style: _typeToStyle(m.type, isDark),
      ));
      pos = m.end;
    }
    if (pos < line.length) {
      spans.add(TextSpan(text: line.substring(pos)));
    }
  }

  static TextStyle _typeToStyle(_HighlightType type, bool isDark) {
    switch (type) {
      case _HighlightType.keyword:
        return TextStyle(
          color: isDark ? const Color(0xFFC586C0) : const Color(0xFF7B30A0),
          fontWeight: FontWeight.w600,
        );
      case _HighlightType.string:
        return TextStyle(color: isDark ? const Color(0xFF6A9955) : const Color(0xFF387A1E));
      case _HighlightType.comment:
        return TextStyle(
          color: isDark ? const Color(0xFF6A9955) : const Color(0xFF6A9955),
          fontStyle: FontStyle.italic,
        );
      case _HighlightType.number:
        return TextStyle(color: isDark ? const Color(0xFFB5CEA8) : const Color(0xFF0E5E6D));
      case _HighlightType.className:
        return TextStyle(color: isDark ? const Color(0xFF4EC9B0) : const Color(0xFF267F99));
      case _HighlightType.builtin:
        return TextStyle(color: isDark ? const Color(0xFFDCDCAA) : const Color(0xFF795E26));
      case _HighlightType.annotation:
        return TextStyle(color: isDark ? const Color(0xFFD7BA7D) : const Color(0xFFC5862A));
    }
  }
}

enum _HighlightType { keyword, string, comment, number, className, builtin, annotation }

extension _HLExt on _HighlightType {
  _HighlightRule r(String pattern, {bool caseSensitive = true}) =>
      _HighlightRule(RegExp(pattern, caseSensitive: caseSensitive), this);
}

class _HighlightRule {
  const _HighlightRule(this.pattern, this.type);
  final RegExp pattern;
  final _HighlightType type;
}

class _Match {
  const _Match(this.start, this.end, this.type);
  final int start;
  final int end;
  final _HighlightType type;
}
