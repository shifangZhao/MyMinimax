import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:markdown/markdown.dart' as md;

extension _N on md.Element {
  List<md.Node> get n => children ?? const [];
}

/// Markdown → PPTX generator using proper Markdown AST.
class PptxWriter {

  PptxWriter(this.markdown);
  final String markdown;

  Uint8List build() {
    final doc = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    final nodes = doc.parse(markdown);
    final slides = _splitSlides(nodes);

    final archive = Archive();
    final slideXmls = <String>[];
    final slideRels = StringBuffer();
    final presRels = StringBuffer();
    final overrides = StringBuffer();

    for (int i = 0; i < slides.length; i++) {
      final xml = _buildSlide(slides[i]);
      final sp = 'ppt/slides/slide${i + 1}.xml';
      slideXmls.add(xml);
      archive.addFile(_file(sp, xml));
      slideRels.writeln('  <Relationship Id="rId${i + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i + 1}.xml"/>');
      presRels.writeln('  <p:sldId id="${256 + i}" r:id="rId${i + 2}"/>');
      overrides.writeln('  <Override PartName="/$sp" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>');
    }

    archive.addFile(_file('[Content_Types].xml', _contentTypes(overrides.toString())));
    archive.addFile(_file('_rels/.rels', _packageRels));
    archive.addFile(_file('ppt/_rels/presentation.xml.rels', _presRels(slideRels.toString())));
    archive.addFile(_file('ppt/presentation.xml', _buildPresXml(slides.length, presRels.toString())));
    archive.addFile(_file('ppt/slideMasters/slideMaster1.xml', _slideMaster));
    archive.addFile(_file('ppt/theme/theme1.xml', _themeXml));
    archive.addFile(_file('ppt/_rels/theme/theme1.xml.rels', _emptyRels));

    final encoder = ZipEncoder();
    return Uint8List.fromList(encoder.encode(archive));
  }

  List<md.Element> _splitSlides(List<md.Node> nodes) {
    final slides = <md.Element>[];
    List<md.Node>? current;

    void flush() {
      if (current != null && current!.isNotEmpty) {
        slides.add(md.Element('div', current));
      }
      current = null;
    }

    for (final node in nodes) {
      if (node is md.Element && node.tag == 'h2') {
        flush();
        current = [node];
      } else if (node is md.Element) {
        current ??= [];
        current!.add(node);
      }
    }
    flush();
    return slides;
  }

  // ─── Slide layout ─────────────────────────────────────────────────────

  static const _slideW = 9144000.0; // EMU
  static const _slideH = 6858000.0;
  static const _marginL = 685800.0;
  static const _marginR = 685800.0;
  static const _contentW = _slideW - _marginL - _marginR;
  static const _titleH = 762000.0;
  static const _lineH = 370840.0;
  static const _paraSpacing = 137160.0;

  String _buildSlide(md.Element slide) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buf.writeln('<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
        ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
        ' xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">');
    buf.writeln('  <p:cSld><p:spTree>');

    final layout = _SlideLayout();
    int shapeId = 1;

    for (final child in slide.n) {
      if (child is! md.Element) continue;

      if ((child.tag == 'h1' || child.tag == 'h2') && !layout.hasTitle) {
        layout.hasTitle = true;
        final text = _extractText(child.n);
        buf.writeln('    <p:sp>');
        buf.writeln('      <p:nvSpPr><p:cNvPr id="$shapeId" name="Title"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>');
        buf.writeln('      <p:spPr><a:xfrm><a:off x="$_marginL" y="${layout.titleY}"/><a:ext cx="$_contentW" cy="$_titleH"/></a:xfrm></p:spPr>');
        buf.writeln('      <p:txBody><a:bodyPr/>');
        buf.writeln('        <a:p><a:r><a:rPr lang="en-US" sz="2800" b="1"/><a:t>${_esc(text)}</a:t></a:r></a:p>');
        buf.writeln('      </p:txBody>');
        buf.writeln('    </p:sp>');
        layout.advance(_titleH);
        shapeId++;
      } else if (child.tag == 'table') {
        final rows = _extractTableRows(child);
        if (rows.isNotEmpty) {
          final tblH = rows.length * _lineH;
          final bodyH = rows.length * _lineH;
          buf.writeln('    <p:graphicFrame>');
          buf.writeln('      <p:nvGraphicFramePr><p:cNvPr id="$shapeId" name="Table"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>');
          buf.writeln('      <p:xfrm><a:off x="$_marginL" y="${layout.y}"/><a:ext cx="$_contentW" cy="$bodyH"/></p:xfrm>');
          buf.writeln('      <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">');
          final colCount = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
          final colW = _contentW ~/ colCount;
          buf.writeln('        <a:tbl><a:tblPr/><a:tblGrid>');
          for (int i = 0; i < colCount; i++) {
            buf.writeln('          <a:gridCol w="$colW"/>');
          }
          buf.writeln('        </a:tblGrid>');
          for (final row in rows) {
            buf.writeln('          <a:tr h="$_lineH">');
            for (final cell in row) {
              buf.writeln('            <a:tc><a:txBody><a:bodyPr/><a:p><a:r><a:rPr lang="en-US" sz="1400"/><a:t>${_esc(cell)}</a:t></a:r></a:p></a:txBody></a:tc>');
            }
            buf.writeln('          </a:tr>');
          }
          buf.writeln('        </a:tbl>');
          buf.writeln('      </a:graphicData></a:graphic>');
          buf.writeln('    </p:graphicFrame>');
          layout.advance(bodyH);
        }
        shapeId++;
      } else if (child.tag == 'ul' || child.tag == 'ol') {
        final items = _listItems(child);
        final listH = items.length * _lineH + _paraSpacing;
        buf.writeln('    <p:sp>');
        buf.writeln('      <p:nvSpPr><p:cNvPr id="$shapeId" name="List"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>');
        buf.writeln('      <p:spPr><a:xfrm><a:off x="$_marginL" y="${layout.y}"/><a:ext cx="$_contentW" cy="$listH"/></a:xfrm></p:spPr>');
        buf.writeln('      <p:txBody><a:bodyPr/>');
        int olIdx = 0;
        for (final item in items) {
          olIdx++;
          final bullet = child.tag == 'ol' ? '$olIdx.' : '•';
          buf.writeln('        <a:p><a:pPr marL="342900" indent="-285750"><a:buChar char="$bullet"/></a:pPr><a:r><a:rPr lang="en-US" sz="1800"/><a:t>${_esc(item)}</a:t></a:r></a:p>');
        }
        buf.writeln('      </p:txBody>');
        buf.writeln('    </p:sp>');
        layout.advance(listH);
        shapeId++;
      } else if (child.tag == 'p') {
        final text = _extractText(child.n).trim();
        if (text.isNotEmpty) {
          final lineCount = (text.length / 70).ceil().clamp(1, 20);
          final paraH = lineCount * _lineH + _paraSpacing;
          buf.writeln('    <p:sp>');
          buf.writeln('      <p:nvSpPr><p:cNvPr id="$shapeId" name="Text"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>');
          buf.writeln('      <p:spPr><a:xfrm><a:off x="$_marginL" y="${layout.y}"/><a:ext cx="$_contentW" cy="$paraH"/></a:xfrm></p:spPr>');
          buf.writeln('      <p:txBody><a:bodyPr/>');
          buf.writeln('        <a:p><a:r><a:rPr lang="en-US" sz="1800"/><a:t>${_esc(text)}</a:t></a:r></a:p>');
          buf.writeln('      </p:txBody>');
          buf.writeln('    </p:sp>');
          layout.advance(paraH);
          shapeId++;
        }
      } else if (child.tag == 'h3' || child.tag == 'h4' || child.tag == 'h5' || child.tag == 'h6') {
        final text = _extractText(child.n).trim();
        if (text.isNotEmpty) {
          final sizes = {'h3': '2400', 'h4': '2000', 'h5': '1800', 'h6': '1600'};
          buf.writeln('    <p:sp>');
          buf.writeln('      <p:nvSpPr><p:cNvPr id="$shapeId" name="Heading"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr/></p:nvSpPr>');
          buf.writeln('      <p:spPr><a:xfrm><a:off x="$_marginL" y="${layout.y}"/><a:ext cx="$_contentW" cy="$_lineH"/></a:xfrm></p:spPr>');
          buf.writeln('      <p:txBody><a:bodyPr/>');
          buf.writeln('        <a:p><a:r><a:rPr lang="en-US" sz="${sizes[child.tag] ?? '1800'}" b="1"/><a:t>${_esc(text)}</a:t></a:r></a:p>');
          buf.writeln('      </p:txBody>');
          buf.writeln('    </p:sp>');
          layout.advance(_lineH);
          shapeId++;
        }
      }
    }

    buf.writeln('  </p:spTree></p:cSld>');
    buf.writeln('</p:sld>');
    return buf.toString();
  }

  List<String> _listItems(md.Element list) {
    final items = <String>[];
    for (final child in list.n) {
      if (child is md.Element && child.tag == 'li') {
        items.add(_extractText(child.n).trim());
      }
    }
    return items;
  }

  List<List<String>> _extractTableRows(md.Element table) {
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
    return rows;
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

  String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  // ─── XML templates ────────────────────────────────────────────────────

  String _buildPresXml(int count, String ids) => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>
  <p:sldIdLst>$ids</p:sldIdLst>
  <p:sldSz cx="$_slideW" cy="$_slideH"/>
</p:presentation>''';

  String _presRels(String slides) => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>
  <Relationship Id="rId100" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>
$slides
</Relationships>''';

  String _contentTypes(String ov) => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
  <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
  <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
$ov
</Types>''';

  ArchiveFile _file(String path, String content) {
    final bytes = utf8.encode(content);
    return ArchiveFile(path, bytes.length, bytes);
  }

  static String get _packageRels => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
</Relationships>''';

  static String get _slideMaster => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld><p:spTree/></p:cSld>
  <p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles>
</p:sldMaster>''';

  static String get _themeXml => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Default">
  <a:themeElements>
    <a:clrScheme name="Default"><a:dk1/><a:lt1/><a:dk2/><a:lt2/><a:accent1/><a:accent2/><a:accent3/><a:accent4/><a:accent5/><a:accent6/><a:hlink/><a:folHlink/></a:clrScheme>
    <a:fontScheme name="Default"><a:majorFont><a:latin typeface="Calibri"/></a:majorFont><a:minorFont><a:latin typeface="Calibri"/></a:minorFont></a:fontScheme>
    <a:fmtScheme name="Default"><a:fillStyleLst/><a:lnStyleLst/><a:effectStyleLst/><a:bgFillStyleLst/></a:fmtScheme>
  </a:themeElements>
</a:theme>''';

  static String get _emptyRels => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>''';
}

class _SlideLayout {
  static const _titleY = 457200.0;
  static const _contentStartY = 1371600.0;
  static const _bottomMargin = 457200.0;
  static const _slideH = 6858000.0;
  double y = _contentStartY;
  bool hasTitle = false;
  double titleY = _titleY;

  void advance(double height) { y += height; }

  bool get hasSpace => y < _slideH - _bottomMargin;
}
