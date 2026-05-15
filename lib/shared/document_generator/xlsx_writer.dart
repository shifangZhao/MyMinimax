import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:markdown/markdown.dart' as md;
import '../utils/file_utils.dart';

extension _N on md.Element {
  List<md.Node> get n => children ?? const [];
}

/// Markdown table / CSV → XLSX generator.
class XlsxWriter {

  XlsxWriter(this.input);
  final String input;

  Uint8List build() {
    final rows = _parseInput();
    final archive = Archive();

    final sharedStrings = <String>[];
    final cellRefs = <List<String>>[];

    for (final row in rows) {
      final refs = <String>[];
      for (final cell in row) {
        if (_isNumeric(cell)) {
          refs.add(cell);
        } else {
          sharedStrings.add(cell);
          refs.add('s:${sharedStrings.length - 1}');
        }
      }
      cellRefs.add(refs);
    }

    final maxCol = rows.fold<int>(0, (max, r) => r.length > max ? r.length : max);

    archive.addFile(_file('[Content_Types].xml', _contentTypes));
    archive.addFile(_file('_rels/.rels', _packageRels));
    archive.addFile(_file('xl/_rels/workbook.xml.rels', _workbookRels));
    archive.addFile(_file('xl/workbook.xml', _buildWorkbookXml('Sheet 1')));
    archive.addFile(_file('xl/sharedStrings.xml', _buildSharedStrings(sharedStrings)));
    archive.addFile(_file('xl/styles.xml', _stylesXml));
    archive.addFile(_file('xl/worksheets/sheet1.xml', _buildSheetXml(cellRefs, maxCol)));

    final encoder = ZipEncoder();
    return Uint8List.fromList(encoder.encode(archive));
  }

  List<List<String>> _parseInput() {
    // Try Markdown AST tables first
    if (input.contains('|')) {
      final doc = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
      final nodes = doc.parse(input);
      final rows = <List<String>>[];
      for (final node in nodes) {
        if (node is md.Element && node.tag == 'table') {
          void collectRows(md.Element parent) {
            for (final child in parent.n) {
              if (child is md.Element) {
                if (child.tag == 'thead' || child.tag == 'tbody') {
                  collectRows(child);
                } else if (child.tag == 'tr') {
                  final row = <String>[];
                  for (final cell in child.n) {
                    if (cell is md.Element && (cell.tag == 'th' || cell.tag == 'td')) {
                      row.add(_extractText(cell.n).trim());
                    }
                  }
                  if (row.isNotEmpty) rows.add(row);
                }
              }
            }
          }
          collectRows(node);
        }
      }
      if (rows.isNotEmpty) return rows;
    }

    // Fall back to CSV
    final delimiter = _detectDelimiter(input);
    final rows = <List<String>>[];
    for (final line in input.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      rows.add(_splitCSV(trimmed, delimiter));
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

  String _detectDelimiter(String text) {
    final firstLine = text.split('\n').first;
    final commas = ','.allMatches(firstLine).length;
    final tabs = '\t'.allMatches(firstLine).length;
    final semicolons = ';'.allMatches(firstLine).length;
    if (tabs >= commas && tabs >= semicolons) return '\t';
    if (semicolons > commas) return ';';
    return ',';
  }

  List<String> _splitCSV(String line, [String delimiter = ',']) {
    final fields = <String>[];
    bool inQuotes = false;
    final current = StringBuffer();
    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') { current.write('"'); i++; }
        else { inQuotes = !inQuotes; }
      } else if (c == delimiter && !inQuotes) {
        fields.add(current.toString().trim());
        current.clear();
      } else {
        current.write(c);
      }
    }
    fields.add(current.toString().trim());
    return fields;
  }

  bool _isNumeric(String s) => double.tryParse(s) != null;

  String _buildWorkbookXml(String sheetName) => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="${_esc(sheetName)}" sheetId="1" r:id="rId1"/></sheets>
</workbook>''';

  String _buildSharedStrings(List<String> strings) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buf.writeln('<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="${strings.length}" uniqueCount="${strings.length}">');
    for (final s in strings) {
      buf.writeln('  <si><t>${_esc(s)}</t></si>');
    }
    buf.writeln('</sst>');
    return buf.toString();
  }

  String _buildSheetXml(List<List<String>> cellRefs, int maxCol) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buf.writeln('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>');
    for (int r = 0; r < cellRefs.length; r++) {
      buf.writeln('    <row r="${r + 1}">');
      for (int c = 0; c < cellRefs[r].length; c++) {
        final ref = cellRefs[r][c];
        final col = FileUtils.colNumToLetter(c);
        if (ref.startsWith('s:')) {
          buf.writeln('      <c r="$col${r + 1}" t="s"><v>${ref.substring(2)}</v></c>');
        } else {
          buf.writeln('      <c r="$col${r + 1}"><v>$ref</v></c>');
        }
      }
      buf.writeln('    </row>');
    }
    buf.writeln('</sheetData></worksheet>');
    return buf.toString();
  }

  String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  ArchiveFile _file(String path, String content) {
    final bytes = utf8.encode(content);
    return ArchiveFile(path, bytes.length, bytes);
  }

  static String get _contentTypes => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>''';

  static String get _packageRels => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';

  static String get _workbookRels => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';

  static String get _stylesXml => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
  <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
</styleSheet>''';
}
