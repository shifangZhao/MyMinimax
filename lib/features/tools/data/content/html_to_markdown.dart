/// Pure Dart HTML→Markdown converter — instant, no LLM needed.
///
/// Key improvement over @steipete/summarize which requires an LLM API call
/// for markdown conversion. Our version is instant, offline, and preserves:
/// headings, bold/italic, links, lists, tables, code blocks, images, blockquotes.
///
/// CJK-aware: preserves CJK text without inserting extra spaces.
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;

String convertHtmlToMarkdown(String html) {
  final document = parse(html);
  return convertDocumentToMarkdown(document);
}

/// Convert an already-parsed Document to Markdown — no re-parsing.
String convertDocumentToMarkdown(Document document) {
  final body = document.querySelector('body') ?? document;
  final buf = StringBuffer();
  _convertNode(body, buf, 0);
  return buf.toString().trim();
}

void _convertNode(Node node, StringBuffer buf, int depth) {
  if (node is Element) {
    final tag = (node.localName ?? '').toLowerCase();
    switch (tag) {
      case 'h1':
        buf.write('\n\n# ');
        _writeInlineText(node, buf);
        buf.write('\n');
        return;
      case 'h2':
        buf.write('\n\n## ');
        _writeInlineText(node, buf);
        buf.write('\n');
        return;
      case 'h3':
        buf.write('\n\n### ');
        _writeInlineText(node, buf);
        buf.write('\n');
        return;
      case 'h4':
        buf.write('\n\n#### ');
        _writeInlineText(node, buf);
        buf.write('\n');
        return;
      case 'h5':
        buf.write('\n\n##### ');
        _writeInlineText(node, buf);
        buf.write('\n');
        return;
      case 'h6':
        buf.write('\n\n###### ');
        _writeInlineText(node, buf);
        buf.write('\n');
        return;
      case 'p':
        buf.write('\n\n');
        _writeInlineText(node, buf);
        return;
      case 'br':
        buf.write('\n');
        return;
      case 'hr':
        buf.write('\n\n---\n\n');
        return;
      case 'strong':
      case 'b':
        buf.write('**');
        _writeInlineText(node, buf);
        buf.write('**');
        return;
      case 'em':
      case 'i':
        buf.write('*');
        _writeInlineText(node, buf);
        buf.write('*');
        return;
      case 'del':
      case 's':
        buf.write('~~');
        _writeInlineText(node, buf);
        buf.write('~~');
        return;
      case 'sub':
        buf.write('<sub>');
        _writeInlineText(node, buf);
        buf.write('</sub>');
        return;
      case 'sup':
        buf.write('<sup>');
        _writeInlineText(node, buf);
        buf.write('</sup>');
        return;
      case 'code':
        if (_isInsidePre(node)) {
          _writeInlineText(node, buf);
        } else {
          buf.write('`');
          final text = node.text;
          buf.write(_normalizeText(text));
          buf.write('`');
        }
        return;
      case 'pre':
        final lang = _extractCodeLanguage(node);
        buf.write('\n\n```$lang\n');
        buf.write(node.text.trim());
        buf.write('\n```\n');
        return;
      case 'a':
        final href = node.attributes['href'] ?? '';
        buf.write('[');
        _writeInlineText(node, buf);
        buf.write(']($href)');
        return;
      case 'img':
        final alt = node.attributes['alt'] ?? '';
        final src = node.attributes['src'] ?? '';
        if (src.isNotEmpty) {
          buf.write('\n![$alt]($src)\n');
        }
        return;
      case 'blockquote':
        buf.write('\n\n> ');
        _writeInlineText(node, buf);
        return;
      case 'ul':
        buf.write('\n');
        _writeListItems(node, buf, '', '- ', 0);
        buf.write('\n');
        return;
      case 'ol':
        buf.write('\n');
        var idx = 1;
        _writeOrderedListItems(node, buf, '', idx, 0);
        buf.write('\n');
        return;
      case 'table':
        _writeTable(node, buf);
        return;
      case 'thead':
      case 'tbody':
      case 'tfoot':
      case 'tr':
      case 'th':
      case 'td':
        for (final child in node.children) {
          _convertNode(child, buf, depth + 1);
        }
        return;
      default:
        for (final child in node.children) {
          _convertNode(child, buf, depth + 1);
        }
        return;
    }
  } else if (node is Text) {
    final text = node.text;
    if (text.trim().isNotEmpty) {
      buf.write(_normalizeText(text));
    }
  }
}

void _writeInlineText(Element element, StringBuffer buf) {
  for (final child in element.nodes) {
    if (child is Text) {
      buf.write(_normalizeText(child.text));
    } else if (child is Element) {
      _convertInlineElement(child, buf);
    } else {
      buf.write(child.text ?? '');
    }
  }
}

void _convertInlineElement(Element element, StringBuffer buf) {
  final tag = (element.localName ?? '').toLowerCase();
  switch (tag) {
    case 'strong':
    case 'b':
      buf.write('**');
      _writeInlineText(element, buf);
      buf.write('**');
      break;
    case 'em':
    case 'i':
      buf.write('*');
      _writeInlineText(element, buf);
      buf.write('*');
      break;
    case 'del':
    case 's':
      buf.write('~~');
      _writeInlineText(element, buf);
      buf.write('~~');
      break;
    case 'sub':
      buf.write('<sub>');
      _writeInlineText(element, buf);
      buf.write('</sub>');
      break;
    case 'sup':
      buf.write('<sup>');
      _writeInlineText(element, buf);
      buf.write('</sup>');
      break;
    case 'code':
      buf.write('`${_normalizeText(element.text)}`');
      break;
    case 'a':
      final href = element.attributes['href'] ?? '';
      buf.write('[');
      _writeInlineText(element, buf);
      buf.write(']($href)');
      break;
    case 'br':
      buf.write('\n');
      break;
    case 'img':
      final alt = element.attributes['alt'] ?? '';
      final src = element.attributes['src'] ?? '';
      if (src.isNotEmpty) buf.write('![$alt]($src)');
      break;
    default:
      _writeInlineText(element, buf);
  }
}

bool _isInsidePre(Element element) {
  var parent = element.parent;
  while (parent != null) {
    final tag = parent.localName ?? '';
    if (tag == 'pre' || tag == 'code') return true;
    parent = parent.parent;
  }
  return false;
}

void _writeListItems(Element list, StringBuffer buf, String indent, String marker, int depth) {
  for (final child in list.children) {
    if (child.localName != 'li') continue;
    buf.write('\n$indent$marker');
    // Write inline text of the li, but skip nested uls/ols (handle separately)
    _writeListItemContent(child, buf);
    // Recursively handle nested lists inside this li
    for (final nested in child.children) {
      final nestedTag = (nested.localName ?? '').toLowerCase();
      if (nestedTag == 'ul') {
        _writeListItems(nested, buf, '$indent  ', '- ', depth + 1);
      } else if (nestedTag == 'ol') {
        _writeOrderedListItems(nested, buf, '$indent  ', 1, depth + 1);
      }
    }
  }
}

int _writeOrderedListItems(Element list, StringBuffer buf, String indent, int startIdx, int depth) {
  var idx = startIdx;
  for (final child in list.children) {
    if (child.localName != 'li') continue;
    buf.write('\n$indent$idx. ');
    _writeListItemContent(child, buf);
    for (final nested in child.children) {
      final nestedTag = (nested.localName ?? '').toLowerCase();
      if (nestedTag == 'ul') {
        _writeListItems(nested, buf, '$indent  ', '- ', depth + 1);
      } else if (nestedTag == 'ol') {
        idx = _writeOrderedListItems(nested, buf, '$indent  ', idx, depth + 1);
      }
    }
    idx++;
  }
  return idx;
}

void _writeListItemContent(Element li, StringBuffer buf) {
  for (final child in li.nodes) {
    if (child is Text) {
      buf.write(_normalizeText(child.text));
    } else if (child is Element) {
      final tag = (child.localName ?? '').toLowerCase();
      if (tag == 'ul' || tag == 'ol') continue; // handled by parent
      _convertInlineElement(child, buf);
    }
  }
}

void _writeTable(Element table, StringBuffer buf) {
  final rows = <List<String>>[];
  var hasHeader = false;

  void collectRows(Element parent) {
    for (final child in parent.children) {
      final tag = (child.localName ?? '').toLowerCase();
      if (tag == 'thead' || tag == 'tbody' || tag == 'tfoot') {
        collectRows(child);
      } else if (tag == 'tr') {
        final cells = <String>[];
        for (final cell in child.children) {
          final cellTag = (cell.localName ?? '').toLowerCase();
          if (cellTag == 'th') hasHeader = true;
          if (cellTag == 'th' || cellTag == 'td') {
            cells.add(_extractCellText(cell));
          }
        }
        if (cells.isNotEmpty) rows.add(cells);
      }
    }
  }

  collectRows(table);
  if (rows.isEmpty) return;

  final colCount =
      rows.fold<int>(0, (max, row) => row.length > max ? row.length : max);
  for (final row in rows) {
    while (row.length < colCount) {
      row.add('');
    }
  }

  buf.write('\n\n');
  if (hasHeader && rows.isNotEmpty) {
    final header = rows.first;
    buf.write('| ${header.join(' | ')} |\n');
    buf.write('|${List.filled(colCount, '---').join('|')}|\n');
    for (var i = 1; i < rows.length; i++) {
      buf.write('| ${rows[i].join(' | ')} |\n');
    }
  } else {
    for (final row in rows) {
      buf.write('| ${row.join(' | ')} |\n');
    }
  }
  buf.write('\n');
}

String _extractCellText(Element cell) {
  final buf = StringBuffer();
  _writeInlineText(cell, buf);
  return buf.toString().replaceAll('\n', ' ').trim();
}

String _normalizeText(String text) {
  return text
      .replaceAll(' ', ' ')
      .replaceAll(RegExp(r'[\t ]+'), ' ')
      .replaceAll(RegExp(r'\n\s*\n'), '\n')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n[ \t]+'), '\n');
}

/// Extract language from <pre class="language-python"> or <code class="lang-js">.
String _extractCodeLanguage(Element pre) {
  // Check class on <pre> itself and its <code> child
  for (final el in [pre, pre.querySelector('code')]) {
    if (el == null) continue;
    final cls = el.attributes['class'] ?? '';
    // highlight.js / Prism convention: language-xxx or lang-xxx
    final m = RegExp(r'(?:language|lang)-(\w[\w+#-]*)', caseSensitive: false)
        .firstMatch(cls);
    if (m != null) return m.group(1)!.toLowerCase();
  }
  return '';
}
