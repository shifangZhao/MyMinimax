import 'dart:typed_data';
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

extension _N on md.Element {
  List<md.Node> get n => children ?? const [];
}

/// Accumulated inline style during recursive parsing.
class _Style {

  const _Style({this.bold = false, this.italic = false, this.strike = false, this.mono = false, this.link});
  final bool bold;
  final bool italic;
  final bool strike;
  final bool mono;
  final String? link;

  _Style copyWith({bool? bold, bool? italic, bool? strike, bool? mono, String? link}) =>
      _Style(bold: bold ?? this.bold, italic: italic ?? this.italic, strike: strike ?? this.strike, mono: mono ?? this.mono, link: link ?? this.link);

  pw.TextStyle get textStyle => pw.TextStyle(
    fontSize: mono ? 10 : 11,
    fontWeight: bold ? pw.FontWeight.bold : null,
    fontStyle: italic ? pw.FontStyle.italic : null,
    decoration: strike ? pw.TextDecoration.lineThrough : null,
    font: mono ? pw.Font.courier() : null,
    color: link != null ? PdfColors.blue : null,
  );
}

/// Markdown → PDF generator using proper Markdown AST.
class PdfWriter {

  PdfWriter(this.markdown);
  final String markdown;

  Future<Uint8List> build() async {
    final doc = pw.Document();
    final nodes = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored).parse(markdown);

    final widgets = <pw.Widget>[];
    bool firstHeading = true;
    for (final node in nodes) {
      if (node is md.Element) _blockToPdf(node, widgets, 0, firstHeading: firstHeading);
      if (node is md.Element && (node.tag == 'h1' || node.tag == 'h2')) firstHeading = false;
    }

    doc.addPage(pw.MultiPage(
      margin: const pw.EdgeInsets.all(40),
      build: (_) => widgets,
    ));
    return doc.save();
  }

  void _blockToPdf(md.Element el, List<pw.Widget> out, int listDepth, {bool firstHeading = false}) {
    switch (el.tag) {
      case 'h1':
        if (!firstHeading) out.add(pw.SizedBox(height: 12));
        out.add(_heading(el, 24));
        break;
      case 'h2':
        if (!firstHeading) out.add(pw.SizedBox(height: 10));
        out.add(_heading(el, 20));
        break;
      case 'h3': out.add(_heading(el, 16)); break;
      case 'h4': out.add(_heading(el, 14)); break;
      case 'h5': out.add(_heading(el, 13)); break;
      case 'h6': out.add(_heading(el, 12)); break;
      case 'p':
        final spans = _parseInline(el.n, const _Style());
        if (spans.isNotEmpty) {
          out.add(pw.RichText(text: pw.TextSpan(children: spans)));
          out.add(pw.SizedBox(height: 4));
        }
        break;
      case 'ul':
        for (final li in el.n) {
          if (li is md.Element && li.tag == 'li') _listItem(li, false, listDepth, out);
        }
        break;
      case 'ol':
        int idx = 1;
        for (final li in el.n) {
          if (li is md.Element && li.tag == 'li') { _listItem(li, true, listDepth, out, idx); idx++; }
        }
        break;
      case 'table':
        _pdfTable(el, out);
        break;
      case 'pre':
        final text = _extractText(el.n);
        out.add(pw.Container(
          padding: const pw.EdgeInsets.all(8),
          color: PdfColors.grey200,
          child: pw.Text(text, style: pw.TextStyle(fontSize: 9, font: pw.Font.courier())),
        ));
        out.add(pw.SizedBox(height: 6));
        break;
      case 'blockquote':
        for (final child in el.n) {
          if (child is md.Element) _blockToPdf(child, out, listDepth);
        }
        break;
      case 'hr':
        out.add(pw.Divider());
        break;
    }
  }

  pw.Widget _heading(md.Element el, double size) {
    final text = _extractText(el.n);
    return pw.Column(children: [
      pw.SizedBox(height: 8),
      pw.Text(text, style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
    ]);
  }

  void _listItem(md.Element li, bool ordered, int depth, List<pw.Widget> out, [int? index]) {
    final prefix = ordered ? '${index ?? 1}. ' : '• ';
    final spans = <pw.InlineSpan>[];
    for (final child in li.n) {
      if (child is md.Element && (child.tag == 'ul' || child.tag == 'ol')) continue;
      spans.addAll(_parseInline([child], const _Style()));
    }
    out.add(pw.Padding(
      padding: pw.EdgeInsets.only(left: depth * 20.0 + 20),
      child: pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: prefix, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ...spans,
      ])),
    ));
    out.add(pw.SizedBox(height: 2));
    for (final child in li.n) {
      if (child is md.Element && (child.tag == 'ul' || child.tag == 'ol')) {
        int ni = 1;
        for (final subLi in child.n) {
          if (subLi is md.Element && subLi.tag == 'li') { _listItem(subLi, child.tag == 'ol', depth + 1, out, ni); ni++; }
        }
      }
    }
  }

  void _pdfTable(md.Element table, List<pw.Widget> out) {
    final rows = <List<String>>[];
    for (final child in table.n) {
      if (child is md.Element && (child.tag == 'thead' || child.tag == 'tbody')) {
        for (final tr in child.n) {
          if (tr is md.Element && tr.tag == 'tr') {
            final row = <String>[];
            for (final cell in tr.n) {
              if (cell is md.Element && (cell.tag == 'th' || cell.tag == 'td')) {
                row.add(_extractText(cell.n).trim());
              }
            }
            if (row.isNotEmpty) rows.add(row);
          }
        }
      }
    }
    if (rows.isEmpty) return;
    final colCount = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    for (final row in rows) { while (row.length < colCount) {
      row.add('');
    } }
    out.add(pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      cellStyle: const pw.TextStyle(fontSize: 10),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      data: rows,
    ));
    out.add(pw.SizedBox(height: 8));
  }

  /// Recursively parse inline nodes with accumulated style.
  /// `**bold *italic* text**` produces combined bold+italic for "italic".
  List<pw.InlineSpan> _parseInline(List<md.Node> nodes, _Style style) {
    final spans = <pw.InlineSpan>[];
    for (final node in nodes) {
      if (node is md.Text) {
        final widget = style.link != null
            ? pw.TextSpan(text: node.text, style: style.textStyle, annotation: pw.AnnotationLink(style.link!))
            : pw.TextSpan(text: node.text, style: style.textStyle);
        spans.add(widget);
      } else if (node is md.Element) {
        switch (node.tag) {
          case 'strong':
            spans.addAll(_parseInline(node.n, style.copyWith(bold: true)));
            break;
          case 'em':
            spans.addAll(_parseInline(node.n, style.copyWith(italic: true)));
            break;
          case 'code':
            spans.addAll(_parseInline(node.n, style.copyWith(mono: true)));
            break;
          case 'del':
          case 'strikethrough':
            spans.addAll(_parseInline(node.n, style.copyWith(strike: true)));
            break;
          case 'a':
            final href = node.attributes['href'] ?? '';
            spans.addAll(_parseInline(node.n, style.copyWith(link: href.isNotEmpty ? href : null)));
            break;
          case 'img':
            spans.add(pw.TextSpan(
              text: '[Image: ${node.attributes['alt'] ?? ''}]',
              style: style.textStyle.copyWith(fontStyle: pw.FontStyle.italic),
            ));
            break;
          case 'br':
            spans.add(pw.TextSpan(text: '\n', style: style.textStyle));
            break;
          default:
            spans.addAll(_parseInline(node.n, style));
        }
      }
    }
    return spans;
  }

  String _extractText(List<md.Node> nodes) {
    final buf = StringBuffer();
    for (final n in nodes) {
      if (n is md.Text) {
        buf.write(n.text);
      } else if (n is md.Element) buf.write(_extractText(n.n));
    }
    return buf.toString();
  }
}
