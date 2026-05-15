import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:markdown/markdown.dart' as md;

extension _N on md.Element {
  List<md.Node> get n => children ?? const [];
}

/// Markdown → DOCX generator using proper Markdown AST.
class DocxWriter {

  DocxWriter(this.markdown);
  final String markdown;

  Uint8List build() {
    final doc = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    final nodes = doc.parse(markdown);

    final hasContent = nodes.whereType<md.Element>().isNotEmpty;
    if (!hasContent) {
      final archive = Archive();
      archive.addFile(_file('[Content_Types].xml', _contentTypesXml));
      archive.addFile(_file('_rels/.rels', _packageRels));
      archive.addFile(_file('word/_rels/document.xml.rels', _emptyRels()));
      archive.addFile(_file('word/styles.xml', _stylesXml));
      archive.addFile(_file('word/document.xml', _minimalDoc('Empty document')));
      return Uint8List.fromList(ZipEncoder().encode(archive));
    }

    // First pass: collect hyperlinks
    final urls = <String>[];
    final urlToId = <String, String>{};
    _collectUrls(nodes, urls);
    for (int i = 0; i < urls.length; i++) {
      urlToId[urls[i]] = 'rIdH${i + 1}';
    }

    final archive = Archive();
    archive.addFile(_file('[Content_Types].xml', _contentTypesXml));
    archive.addFile(_file('_rels/.rels', _packageRels));
    archive.addFile(_file('word/_rels/document.xml.rels', _docRels(urls, urlToId)));
    archive.addFile(_file('word/styles.xml', _stylesXml));
    archive.addFile(_file('word/document.xml', _buildBody(nodes, urlToId)));

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  void _collectUrls(List<md.Node> nodes, List<String> urls) {
    for (final node in nodes) {
      if (node is md.Element) {
        if (node.tag == 'a') {
          final href = node.attributes['href'] ?? '';
          if (href.isNotEmpty && !urls.contains(href)) urls.add(href);
        }
        _collectUrls(node.n, urls);
      }
    }
  }

  String _buildBody(List<md.Node> nodes, Map<String, String> urlToId) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buf.writeln('<w:document'
        ' xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
        ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
    buf.writeln('  <w:body>');
    for (final node in nodes) {
      if (node is md.Element) _writeBlock(node, buf, 0, urlToId);
    }
    buf.writeln('  </w:body>');
    buf.writeln('</w:document>');
    return buf.toString();
  }

  void _writeBlock(md.Element el, StringBuffer buf, int listLevel, Map<String, String> urlToId) {
    switch (el.tag) {
      case 'h1': _writePara(buf, el.n, urlToId, style: 'Heading1'); break;
      case 'h2': _writePara(buf, el.n, urlToId, style: 'Heading2'); break;
      case 'h3': _writePara(buf, el.n, urlToId, style: 'Heading3'); break;
      case 'h4': _writePara(buf, el.n, urlToId, style: 'Heading4'); break;
      case 'h5': _writePara(buf, el.n, urlToId, style: 'Heading5'); break;
      case 'h6': _writePara(buf, el.n, urlToId, style: 'Heading6'); break;
      case 'p': _writePara(buf, el.n, urlToId); break;
      case 'ul':
        for (final child in el.n) {
          if (child is md.Element && child.tag == 'li') _writeListItem(buf, child, listLevel, false, urlToId);
        }
        break;
      case 'ol':
        for (final child in el.n) {
          if (child is md.Element && child.tag == 'li') _writeListItem(buf, child, listLevel, true, urlToId);
        }
        break;
      case 'blockquote':
        for (final child in el.n) {
          if (child is md.Element) _writeBlock(child, buf, listLevel, urlToId);
        }
        break;
      case 'pre':
        final code = el.n.whereType<md.Element>().where((e) => e.tag == 'code').firstOrNull;
        final text = code != null ? _extractText(code.n) : _extractText(el.n);
        buf.writeln('    <w:p>');
        buf.writeln('      <w:r><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:eastAsia="Courier New"/></w:rPr>');
        buf.writeln('        <w:t xml:space="preserve">${_esc(text)}</w:t></w:r>');
        buf.writeln('    </w:p>');
        break;
      case 'table':
        _writeTable(buf, el, urlToId);
        break;
      case 'hr':
        buf.writeln('    <w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="auto"/></w:pBdr></w:pPr></w:p>');
        break;
    }
  }

  void _writePara(StringBuffer buf, List<md.Node> children, Map<String, String> urlToId, {String? style}) {
    buf.writeln('    <w:p>');
    if (style != null) buf.writeln('      <w:pPr><w:pStyle w:val="$style"/></w:pPr>');
    for (final child in children) {
      _writeInline(child, buf, urlToId);
    }
    buf.writeln('    </w:p>');
  }

  void _writeListItem(StringBuffer buf, md.Element li, int level, bool ordered, Map<String, String> urlToId) {
    buf.writeln('    <w:p>');
    final listStyle = ordered ? 'ListNumber' : 'ListBullet';
    buf.writeln('      <w:pPr>');
    buf.writeln('        <w:pStyle w:val="$listStyle"/>');
    buf.writeln('        <w:ind w:left="${360 + level * 360}" w:hanging="360"/>');
    buf.writeln('      </w:pPr>');

    for (final child in li.n) {
      if (child is md.Element && (child.tag == 'ul' || child.tag == 'ol')) continue;
      _writeInline(child, buf, urlToId);
    }
    buf.writeln('    </w:p>');

    for (final child in li.n) {
      if (child is md.Element && (child.tag == 'ul' || child.tag == 'ol')) {
        for (final subLi in child.n) {
          if (subLi is md.Element && subLi.tag == 'li') {
            _writeListItem(buf, subLi, level + 1, child.tag == 'ol', urlToId);
          }
        }
      }
    }
  }

  void _writeInline(md.Node node, StringBuffer buf, Map<String, String> urlToId) {
    if (node is md.Text) {
      buf.writeln('      <w:r><w:t xml:space="preserve">${_esc(node.text)}</w:t></w:r>');
    } else if (node is md.Element) {
      switch (node.tag) {
        case 'strong':
          for (final c in node.n) {
            _writeInlineWithFormat(c, buf, urlToId, bold: true);
          }
          break;
        case 'em':
          for (final c in node.n) {
            _writeInlineWithFormat(c, buf, urlToId, italic: true);
          }
          break;
        case 'code':
          buf.writeln('      <w:r><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:eastAsia="Courier New"/></w:rPr><w:t xml:space="preserve">${_esc(_extractText(node.n))}</w:t></w:r>');
          break;
        case 'del':
        case 'strikethrough':
          for (final c in node.n) {
            _writeInlineWithFormat(c, buf, urlToId, strike: true);
          }
          break;
        case 'a':
          final href = node.attributes['href'] ?? '';
          final rId = urlToId[href];
          if (rId != null) {
            buf.writeln('      <w:hyperlink r:id="$rId">');
            for (final c in node.n) {
              _writeInlineWithFormat(c, buf, urlToId, link: true);
            }
            buf.writeln('      </w:hyperlink>');
          } else {
            for (final c in node.n) {
              _writeInlineWithFormat(c, buf, urlToId);
            }
          }
          break;
        case 'img':
          final alt = node.attributes['alt'] ?? '';
          buf.writeln('      <w:r><w:t> [Image${alt.isNotEmpty ? ': $alt' : ''}] </w:t></w:r>');
          break;
        case 'br':
          buf.writeln('    </w:p>');
          buf.writeln('    <w:p>');
          break;
        default:
          for (final c in node.n) {
            _writeInline(c, buf, urlToId);
          }
      }
    }
  }

  void _writeInlineWithFormat(md.Node node, StringBuffer buf, Map<String, String> urlToId, {bool bold = false, bool italic = false, bool strike = false, bool link = false}) {
    if (node is md.Text) {
      final rPrParts = <String>[];
      if (bold) rPrParts.add('<w:b/>');
      if (italic) rPrParts.add('<w:i/>');
      if (strike) rPrParts.add('<w:strike/>');
      if (link) rPrParts.add('<w:rStyle w:val="Hyperlink"/>');
      final rPr = rPrParts.isNotEmpty ? '<w:rPr>${rPrParts.join()}</w:rPr>' : '';
      buf.writeln('      <w:r>$rPr<w:t xml:space="preserve">${_esc(node.text)}</w:t></w:r>');
    } else if (node is md.Element) {
      switch (node.tag) {
        case 'strong':
          for (final c in node.n) {
            _writeInlineWithFormat(c, buf, urlToId, bold: true, italic: italic, strike: strike, link: link);
          }
          break;
        case 'em':
          for (final c in node.n) {
            _writeInlineWithFormat(c, buf, urlToId, bold: bold, italic: true, strike: strike, link: link);
          }
          break;
        case 'code':
          for (final c in node.n) {
            _writeInlineWithFormat(c, buf, urlToId, bold: bold, italic: italic, strike: strike, link: link);
          }
          break;
        case 'a':
          final href = node.attributes['href'] ?? '';
          final rId = urlToId[href];
          if (rId != null) {
            buf.writeln('      <w:hyperlink r:id="$rId">');
            for (final c in node.n) {
              _writeInlineWithFormat(c, buf, urlToId, bold: bold, italic: italic, strike: strike, link: true);
            }
            buf.writeln('      </w:hyperlink>');
          } else {
            for (final c in node.n) {
              _writeInlineWithFormat(c, buf, urlToId, bold: bold, italic: italic, strike: strike, link: link);
            }
          }
          break;
        default:
          for (final c in node.n) {
            _writeInlineWithFormat(c, buf, urlToId, bold: bold, italic: italic, strike: strike, link: link);
          }
      }
    }
  }

  void _writeTable(StringBuffer buf, md.Element table, Map<String, String> urlToId) {
    final rows = <List<List<md.Node>>>[];
    for (final child in table.n) {
      if (child is md.Element && (child.tag == 'thead' || child.tag == 'tbody')) {
        for (final tr in child.n) {
          if (tr is md.Element && tr.tag == 'tr') {
            final row = <List<md.Node>>[];
            for (final cell in tr.n) {
              if (cell is md.Element && (cell.tag == 'th' || cell.tag == 'td')) row.add(cell.n);
            }
            if (row.isNotEmpty) rows.add(row);
          }
        }
      }
    }
    if (rows.isEmpty) return;

    final colCount = rows.fold<int>(0, (max, r) => r.length > max ? r.length : max);
    buf.writeln('    <w:tbl>');
    buf.writeln('      <w:tblPr>');
    buf.writeln('        <w:tblStyle w:val="TableGrid"/>');
    buf.writeln('        <w:tblW w:w="5000" w:type="pct"/>');
    buf.writeln('        <w:tblBorders>');
    buf.writeln('          <w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>');
    buf.writeln('          <w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>');
    buf.writeln('          <w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>');
    buf.writeln('          <w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>');
    buf.writeln('        </w:tblBorders>');
    buf.writeln('      </w:tblPr>');

    for (final row in rows) {
      buf.writeln('      <w:tr>');
      for (final cell in row) {
        buf.writeln('        <w:tc>');
        buf.writeln('          <w:p>');
        for (final node in cell) {
          _writeInline(node, buf, urlToId);
        }
        buf.writeln('          </w:p>');
        buf.writeln('        </w:tc>');
      }
      buf.writeln('      </w:tr>');
    }
    buf.writeln('    </w:tbl>');
  }

  String _extractText(List<md.Node> nodes) {
    final buf = StringBuffer();
    for (final node in nodes) {
      if (node is md.Text) {
        buf.write(node.text);
      } else if (node is md.Element) buf.write(_extractText(node.n));
    }
    return buf.toString();
  }

  String _esc(String s) => s
      .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;').replaceAll("'", '&apos;');

  String _minimalDoc(String text) => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document'
      ' xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
      ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '  <w:body><w:p><w:r><w:t>${_esc(text)}</w:t></w:r></w:p></w:body>'
      '</w:document>';

  ArchiveFile _file(String path, String content) {
    final bytes = utf8.encode(content);
    return ArchiveFile(path, bytes.length, bytes);
  }

  String _docRels(List<String> urls, Map<String, String> urlToId) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buf.writeln('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    buf.writeln('  <Relationship Id="rIdS" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');
    for (final url in urls) {
      final id = urlToId[url]!;
      buf.writeln('  <Relationship Id="$id" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="${_esc(url)}" TargetMode="External"/>');
    }
    buf.writeln('</Relationships>');
    return buf.toString();
  }

  String _emptyRels() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>';

  // ─── Template XML ────────────────────────────────────────────────────

  static String get _contentTypesXml => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''';

  static String get _packageRels => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

  static String get _stylesXml => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:styleId="Normal"><w:name w:val="Normal"/><w:rPr><w:sz w:val="22"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="Heading 1"/><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="Heading 2"/><w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="Heading 3"/><w:rPr><w:b/><w:sz w:val="24"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading4"><w:name w:val="Heading 4"/><w:rPr><w:b/><w:sz w:val="22"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading5"><w:name w:val="Heading 5"/><w:rPr><w:b/><w:i/><w:sz w:val="22"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading6"><w:name w:val="Heading 6"/><w:rPr><w:i/><w:sz w:val="22"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="ListBullet"><w:name w:val="List Bullet"/><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr></w:style>
  <w:style w:type="paragraph" w:styleId="ListNumber"><w:name w:val="List Number"/><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="2"/></w:numPr></w:pPr></w:style>
  <w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:rPr><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr></w:style>
  <w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/></w:tblBorders></w:tblPr></w:style>
  <w:num w:numId="1"><w:abstractNumId w:val="1"/></w:num>
  <w:num w:numId="2"><w:abstractNumId w:val="2"/></w:num>
  <w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/><w:lvlJc w:val="left"/></w:lvl></w:abstractNum>
  <w:abstractNum w:abstractNumId="2"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/><w:lvlJc w:val="left"/></w:lvl></w:abstractNum>
</w:styles>''';
}
