import 'dart:typed_data';
import 'package:xml/xml.dart';
import '../domain/document_converter_interface.dart';
import '../domain/document_converter_result.dart';
import '../document_converter.dart' show kCancelToken;
import '../services/cancellation_token.dart';
import '../services/zip_reader.dart';
import '../../utils/file_utils.dart';

enum _CellType { string, numeric, empty }

class XlsxConverter extends BaseDocumentConverter {
  @override
  int get priority => ConverterPriority.specific;

  @override
  List<String> get supportedMimeTypes => const [
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ];

  @override
  List<String> get supportedExtensions => const ['.xlsx', '.xlsm'];

  @override
  String get formatName => 'XLSX';

  static const int _pageSize = 500;
  static const int _maxRowsPerSheet = 50000;

  @override
  Future<DocumentConverterResult> convert({
    required Uint8List bytes,
    String? mimeType,
    String? fileName,
    Map<String, dynamic>? options,
  }) async {
    final cancelToken = options?[kCancelToken] as CancellationToken?;

    final zip = ZipReader.tryParse(bytes);
    if (zip == null) throw Exception('Invalid XLSX: not a valid ZIP archive');

    cancelToken?.throwIfCancelled();

    // Shared strings
    final sharedStrings = <String>[];
    final boldSiIndices = <int>{};
    final ssXml = zip.readFileAsString('xl/sharedStrings.xml');
    if (ssXml != null) {
      final siElements = XmlDocument.parse(ssXml).findAllElements('si').toList();
      for (int idx = 0; idx < siElements.length; idx++) {
        final si = siElements[idx];
        final text = si.findAllElements('t').map((t) => t.innerText).join('');
        sharedStrings.add(text);
        if (si.findElements('rPr').isNotEmpty ||
            si.findAllElements('r').any((r) => r.findElements('rPr').isNotEmpty)) {
          boldSiIndices.add(idx);
        }
      }
    }

    cancelToken?.throwIfCancelled();

    // Sheet names
    final sheetNames = <String>[];
    final wbXml = zip.readFileAsString('xl/workbook.xml');
    if (wbXml != null) {
      for (final sheet in XmlDocument.parse(wbXml).findAllElements('sheet')) {
        sheetNames.add(sheet.getAttribute('name') ?? '');
      }
    }

    // Find worksheet files (selective — only reads XML entry names, not content)
    final sheetPaths = zip.findMatching('xl/worksheets/sheet*.xml');
    if (sheetPaths.isEmpty) throw Exception('Invalid XLSX: no worksheets found');

    final buf = StringBuffer();

    for (int i = 0; i < sheetPaths.length; i++) {
      cancelToken?.throwIfCancelled();

      final sheetName = i < sheetNames.length ? sheetNames[i] : 'Sheet${i + 1}';
      final xmlString = zip.readFileAsString(sheetPaths[i]);
      if (xmlString == null) continue;
      final doc = XmlDocument.parse(xmlString);

      // Merged cells
      final mergedCells = <int, Map<int, String>>{};
      final mergeCellsEl = doc.findElements('mergeCells').firstOrNull;
      if (mergeCellsEl != null) {
        for (final mc in mergeCellsEl.findElements('mergeCell')) {
          final ref = mc.getAttribute('ref') ?? '';
          final parts = ref.split(':');
          if (parts.length != 2) continue;
          final (startCol, startRow) = _parseRef(parts[0]);
          final (endCol, endRow) = _parseRef(parts[1]);
          final masterKey = '$startRow,$startCol';
          for (int r = startRow; r <= endRow; r++) {
            for (int c = startCol; c <= endCol; c++) {
              if (r == startRow && c == startCol) continue;
              mergedCells.putIfAbsent(r, () => {});
              mergedCells[r]![c] = masterKey;
            }
          }
        }
      }

      // Rows
      final rows = <int, Map<int, String>>{};
      for (final row in doc.findAllElements('row')) {
        final rowNum = int.tryParse(row.getAttribute('r') ?? '') ?? 0;
        final cells = <int, String>{};
        for (final c in row.findAllElements('c')) {
          final ref = c.getAttribute('r') ?? '';
          final colLetter = ref.replaceAll(RegExp(r'\d'), '');
          final colNum = _colLetterToNum(colLetter);
          String value = '';

          if (c.getAttribute('t') == 's') {
            final v = c.findElements('v').firstOrNull?.innerText;
            final idx = int.tryParse(v ?? '') ?? -1;
            if (idx >= 0 && idx < sharedStrings.length) value = sharedStrings[idx];
          } else if (c.getAttribute('t') == 'inlineStr') {
            value = c.findAllElements('t').map((t) => t.innerText).join('');
          } else {
            value = c.findElements('v').firstOrNull?.innerText ?? '';
          }
          cells[colNum] = value;
        }
        if (cells.isNotEmpty) rows[rowNum] = cells;
      }

      // Apply merges
      for (final entry in mergedCells.entries) {
        for (final cell in entry.value.entries) {
          final parts = cell.value.split(',');
          final masterRow = int.tryParse(parts[0]) ?? 0;
          final masterCol = int.tryParse(parts[1]) ?? 0;
          rows.putIfAbsent(entry.key, () => {});
          rows[entry.key]!.putIfAbsent(cell.key, () => rows[masterRow]?[masterCol] ?? '');
        }
      }

      if (rows.isEmpty) continue;

      final sortedRows = rows.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
      final maxCol = sortedRows.fold<int>(0, (max, e) {
        final m = e.value.keys.fold<int>(0, (a, b) => a > b ? a : b);
        return m > max ? m : max;
      });

      final dataRows = sortedRows.length > _maxRowsPerSheet
          ? sortedRows.sublist(0, _maxRowsPerSheet)
          : sortedRows;
      if (dataRows.isEmpty) continue;

      final hasHeader = _hasHeaderRow(doc, boldSiIndices);

      final headers = <String>[];
      final int dataStartIndex;
      if (hasHeader) {
        final firstRow = dataRows.first.value;
        for (int c = 0; c <= maxCol; c++) {
          headers.add(firstRow[c] ?? FileUtils.colNumToLetter(c));
        }
        dataStartIndex = 1;
      } else {
        for (int c = 0; c <= maxCol; c++) {
          headers.add('Column ${FileUtils.colNumToLetter(c)}');
        }
        dataStartIndex = 0;
      }

      final totalDataRows = dataRows.length - dataStartIndex;
      final totalPages = totalDataRows > 0 ? (totalDataRows / _pageSize).ceil() : 1;

      for (int page = 0; page < totalPages; page++) {
        cancelToken?.throwIfCancelled();

        final start = dataStartIndex + page * _pageSize;
        final end = start + _pageSize < dataRows.length ? start + _pageSize : dataRows.length;

        if (page > 0) buf.writeln('\n---\n');
        if (totalPages > 1) {
          buf.writeln('**$sheetName (${page + 1}/$totalPages)**\n');
        } else {
          buf.writeln('## $sheetName\n');
        }

        buf.writeln('| ${headers.join(' | ')} |');
        buf.writeln('| ${List.filled(maxCol + 1, '---').join(' | ')} |');

        for (int ri = start; ri < end; ri++) {
          final rowData = dataRows[ri].value;
          final cells = <String>[];
          for (int c = 0; c <= maxCol; c++) {
            cells.add((rowData[c] ?? '').replaceAll('\n', ' ').replaceAll('|', '\\|'));
          }
          buf.writeln('| ${cells.join(' | ')} |');
        }
      }

      if (sortedRows.length > _maxRowsPerSheet) {
        buf.writeln('\n*...truncated ${sortedRows.length - _maxRowsPerSheet} more rows (${sortedRows.length} total)*');
      }
      buf.writeln();
    }

    return DocumentConverterResult(
      markdownContent: buf.toString().trim(),
      mimeType: mimeType,
      detectedFormat: 'xlsx',
      metadata: {'sheetCount': sheetPaths.length, 'sheetNames': sheetNames},
    );
  }

  static bool _hasHeaderRow(XmlDocument sheetDoc, Set<int> boldSiIndices) {
    final rowElements = sheetDoc.findAllElements('row').toList()
      ..sort((a, b) {
        final aNum = int.tryParse(a.getAttribute('r') ?? '') ?? 0;
        final bNum = int.tryParse(b.getAttribute('r') ?? '') ?? 0;
        return aNum.compareTo(bNum);
      });

    if (rowElements.length < 2) return true;
    final firstRow = rowElements.first;
    final secondRow = rowElements[1];

    for (final cell in firstRow.findAllElements('c')) {
      if (cell.findElements('rPr').isNotEmpty) return true;
      final isEl = cell.findElements('is').firstOrNull;
      if (isEl != null) {
        if (isEl.findElements('rPr').isNotEmpty) return true;
        if (isEl.findAllElements('r').any((r) => r.findElements('rPr').isNotEmpty)) return true;
      }
      if (cell.getAttribute('t') == 's') {
        final idx = int.tryParse(cell.findElements('v').firstOrNull?.innerText ?? '') ?? -1;
        if (idx >= 0 && boldSiIndices.contains(idx)) return true;
      }
    }

    final firstTypes = _getCellTypes(firstRow);
    final secondTypes = _getCellTypes(secondRow);
    final firstAllStrings = firstTypes.isNotEmpty && firstTypes.every((t) => t == _CellType.string);
    final secondHasNumeric = secondTypes.any((t) => t == _CellType.numeric);
    if (firstAllStrings && secondHasNumeric) return true;
    return true;
  }

  static List<_CellType> _getCellTypes(XmlElement row) {
    final types = <_CellType>[];
    for (final cell in row.findAllElements('c')) {
      final t = cell.getAttribute('t');
      if (t == 's' || t == 'inlineStr' || t == 'str') {
        types.add(_CellType.string);
      } else if (t == 'n' || t == null) {
        final v = cell.findElements('v').firstOrNull?.innerText ?? '';
        if (v.isEmpty) {
          types.add(_CellType.empty);
        } else {
          types.add(double.tryParse(v) != null ? _CellType.numeric : _CellType.string);
        }
      } else if (t == 'b') {
        types.add(_CellType.numeric);
      } else {
        types.add(_CellType.empty);
      }
    }
    return types;
  }

  static int _colLetterToNum(String letters) {
    int n = 0;
    for (int i = 0; i < letters.length; i++) {
      n = n * 26 + (letters.codeUnitAt(i) - 'A'.codeUnitAt(0) + 1);
    }
    return n - 1;
  }

  static (int, int) _parseRef(String ref) {
    final letters = ref.replaceAll(RegExp(r'\d'), '');
    final digits = ref.replaceAll(RegExp(r'[A-Za-z]'), '');
    return (_colLetterToNum(letters), (int.tryParse(digits) ?? 1) - 1);
  }
}
