import 'package:markdown/markdown.dart' as md;

class MarkdownAst {
  MarkdownAst(this.nodes);
  final List<md.Node> nodes;

  factory MarkdownAst.parse(String markdown) {
    final doc = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    return MarkdownAst(doc.parse(markdown));
  }

  T accept<T>(AstVisitor<T> visitor) => visitor.visitNodes(nodes);

  List<md.Node> getNodes() => nodes;
}

abstract class AstVisitor<T> {
  T visitNodes(List<md.Node> nodes);
  T visitElement(md.Element el);
  T visitText(md.Text text);
  defaultResult();
}

class DefaultAstVisitor extends AstVisitor<void> {
  @override
  void visitNodes(List<md.Node> nodes) {
    for (final node in nodes) {
      if (node is md.Element) visitElement(node);
      else if (node is md.Text) visitText(node);
    }
  }

  @override
  void visitElement(md.Element el) {
    visitNodes(el.children ?? const []);
  }

  @override
  void visitText(md.Text text) {}

  @override
  void defaultResult() {}
}

enum MarkdownNodeType {
  document,
  heading,
  paragraph,
  blockquote,
  unorderedList,
  orderedList,
  listItem,
  table,
  tableRow,
  tableCell,
  codeBlock,
  inlineCode,
  bold,
  italic,
  strikethrough,
  hyperlink,
  image,
  lineBreak,
  text,
  horizontalRule,
}

class MarkdownElement {
  MarkdownElement({
    required this.type,
    required this.tag,
    this.attributes = const {},
    required this.children,
    this.level = 0,
    this.columnWidthRatios,
  });

  final MarkdownNodeType type;
  final String tag;
  final Map<String, String> attributes;
  final List<Object> children;
  final int level;
  final List<double>? columnWidthRatios;

  bool get isBlock => _isBlockType(type);

  static bool _isBlockType(MarkdownNodeType t) =>
      t == MarkdownNodeType.document ||
      t == MarkdownNodeType.heading ||
      t == MarkdownNodeType.paragraph ||
      t == MarkdownNodeType.blockquote ||
      t == MarkdownNodeType.unorderedList ||
      t == MarkdownNodeType.orderedList ||
      t == MarkdownNodeType.listItem ||
      t == MarkdownNodeType.table ||
      t == MarkdownNodeType.codeBlock ||
      t == MarkdownNodeType.horizontalRule;
}

class MarkdownText {
  MarkdownText(this.text);
  final String text;
}

class AstToElementConverter extends DefaultAstVisitor {
  AstToElementConverter();

  List<Object> convert(List<md.Node> nodes) {
    final result = <Object>[];
    for (final node in nodes) {
      if (node is md.Element) {
        result.add(_convertElement(node));
      } else if (node is md.Text) {
        result.add(MarkdownText(node.text));
      }
    }
    return result;
  }

  @override
  void visitElement(md.Element el) {
    result!.add(_convertElement(el));
  }

  @override
  void visitText(md.Text text) {
    result!.add(MarkdownText(text.text));
  }

  List<Object>? result;

  MarkdownElement _convertElement(md.Element el) {
    final type = _tagToType(el.tag);
    final children = <Object>[];
    for (final child in el.children ?? const []) {
      if (child is md.Element) {
        children.add(_convertElement(child));
      } else if (child is md.Text) {
        children.add(MarkdownText(child.text));
      }
    }
    List<double>? columnWidthRatios;
    if (type == MarkdownNodeType.table) {
      columnWidthRatios = _computeColumnWidthRatios(el);
    }
    return MarkdownElement(
      type: type,
      tag: el.tag,
      attributes: Map.from(el.attributes),
      children: children,
      level: _extractLevel(el.tag),
      columnWidthRatios: columnWidthRatios,
    );
  }

  List<double>? _computeColumnWidthRatios(md.Element table) {
    final children = table.children ?? const [];
    final tbody = children
        .where((c) => c is md.Element && (c as md.Element).tag == 'tbody')
        .cast<md.Element>()
        .firstOrNull;
    if (tbody == null) return null;

    final separatorRow = (tbody.children ?? const [])
        .where((c) => c is md.Element && (c as md.Element).tag == 'tr')
        .cast<md.Element>()
        .firstOrNull;
    if (separatorRow == null) return null;

    final separatorCells = <String>[];
    final rowChildren = separatorRow.children ?? const [];
    for (final cell in rowChildren) {
      if (cell is md.Element && (cell.tag == 'th' || cell.tag == 'td')) {
        separatorCells.add(_getElementText(cell).trim());
      }
    }
    if (separatorCells.isEmpty) return null;

    final widths = separatorCells.map((s) {
      final clean = s.replaceAll(RegExp(r'[:\-]+'), '');
      final dashCount = RegExp(r'[:\-]+').firstMatch(s)?.group(0)?.length ?? 1;
      if (s.startsWith(':') && s.endsWith(':')) return 1.5;
      if (s.endsWith(':')) return 1.2;
      return 1.0;
    }).toList();
    final total = widths.reduce((a, b) => a + b);
    return widths.map((w) => w / total).toList();
  }

  MarkdownNodeType _tagToType(String tag) {
    switch (tag) {
      case 'h1': case 'h2': case 'h3': case 'h4': case 'h5': case 'h6':
        return MarkdownNodeType.heading;
      case 'p': return MarkdownNodeType.paragraph;
      case 'blockquote': return MarkdownNodeType.blockquote;
      case 'ul': return MarkdownNodeType.unorderedList;
      case 'ol': return MarkdownNodeType.orderedList;
      case 'li': return MarkdownNodeType.listItem;
      case 'table': return MarkdownNodeType.table;
      case 'tr': return MarkdownNodeType.tableRow;
      case 'th': case 'td': return MarkdownNodeType.tableCell;
      case 'pre': return MarkdownNodeType.codeBlock;
      case 'code': return MarkdownNodeType.inlineCode;
      case 'strong': return MarkdownNodeType.bold;
      case 'em': return MarkdownNodeType.italic;
      case 'del': case 'strikethrough': return MarkdownNodeType.strikethrough;
      case 'a': return MarkdownNodeType.hyperlink;
      case 'img': return MarkdownNodeType.image;
      case 'br': return MarkdownNodeType.lineBreak;
      case 'hr': return MarkdownNodeType.horizontalRule;
      default: return MarkdownNodeType.document;
    }
  }

  int _extractLevel(String tag) {
    if (tag.startsWith('h') && tag.length == 2) {
      return int.tryParse(tag[1]) ?? 1;
    }
    return 0;
  }

  String _getElementText(md.Element el) {
    final buf = StringBuffer();
    for (final child in el.children ?? const []) {
      if (child is md.Text) {
        buf.write(child.text);
      } else if (child is md.Element) {
        buf.write(_getElementText(child));
      }
    }
    return buf.toString();
  }
}

List<Object> markdownToAst(String markdown) {
  final doc = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
  final nodes = doc.parse(markdown);
  final converter = AstToElementConverter();
  return converter.convert(nodes);
}
