import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import '../domain/document_converter_interface.dart';
import '../domain/document_converter_result.dart';
import '../document_converter.dart' show kCancelToken;
import '../services/cancellation_token.dart';
import '../services/zip_reader.dart';

typedef PptxImageCallback = Future<String> Function(Uint8List imageBytes, String? altText);

class PptxConverter extends BaseDocumentConverter {
  @override
  int get priority => ConverterPriority.specific;

  @override
  List<String> get supportedMimeTypes => const [
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      ];

  @override
  List<String> get supportedExtensions => const ['.pptx'];

  @override
  String get formatName => 'PPTX';

  static PptxImageCallback? imageCallback;

  @override
  Future<DocumentConverterResult> convert({
    required Uint8List bytes,
    String? mimeType,
    String? fileName,
    Map<String, dynamic>? options,
  }) async {
    final cancelToken = options?[kCancelToken] as CancellationToken?;

    final zip = ZipReader.tryParse(bytes);
    if (zip == null) throw Exception('Invalid PPTX: not a valid ZIP archive');

    cancelToken?.throwIfCancelled();

    // Slide → relationships
    final slideRels = <String, Map<String, String>>{};
    for (final relsPath in zip.findMatching('ppt/slides/_rels/slide*.rels')) {
      final slideName = 'ppt/slides/${relsPath.split('/').last.replaceAll('.rels', '')}';
      final relsMap = <String, String>{};
      final xml = zip.readFileAsString(relsPath);
      if (xml != null) {
        for (final rel in XmlDocument.parse(xml).findAllElements('Relationship')) {
          final rId = rel.getAttribute('Id');
          final target = rel.getAttribute('Target');
          if (rId != null && target != null) relsMap[rId] = target;
        }
      }
      slideRels[slideName] = relsMap;
    }

    cancelToken?.throwIfCancelled();

    // Image descriptions with concurrency limit (max 3 parallel)
    final imageDescs = <String, String>{};
    if (imageCallback != null) {
      final mediaPaths = zip.findMatching('ppt/media/*');
      if (mediaPaths.isNotEmpty) {
        final factories = mediaPaths.map<Future<void> Function()>((path) => () async {
          try {
            cancelToken?.throwIfCancelled();
            final imgBytes = zip.readFile(path);
            if (imgBytes != null) {
              final desc = await imageCallback!(imgBytes, path.split('/').last);
              if (desc.isNotEmpty) imageDescs[path.split('/').last] = desc;
            }
          } catch (_) {}
        }).toList();
        await runWithConcurrency(factories, concurrency: 3, cancelToken: cancelToken);
      }
    }

    cancelToken?.throwIfCancelled();

    // Slide files
    final slidePaths = zip.findMatching('ppt/slides/slide*.xml')
        .where((p) => !p.contains('/slideLayout') && !p.contains('/slideMaster'))
        .toList()
      ..sort((a, b) {
        final aNum = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        final bNum = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        return aNum.compareTo(bNum);
      });

    // Chart data
    final chartPaths = zip.findMatching('ppt/charts/chart*.xml');
    final chartData = <String, String>{};
    for (final cp in chartPaths) {
      cancelToken?.throwIfCancelled();
      final md = _extractChartDataFromPath(cp, zip);
      if (md != null) chartData[cp] = md;
    }

    // Speaker notes
    final notesMap = <int, String>{};
    for (final notesPath in zip.findMatching('ppt/notesSlides/notesSlide*.xml')) {
      final n = int.tryParse(notesPath.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final xml = zip.readFileAsString(notesPath);
      if (xml != null) {
        final t = XmlDocument.parse(xml).findAllElements('a:t').map((e) => e.innerText).join(' ');
        if (t.trim().isNotEmpty) notesMap[n] = t.trim();
      }
    }

    final buf = StringBuffer();

    for (int i = 0; i < slidePaths.length; i++) {
      cancelToken?.throwIfCancelled();

      final slideNum = i + 1;
      final xmlString = zip.readFileAsString(slidePaths[i]);
      if (xmlString == null) continue;
      final doc = XmlDocument.parse(xmlString);

      String? slideTitle;
      for (final sp in doc.findAllElements('p:sp')) {
        final ph = sp.findElements('p:nvSpPr').firstOrNull?.findElements('p:ph').firstOrNull;
        if (ph != null) {
          final phType = ph.getAttribute('type') ?? '';
          if (phType == 'title' || phType == 'ctrTitle' || phType == 'subTitle') {
            slideTitle = sp.findAllElements('a:t').map((t) => t.innerText).join('').trim();
            break;
          }
        }
      }

      final shapes = <Shape>[];
      final rels = slideRels[slidePaths[i]] ?? <String, String>{};

      void processShapes(XmlElement parent, {int depth = 0}) {
        if (depth > 10) return;
        for (final child in parent.childElements) {
          final tag = child.localName;
          if (tag == 'grpSp' || tag == 'spTree') {
            processShapes(child, depth: depth + 1);
          } else if (tag == 'sp') {
            _extractShape(child, shapes, rels, imageDescs);
          } else if (tag == 'graphicFrame') {
            _extractGraphicFrame(child, shapes, rels, chartData);
          } else if (tag == 'pic') {
            _extractPicture(child, shapes, rels, imageDescs);
          }
        }
      }

      final spTree = doc.findElements('p:spTree').firstOrNull;
      if (spTree != null) processShapes(spTree);

      final hasChart = doc.findAllElements('c:chart').isNotEmpty;
      final hasDiagram = doc.findAllElements('dgm:relIds').isNotEmpty;
      final hasOleObject = doc.findAllElements('p:oleObj').isNotEmpty;
      final allText = doc.findAllElements('a:t').map((t) => t.innerText.trim()).where((t) => t.isNotEmpty).join(' ');
      final textIsSparse = allText.length < 20;

      final notes = notesMap[slideNum];
      final hasContent = shapes.isNotEmpty || allText.isNotEmpty || notes != null;
      if (!hasContent) continue;

      if (slideTitle != null && slideTitle.isNotEmpty) {
        buf.writeln('## Slide $slideNum: $slideTitle');
      } else {
        buf.writeln('## Slide $slideNum');
      }

      final warnings = <String>[];
      if (hasChart) warnings.add('chart');
      if (hasDiagram) warnings.add('diagram');
      if (hasOleObject) warnings.add('embedded object');
      if (textIsSparse && warnings.isNotEmpty) {
        buf.writeln('*Contains: ${warnings.join(", ")}. Text extraction may be limited.*\n');
      }

      for (final shape in shapes) {
        if (shape.type == 'text' && shape.text != null) {
          for (final line in shape.text!.split('\n')) { buf.writeln('- $line'); }
        } else if (shape.type == 'table' && shape.tableRows != null) {
          final rows = shape.tableRows!;
          if (rows.isEmpty) continue;
          final colCount = rows.fold<int>(0, (max, r) => r.length > max ? r.length : max);
          final norm = rows.map((r) { while (r.length < colCount) {
            r.add('');
          } return r; }).toList();
          buf.writeln();
          for (final row in norm) { buf.writeln('| ${row.join(' | ')} |'); }
          buf.writeln();
        } else if (shape.type == 'chart' && shape.text != null) {
          buf.writeln(shape.text);
        } else if (shape.type == 'image' && shape.text != null) {
          buf.writeln('- ${shape.text}');
        }
      }

      final hasRealText = shapes.any((s) => s.type == 'text' || s.type == 'table' || s.type == 'chart');
      if (!hasRealText && allText.isNotEmpty) buf.writeln(allText);

      if (notes != null) buf.writeln('\n> **Speaker Notes:** $notes');
      buf.writeln();
    }

    return DocumentConverterResult(
      markdownContent: buf.toString().trim(),
      mimeType: mimeType,
      detectedFormat: 'pptx',
      metadata: {'slideCount': slidePaths.length},
    );
  }

  void _extractShape(XmlElement sp, List<Shape> shapes, Map<String, String> rels, Map<String, String> imageDescs) {
    final cNvPr = sp.findElements('p:nvSpPr').firstOrNull?.findElements('p:cNvPr').firstOrNull;
    final altText = cNvPr?.getAttribute('descr') ?? cNvPr?.getAttribute('name') ?? '';

    final txBody = sp.findElements('p:txBody').firstOrNull;
    if (txBody != null) {
      final paragraphs = <String>[];
      for (final ap in txBody.findAllElements('a:p')) {
        final line = ap.findAllElements('a:t').map((t) => t.innerText).join('');
        if (line.trim().isNotEmpty) paragraphs.add(line.trim());
      }
      if (paragraphs.isNotEmpty) { shapes.add(Shape(type: 'text', text: paragraphs.join('\n'))); return; }
    }

    final blipFill = sp.findElements('p:blipFill').firstOrNull ?? sp.findElements('p:spPr').firstOrNull?.findElements('a:blipFill').firstOrNull;
    if (blipFill != null) {
      _addImageShape(shapes, blipFill.findElements('a:blip').firstOrNull?.getAttribute('r:embed'), altText, rels, imageDescs);
    }
  }

  void _extractPicture(XmlElement pic, List<Shape> shapes, Map<String, String> rels, Map<String, String> imageDescs) {
    final cNvPr = pic.findElements('p:nvPicPr').firstOrNull?.findElements('p:cNvPr').firstOrNull;
    final altText = cNvPr?.getAttribute('descr') ?? cNvPr?.getAttribute('name') ?? '';
    final blip = pic.findElements('p:blipFill').firstOrNull?.findElements('a:blip').firstOrNull;
    _addImageShape(shapes, blip?.getAttribute('r:embed'), altText, rels, imageDescs);
  }

  void _addImageShape(List<Shape> shapes, String? rEmbed, String altText, Map<String, String> rels, Map<String, String> imageDescs) {
    if (rEmbed != null && rels.containsKey(rEmbed)) {
      final filename = rels[rEmbed]!.split('/').last;
      if (imageDescs.containsKey(filename)) {
        shapes.add(Shape(type: 'image', text: '*[Image: ${imageDescs[filename]}]*'));
      } else {
        shapes.add(Shape(type: 'image', text: '![${altText.isNotEmpty ? altText : filename}](${altText.isNotEmpty ? altText : filename})'));
      }
    } else {
      shapes.add(Shape(type: 'image', text: '![${altText.isNotEmpty ? altText : 'Picture'}](${altText.isNotEmpty ? altText : 'Picture'})'));
    }
  }

  void _extractGraphicFrame(XmlElement gf, List<Shape> shapes, Map<String, String> rels, Map<String, String> chartData) {
    for (final tbl in gf.findAllElements('a:tbl')) {
      final rows = <List<String>>[];
      for (final tr in tbl.findAllElements('a:tr')) {
        final cells = <String>[];
        for (final tc in tr.findAllElements('a:tc')) {
          cells.add(tc.findAllElements('a:t').map((t) => t.innerText).join(' ').replaceAll('|', '\\|').trim());
        }
        if (cells.isNotEmpty) rows.add(cells);
      }
      if (rows.isNotEmpty) { shapes.add(Shape(type: 'table', tableRows: rows)); return; }
    }

    final chartEl = gf.findElements('c:chart').firstOrNull;
    if (chartEl != null) {
      final chartRId = chartEl.getAttribute('r:id');
      if (chartRId != null && rels.containsKey(chartRId)) {
        final segments = <String>[];
        for (final seg in rels[chartRId]!.split('/')) {
          if (seg == '.' || seg.isEmpty) continue;
          if (seg == '..') { if (segments.isNotEmpty) segments.removeLast(); }
          else { segments.add(seg); }
        }
        final chartPath = 'ppt/${segments.join('/')}';
        if (chartData.containsKey(chartPath)) { shapes.add(Shape(type: 'chart', text: chartData[chartPath]!)); return; }
      }
      shapes.add(Shape(type: 'chart', text: '*[Chart — see original file]*'));
    }
  }

  String? _extractChartDataFromPath(String chartPath, ZipReader zip) {
    try {
      final xml = zip.readFileAsString(chartPath);
      if (xml == null) return null;
      final doc = XmlDocument.parse(xml);

      String? chartTitle;
      final titleEl = doc.findElements('c:title').firstOrNull;
      if (titleEl != null) chartTitle = titleEl.findAllElements('a:t').map((t) => t.innerText).join('').trim();

      final plotArea = doc.findElements('c:plotArea').firstOrNull;
      if (plotArea == null) return null;

      final chartTypes = [
        'barChart', 'bar3DChart', 'lineChart', 'line3DChart',
        'pieChart', 'pie3DChart', 'areaChart', 'area3DChart',
        'radarChart', 'scatterChart', 'bubbleChart',
        'doughnutChart', 'surfaceChart', 'surface3DChart', 'stockChart', 'ofPieChart',
      ];
      XmlElement? chartEl;
      String chartTypeName = '';
      for (final ct in chartTypes) {
        chartEl = plotArea.findElements('c:$ct').firstOrNull;
        if (chartEl != null) { chartTypeName = ct; break; }
      }
      if (chartEl == null) return null;

      String grouping = '';
      final groupingEl = chartEl.findElements('c:grouping').firstOrNull;
      if (groupingEl != null) grouping = groupingEl.getAttribute('val') ?? '';

      final categories = <String>[];
      for (final catEl in chartEl.findElements('c:cat')) {
        final multiLvl = catEl.findElements('c:multiLvlStrRef').firstOrNull;
        if (multiLvl != null) {
          for (final lvl in multiLvl.findAllElements('c:lvl')) {
            for (final pt in lvl.findAllElements('c:pt')) {
              final v = pt.findElements('c:v').firstOrNull?.innerText ?? '';
              if (v.isNotEmpty && !categories.contains(v)) categories.add(v);
            }
          }
          continue;
        }

        final strRef = catEl.findElements('c:strRef').firstOrNull ?? catEl.findElements('c:numRef').firstOrNull;
        if (strRef != null) {
          final cache = strRef.findElements('c:strCache').firstOrNull ?? strRef.findElements('c:numCache').firstOrNull;
          if (cache != null) {
            for (final pt in cache.findAllElements('c:pt')) {
              categories.add(pt.findElements('c:v').firstOrNull?.innerText ?? '');
            }
          } else {
            final f = strRef.findElements('c:f').firstOrNull?.innerText ?? '';
            if (f.isNotEmpty) categories.add('[Data: $f]');
          }
        }
      }

      final seriesList = <_ChartSeries>[];
      for (final ser in chartEl.findAllElements('c:ser')) {
        String? seriesName;
        final tx = ser.findElements('c:tx').firstOrNull;
        if (tx != null) {
          final txStrRef = tx.findElements('c:strRef').firstOrNull;
          if (txStrRef != null) {
            final txCache = txStrRef.findElements('c:strCache').firstOrNull;
            seriesName = txCache?.findElements('c:v').map((v) => v.innerText).join('') ?? '';
            if (seriesName.isEmpty) {
              seriesName = txStrRef.findElements('c:f').firstOrNull?.innerText ?? '';
            }
          }
          if (seriesName == null || seriesName.isEmpty) {
            seriesName = tx.findElements('c:v').map((v) => v.innerText).join('');
          }
        }
        seriesName = (seriesName != null && seriesName.isNotEmpty) ? seriesName : 'Series ${seriesList.length + 1}';

        final values = <String>[];
        final numRef = ser.findElements('c:val').firstOrNull?.findElements('c:numRef').firstOrNull;
        if (numRef != null) {
          final cache = numRef.findElements('c:numCache').firstOrNull;
          if (cache != null) {
            for (final pt in cache.findAllElements('c:pt')) {
              values.add(pt.findElements('c:v').firstOrNull?.innerText ?? '');
            }
          } else {
            final f = numRef.findElements('c:f').firstOrNull?.innerText ?? '';
            if (f.isNotEmpty) values.add('[Data: $f]');
          }
        }
        seriesList.add(_ChartSeries(name: seriesName, values: values));
      }

      if (seriesList.isEmpty) return null;

      final typeLabel = _chartTypeLabel(chartTypeName, grouping);
      final fullTitle = [if (chartTitle != null && chartTitle.isNotEmpty) chartTitle, if (typeLabel.isNotEmpty) typeLabel].join(' — ');
      final buf = StringBuffer();
      buf.writeln('**Chart${fullTitle.isNotEmpty ? ': $fullTitle' : ''}**\n');

      final header = ['Category', ...seriesList.map((s) => s.name)];
      final colCount = header.length;
      buf.writeln('| ${header.join(' | ')} |');
      buf.writeln('| ${List.filled(colCount, '---').join(' | ')} |');

      int maxRows = categories.isNotEmpty ? categories.length : seriesList.fold(0, (m, s) => math.max(m, s.values.length));
      for (int r = 0; r < maxRows; r++) {
        final row = [r < categories.length ? categories[r] : ''];
        for (final s in seriesList) { row.add(r < s.values.length ? s.values[r] : ''); }
        buf.writeln('| ${row.join(' | ')} |');
      }
      return buf.toString();
    } catch (e) {
      debugPrint('PptxConverter: Chart data extraction failed for $chartPath: $e');
      return null;
    }
  }

  String _chartTypeLabel(String typeName, String grouping) {
    const nameMap = {
      'barChart': 'Bar', 'bar3DChart': '3D Bar', 'lineChart': 'Line', 'line3DChart': '3D Line',
      'pieChart': 'Pie', 'pie3DChart': '3D Pie', 'areaChart': 'Area', 'area3DChart': '3D Area',
      'radarChart': 'Radar', 'scatterChart': 'Scatter', 'bubbleChart': 'Bubble',
      'doughnutChart': 'Doughnut', 'surfaceChart': 'Surface', 'surface3DChart': '3D Surface',
      'stockChart': 'Stock', 'ofPieChart': 'Pie of Pie',
    };
    const groupLabel = {'stacked': 'Stacked', 'percentStacked': '100% Stacked', 'clustered': 'Clustered', 'standard': ''};
    final base = nameMap[typeName] ?? typeName;
    final group = groupLabel[grouping] ?? grouping;
    return group.isNotEmpty ? '$group $base' : base;
  }
}

class _ChartSeries { _ChartSeries({required this.name, required this.values}); final String name; final List<String> values; }

class Shape {
  Shape({required this.type, this.text, this.tableRows});
  final String type;
  final String? text;
  final List<List<String>>? tableRows;
}
