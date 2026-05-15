import 'dart:typed_data';
import 'package:xml/xml.dart';
import '../domain/document_converter_interface.dart';
import '../domain/document_converter_result.dart';
import '../document_converter.dart' show kCancelToken;
import '../services/cancellation_token.dart';
import '../services/zip_reader.dart';
import 'docx_omml.dart' as omml;

typedef DocxImageCallback = Future<String> Function(Uint8List imageBytes, String? altText);

class DocxConverter extends BaseDocumentConverter {
  @override
  int get priority => ConverterPriority.specific;

  @override
  List<String> get supportedMimeTypes => const [
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      ];

  @override
  List<String> get supportedExtensions => const ['.docx'];

  @override
  String get formatName => 'DOCX';

  static DocxImageCallback? imageCallback;

  static const _headingStyles = {
    'Heading1': '# ', 'heading1': '# ',
    'Heading2': '## ', 'heading2': '## ',
    'Heading3': '### ', 'heading3': '### ',
    'Heading4': '#### ', 'heading4': '#### ',
    'Heading5': '##### ', 'heading5': '##### ',
    'Heading6': '###### ', 'heading6': '###### ',
    'Title': '# ', 'Subtitle': '### ',
  };

  final Map<String, String> _listTypeCache = {};

  @override
  Future<DocumentConverterResult> convert({
    required Uint8List bytes,
    String? mimeType,
    String? fileName,
    Map<String, dynamic>? options,
  }) async {
    final cancelToken = options?[kCancelToken] as CancellationToken?;

    // Use selective ZIP reader — only decompresses requested files
    final zip = ZipReader.tryParse(bytes);
    if (zip == null) throw Exception('Invalid DOCX: not a valid ZIP archive');

    final docXml = zip.readFileAsString('word/document.xml');
    if (docXml == null) throw Exception('Invalid DOCX: missing word/document.xml');

    cancelToken?.throwIfCancelled();

    // Pre-process OMML math → LaTeX
    var xmlString = docXml;
    try { xmlString = omml.preProcessMath(xmlString); } catch (_) {}

    final document = XmlDocument.parse(xmlString);
    final styleMap = _loadStyles(zip);
    final numMap = _loadNumbering(zip);
    final relsMap = _loadRelationships(zip);
    _listTypeCache.clear();

    cancelToken?.throwIfCancelled();

    // Collect image descriptions with concurrency limit (max 3 parallel)
    final imageDescs = <String, String>{};
    if (imageCallback != null && relsMap.isNotEmpty) {
      final factories = <Future<void> Function()>[];
      for (final entry in relsMap.entries) {
        if (entry.value.startsWith('media/')) {
          factories.add(() async {
            try {
              final imgBytes = zip.readFile('word/${entry.value}');
              if (imgBytes != null) {
                final desc = await imageCallback!(imgBytes, null);
                if (desc.isNotEmpty) imageDescs[entry.key] = desc;
              }
            } catch (_) {}
          });
        }
      }
      if (factories.isNotEmpty) {
        await runWithConcurrency(factories, concurrency: 3, cancelToken: cancelToken);
      }
    }

    cancelToken?.throwIfCancelled();

    final buf = StringBuffer();

    // Header
    for (final hdrName in ['word/header1.xml', 'word/header2.xml', 'word/header3.xml']) {
      _appendPartText(zip, hdrName, buf, prefix: '> ', divider: '\n> ');
      buf.writeln();
    }

    // Body
    final body = document.findElements('w:body').firstOrNull;
    if (body != null) {
      for (final child in body.childElements) {
        cancelToken?.throwIfCancelled();
        switch (child.localName) {
          case 'p':
            _writeParagraph(child, buf, styleMap, numMap, relsMap, imageDescs);
            break;
          case 'tbl':
            _writeTable(child, buf);
            break;
          case 'sectPr':
          case 'toc':
            break;
        }
      }
    }

    // Footer
    for (final ftrName in ['word/footer1.xml', 'word/footer2.xml', 'word/footer3.xml']) {
      buf.writeln();
      _appendPartText(zip, ftrName, buf, prefix: '> ', divider: '\n> ');
    }

    final md = buf.toString().trim();
    final title = _extractTitle(document) ?? _findCoreTitle(zip);

    return DocumentConverterResult(
      markdownContent: md,
      title: title,
      mimeType: mimeType,
      detectedFormat: 'docx',
    );
  }

  Map<String, String> _loadRelationships(ZipReader zip) {
    final map = <String, String>{};
    final xml = zip.readFileAsString('word/_rels/document.xml.rels');
    if (xml == null) return map;
    for (final rel in XmlDocument.parse(xml).findAllElements('Relationship')) {
      final rId = rel.getAttribute('Id');
      final target = rel.getAttribute('Target');
      if (rId != null && target != null) map[rId] = target;
    }
    return map;
  }

  Map<String, String> _loadStyles(ZipReader zip) {
    final map = <String, String>{};
    final xml = zip.readFileAsString('word/styles.xml');
    if (xml == null) return map;
    for (final style in XmlDocument.parse(xml).findAllElements('w:style')) {
      final id = style.getAttribute('w:styleId');
      final name = style.findElements('w:name').firstOrNull?.getAttribute('w:val');
      if (id != null && name != null) map[id] = name;
    }
    return map;
  }

  Map<String, String> _loadNumbering(ZipReader zip) {
    final map = <String, String>{};
    final xml = zip.readFileAsString('word/numbering.xml');
    if (xml == null) return map;
    final doc = XmlDocument.parse(xml);

    for (final numEl in doc.findAllElements('w:num')) {
      final numId = numEl.getAttribute('w:numId');
      final absId = numEl.findElements('w:abstractNumId').firstOrNull?.getAttribute('w:val');
      if (numId != null && absId != null) map[numId] = absId;
    }

    for (final absNum in doc.findAllElements('w:abstractNum')) {
      final absId = absNum.getAttribute('w:abstractNumId');
      if (absId == null) continue;
      for (final lvl in absNum.findAllElements('w:lvl')) {
        final ilvl = lvl.getAttribute('w:ilvl') ?? '0';
        final numFmt = lvl.findElements('w:numFmt').firstOrNull?.getAttribute('w:val') ?? '';
        _listTypeCache['$absId:$ilvl'] = numFmt == 'bullet' ? '- ' : '1. ';
      }
    }
    return map;
  }

  String? _extractTitle(XmlDocument doc) {
    for (final el in doc.findAllElements('dc:title')) {
      final t = el.innerText.trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  String? _findCoreTitle(ZipReader zip) {
    final xml = zip.readFileAsString('docProps/core.xml') ?? zip.readFileAsString('docProps/app.xml');
    if (xml == null) return null;
    return _extractTitle(XmlDocument.parse(xml));
  }

  void _appendPartText(ZipReader zip, String path, StringBuffer buf, {String prefix = '', String divider = '\n'}) {
    final xml = zip.readFileAsString(path);
    if (xml == null) return;
    final doc = XmlDocument.parse(xml);
    final lines = <String>[];
    for (final para in doc.findAllElements('w:p')) {
      final text = para.findAllElements('w:t').map((t) => t.innerText).join('').trim();
      if (text.isNotEmpty) lines.add('$prefix$text');
    }
    if (lines.isNotEmpty) buf.writeln(lines.join(divider));
  }

  void _writeParagraph(
    XmlElement para, StringBuffer buf,
    Map<String, String> styleMap, Map<String, String> numMap,
    Map<String, String> relsMap, Map<String, String> imageDescs,
  ) {
    final pPr = para.findElements('w:pPr').firstOrNull;

    if (pPr?.findElements('w:rPr').any((e) => e.findElements('w:del').isNotEmpty) == true) return;
    if (para.children.whereType<XmlElement>().any((e) => e.localName == 'del')) return;

    final pStyle = pPr?.findElements('w:pStyle').firstOrNull?.getAttribute('w:val') ?? '';
    final styleName = styleMap[pStyle] ?? pStyle;

    final numPr = pPr?.findElements('w:numPr').firstOrNull;
    final numId = numPr?.findElements('w:numId').firstOrNull?.getAttribute('w:val');
    final ilvl = int.tryParse(numPr?.findElements('w:ilvl').firstOrNull?.getAttribute('w:val') ?? '0') ?? 0;

    final parts = <String>[];
    String? linkHref;
    int imageCount = 0;

    for (final instr in para.findAllElements('w:instrText')) {
      final m = RegExp(r'HYPERLINK "([^"]*)"').firstMatch(instr.innerText);
      if (m != null) linkHref = m.group(1);
    }

    for (final run in para.findElements('w:r')) {
      final rPr = run.findElements('w:rPr').firstOrNull;

      if (rPr?.findElements('w:del').isNotEmpty == true) continue;
      if (run.parent is XmlElement && (run.parent as XmlElement).localName == 'del') continue;

      final b = rPr?.findElements('w:b').isNotEmpty == true;
      final i = rPr?.findElements('w:i').isNotEmpty == true;
      final strike = rPr?.findElements('w:strike').isNotEmpty == true;

      final drawings = run.findElements('w:drawing');
      if (drawings.isNotEmpty) {
        imageCount++;
        String? altText;
        String? rId;
        for (final drawing in drawings) {
          for (final docPr in drawing.findAllElements('wp:docPr')) {
            altText = docPr.getAttribute('descr') ?? docPr.getAttribute('name');
            break;
          }
          for (final blip in drawing.findAllElements('a:blip')) {
            rId = blip.getAttribute('r:embed');
            break;
          }
        }
        if (rId != null && imageDescs.containsKey(rId)) {
          parts.add(' *[Image: ${imageDescs[rId]}]* ');
        } else {
          parts.add(' ![${altText ?? 'Image $imageCount'}](${altText ?? 'Image $imageCount'}) ');
        }
        continue;
      }

      if (run.findElements('w:pict').isNotEmpty) {
        imageCount++;
        parts.add(' ![Image $imageCount](Image $imageCount) ');
        continue;
      }

      String text = run.findAllElements('w:t').map((t) => t.innerText).join('');
      if (run.findAllElements('w:delText').isNotEmpty) continue;
      if (run.findElements('w:tab').isNotEmpty) text = '\t';
      if (text.isEmpty) continue;

      if (b) text = '**$text**';
      if (i) text = '*$text*';
      if (strike) text = '~~$text~~';
      parts.add(text);
    }

    if (parts.isEmpty) { buf.writeln(); return; }

    var line = parts.join('');
    if (linkHref != null && linkHref.isNotEmpty) line = '[$line]($linkHref)';

    final headingPrefix = _headingStyles[styleName];
    if (headingPrefix != null) {
      buf.writeln('$headingPrefix${line.replaceAll(RegExp(r'\*{1,3}'), '').trim()}');
      return;
    }

    if (numId != null) {
      final absId = numMap[numId] ?? numId;
      final prefix = _listTypeCache['$absId:$ilvl'] ?? _listTypeCache['$absId:0'] ?? '- ';
      buf.writeln('${"  " * ilvl}$prefix$line');
      return;
    }

    if (parts.length == 1 && parts.first.startsWith('**') && parts.first.endsWith('**') && parts.first.length < 80) {
      buf.writeln('###### ${parts.first.replaceAll('**', '')}');
      return;
    }

    buf.writeln(line);
  }

  bool _hasHeaderRow(XmlElement table) {
    final firstRow = table.findElements('w:tr').firstOrNull;
    if (firstRow == null) return false;
    final firstRowCells = firstRow.findElements('w:tc').toList();
    if (firstRowCells.isEmpty) return false;

    int boldCells = 0;
    for (final tc in firstRowCells) {
      if (tc.findAllElements('w:r').any((r) =>
          r.findElements('w:rPr').firstOrNull?.findElements('w:b').isNotEmpty == true)) {
        boldCells++;
      }
    }
    return boldCells > 0 && boldCells >= firstRowCells.length / 2;
  }

  void _writeTable(XmlElement table, StringBuffer buf) {
    final rows = <List<String>>[];
    for (final tr in table.findElements('w:tr')) {
      final trPr = tr.findElements('w:trPr').firstOrNull;
      if (trPr?.findElements('w:del').isNotEmpty == true) continue;

      final cells = <String>[];
      final tcElements = tr.findElements('w:tc').toList();
      for (int idx = 0; idx < tcElements.length; idx++) {
        final tc = tcElements[idx];
        int span = 1;
        final tcPr = tc.findElements('w:tcPr').firstOrNull;
        if (tcPr != null) {
          final gridSpan = tcPr.findElements('w:gridSpan').firstOrNull;
          if (gridSpan != null) span = int.tryParse(gridSpan.getAttribute('w:val') ?? '1') ?? 1;
        }

        final texts = <String>[];
        for (final para in tc.findElements('w:p')) {
          final ppPr = para.findElements('w:pPr').firstOrNull;
          if (ppPr?.findElements('w:rPr').any((e) => e.findElements('w:del').isNotEmpty) == true) continue;

          if (para.findElements('w:tbl').firstOrNull != null) {
            texts.add('[nested table]');
            continue;
          }
          final line = para.findAllElements('w:t').map((t) => t.innerText).join('');
          if (line.isNotEmpty) texts.add(line);
        }
        cells.add(texts.join(' ').replaceAll('|', '\\|').trim());
        if (span > 1) idx += span - 1;
      }
      if (cells.isNotEmpty) rows.add(cells);
    }

    if (rows.isEmpty) return;

    final colCount = rows.fold<int>(0, (max, r) => r.length > max ? r.length : max);
    for (final row in rows) { while (row.length < colCount) {
      row.add('');
    } }

    buf.writeln();
    if (_hasHeaderRow(table)) {
      buf.writeln('| ${rows.first.join(' | ')} |');
      buf.writeln('| ${List.filled(colCount, '---').join(' | ')} |');
      for (int i = 1; i < rows.length; i++) { buf.writeln('| ${rows[i].join(' | ')} |'); }
    } else {
      for (final row in rows) { buf.writeln('| ${row.join(' | ')} |'); }
    }
    buf.writeln();
  }
}
