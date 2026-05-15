import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:xml/xml.dart';
import '../document_converter/services/zip_reader.dart';

/// In-place text editor for Office Open XML files (DOCX/XLSX/PPTX).
///
/// Strategy: unzip → edit XML text nodes → rezip. Uses [ZipReader] for
/// selective decompression to keep memory low on mobile.
///
/// **Cross-paragraph matching** (DOCX/PPTX): if [oldStr] spans multiple
/// paragraphs or shapes, the editor joins them with sentinel separators
/// before searching. This handles the most common user intent ("change
/// these three lines to something else") without requiring a Markdown
/// round-trip.
///
/// **Limitation**: text split across XML with *different formatting* inside
/// a single run cannot be matched reliably. For complex structural edits,
/// prefer: convert → edit Markdown → regenerate.
class OfficeEditor {
  // ─── Public API ──────────────────────────────────────────────────────

  static Uint8List editDocx(Uint8List bytes, String oldStr, String newStr, {bool replaceAll = false}) {
    const targets = [
      'word/document.xml',
      'word/header1.xml', 'word/header2.xml', 'word/header3.xml',
      'word/footer1.xml', 'word/footer2.xml', 'word/footer3.xml',
    ];
    return _editMulti(bytes, targets, replaceAll, (xml) => _docxEditor(xml, oldStr, newStr));
  }

  static Uint8List editXlsx(Uint8List bytes, String oldStr, String newStr, {bool replaceAll = false}) {
    final zip = ZipReader.tryParse(bytes);
    final targets = ['xl/sharedStrings.xml'];
    if (zip != null) {
      for (final name in zip.fileNames) {
        if (RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(name)) targets.add(name);
      }
    }
    return _editMulti(bytes, targets, replaceAll, (xml) {
      final result = _xlsxEditor(xml, oldStr, newStr);
      if (result != null) return result;
      // Fallback: edit inline <t> elements in sheet data
      if (xml.contains('sheetData')) return _inlineSheetEditor(xml, oldStr, newStr);
      return null;
    });
  }

  static Uint8List editPptx(Uint8List bytes, String oldStr, String newStr, {bool replaceAll = false}) {
    return _editPattern(bytes, RegExp(r'^ppt/slides/slide\d+\.xml$'), replaceAll,
        (xml) => _pptxEditor(xml, oldStr, newStr));
  }

  // ─── Text extraction (for readFile hints) ────────────────────────────

  static String extractDocxText(Uint8List bytes, {int limit = 15}) {
    try {
      final zip = ZipReader.tryParse(bytes);
      final xml = zip?.readFileAsString('word/document.xml');
      if (xml == null) return '';
      final doc = XmlDocument.parse(xml);
      final lines = <String>[];
      for (final p in doc.findAllElements('w:p')) {
        final text = p.findAllElements('w:t').map((t) => t.innerText).join('').trim();
        if (text.isNotEmpty) lines.add(text.length > 120 ? '${text.substring(0, 120)}…' : text);
      }
      return lines.take(limit).join('\n');
    } catch (_) { return ''; }
  }

  static String extractXlsxText(Uint8List bytes, {int limit = 20}) {
    try {
      final zip = ZipReader.tryParse(bytes);
      final xml = zip?.readFileAsString('xl/sharedStrings.xml');
      if (xml == null) return '';
      final doc = XmlDocument.parse(xml);
      final lines = <String>[];
      for (final si in doc.findAllElements('si')) {
        final text = si.findAllElements('t').map((t) => t.innerText).join('').trim();
        if (text.isNotEmpty) lines.add(text);
      }
      return lines.take(limit).join('\n');
    } catch (_) { return ''; }
  }

  static String extractPptxText(Uint8List bytes, {int limit = 15}) {
    try {
      final zip = ZipReader.tryParse(bytes);
      if (zip == null) return '';
      final lines = <String>[];
      for (final name in zip.fileNames) {
        if (!RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(name)) continue;
        final xml = zip.readFileAsString(name);
        if (xml == null) continue;
        final doc = XmlDocument.parse(xml);
        for (final sp in doc.findAllElements('p:sp')) {
          final text = sp.findAllElements('a:t').map((t) => t.innerText).join('').trim();
          if (text.isNotEmpty && text.length > 2) lines.add(text);
        }
      }
      return lines.take(limit).join('\n');
    } catch (_) { return ''; }
  }

  // ─── ZIP I/O (using ZipReader for read, ZipEncoder for write) ────────

  static Uint8List _editMulti(
    Uint8List bytes, List<String> targets, bool replaceAll,
    String? Function(String xml) editor,
  ) {
    final zip = ZipReader.tryParse(bytes);
    if (zip == null) throw Exception('Invalid Office file: not a valid ZIP archive');

    final newArchive = Archive();
    final targetSet = targets.toSet();
    bool modified = false;

    for (final name in zip.fileNames) {
      List<int> copyBytes;
      String? raw;

      if (targetSet.contains(name)) {
        raw = zip.readFileAsString(name);
        if (raw != null) {
          final result = editor(raw);
          if (result != null) {
            copyBytes = utf8.encode(result);
            modified = true;
          } else {
            copyBytes = _toList(zip.readFile(name));
          }
        } else {
          copyBytes = _toList(zip.readFile(name));
        }
      } else {
        copyBytes = _toList(zip.readFile(name));
      }

      if (copyBytes.isEmpty && raw == null) continue;
      newArchive.add(ArchiveFile(name, copyBytes.length, copyBytes));
    }

    if (!modified) {
      // Fall back to full archive for error message extraction
      final fullArchive = ZipDecoder().decodeBytes(bytes);
      _throwError(fullArchive, null);
    }
    return Uint8List.fromList(ZipEncoder().encode(newArchive));
  }

  static Uint8List _editPattern(
    Uint8List bytes, RegExp pattern, bool replaceAll,
    String? Function(String xml) editor,
  ) {
    final zip = ZipReader.tryParse(bytes);
    if (zip == null) throw Exception('Invalid Office file: not a valid ZIP archive');

    final newArchive = Archive();
    bool modified = false;

    for (final name in zip.fileNames) {
      List<int> copyBytes;
      String? raw;

      if (pattern.hasMatch(name)) {
        raw = zip.readFileAsString(name);
        if (raw != null) {
          final result = editor(raw);
          if (result != null) {
            copyBytes = utf8.encode(result);
            modified = true;
          } else {
            copyBytes = _toList(zip.readFile(name));
          }
        } else {
          copyBytes = _toList(zip.readFile(name));
        }
      } else {
        copyBytes = _toList(zip.readFile(name));
      }

      if (copyBytes.isEmpty) continue;
      newArchive.add(ArchiveFile(name, copyBytes.length, copyBytes));
    }

    if (!modified) {
      final fullArchive = ZipDecoder().decodeBytes(bytes);
      _throwError(fullArchive, null);
    }
    return Uint8List.fromList(ZipEncoder().encode(newArchive));
  }

  static List<int> _toList(Uint8List? data) {
    if (data == null) return const [];
    return List<int>.from(data);
  }

  // ─── Error diagnostics ───────────────────────────────────────────────

  static Never _throwError(Archive archive, String? targetPath) {
    final snippets = <String>[];
    for (final file in archive.files) {
      if (targetPath != null && file.name != targetPath) continue;
      if (!file.name.endsWith('.xml')) continue;
      try {
        final xml = utf8.decode(file.content as List<int>);
        final doc = XmlDocument.parse(xml);
        int count = 0;

        // DOCX paragraphs
        for (final p in doc.findAllElements('w:p')) {
          final line = p.findAllElements('w:t').map((t) => t.innerText).join('');
          final t = line.trim();
          if (t.isNotEmpty && t.length > 2) {
            snippets.add(t.length > 80 ? '${t.substring(0, 80)}…' : t);
            count++;
            if (count >= 8) break;
          }
        }
        // PPTX shapes
        if (snippets.isEmpty) {
          for (final sp in doc.findAllElements('p:sp')) {
            final t = sp.findAllElements('a:t').map((e) => e.innerText).join('').trim();
            if (t.isNotEmpty && t.length > 2) {
              snippets.add(t.length > 80 ? '${t.substring(0, 80)}…' : t);
              count++;
              if (count >= 8) break;
            }
          }
        }
        // XLSX shared strings
        if (snippets.isEmpty) {
          for (final si in doc.findAllElements('si')) {
            final t = si.findAllElements('t').map((e) => e.innerText).join('').trim();
            if (t.isNotEmpty) {
              snippets.add(t.length > 80 ? '${t.substring(0, 80)}…' : t);
              count++;
              if (count >= 8) break;
            }
          }
        }
      } catch (_) {}
      if (snippets.isNotEmpty) break;
    }

    final tip = snippets.isNotEmpty
        ? '\n\nDocument text samples (use for old_str matching, case-sensitive):'
          '\n${snippets.map((s) => '  "$s"').join('\n')}'
        : '\n\nTip: use readFile to inspect actual text. Ensure old_str matches exactly.\n'
          '提示：请先用 readFile 查看文档中的实际文字，确保 old_str 完全一致。';
    const hint = '\n\nNote: for complex edits spanning multiple elements, try:\n'
        '  convert → edit Markdown → regenerate\n'
        '注意：跨多元素的复杂替换建议：转换 → 编辑 Markdown → 重新生成';
    throw Exception('No matching text found. / 未找到匹配文本。$hint$tip');
  }

  // ─── DOCX editor — cross-paragraph matching ──────────────────────────

  static String? _docxEditor(String xml, String oldStr, String newStr) {
    final doc = XmlDocument.parse(xml);
    final paragraphs = doc.findAllElements('w:p').toList();
    if (paragraphs.isEmpty) return null;

    // Phase 1: Try single-paragraph match (preserves existing behavior)
    for (final p in paragraphs) {
      final tEls = _collectTextElements(p, 'w:r', 'w:t');
      if (tEls.isEmpty) continue;
      final parts = tEls.map((t) => t.innerText).toList();
      final joined = parts.join('');
      if (!joined.contains(oldStr)) continue;
      _replaceAll(joined, parts, tEls, oldStr, newStr);
      return doc.toXmlString();
    }

    // Phase 2: Cross-paragraph match — join all paragraphs with newline sentinels
    final allEls = <XmlElement>[];
    final allParts = <String>[];
    final paraBoundaries = <int>[]; // indices in allEls where paragraphs end

    for (final p in paragraphs) {
      final tEls = _collectTextElements(p, 'w:r', 'w:t');
      if (tEls.isNotEmpty) {
        allEls.addAll(tEls);
        for (final t in tEls) { allParts.add(t.innerText); }
        paraBoundaries.add(allParts.length - 1);
      }
    }
    if (allParts.length < 2) return null;

    final joined = allParts.join('');
    if (!joined.contains(oldStr)) return null;

    _replaceAll(joined, allParts, allEls, oldStr, newStr);
    return doc.toXmlString();
  }

  /// Collect all text child elements inside a parent, following the path
  /// of [wrapperTag] → [textTag] (e.g. w:r → w:t).
  static List<XmlElement> _collectTextElements(XmlElement parent, String wrapperTag, String textTag) {
    final result = <XmlElement>[];
    for (final r in parent.findAllElements(wrapperTag)) {
      for (final t in r.findAllElements(textTag)) {
        result.add(t);
      }
    }
    return result;
  }

  // ─── XLSX editor ─────────────────────────────────────────────────────

  static String? _xlsxEditor(String xml, String oldStr, String newStr) {
    final doc = XmlDocument.parse(xml);
    int mods = 0;

    // Search shared strings
    for (final si in doc.findAllElements('si')) {
      final tEls = <XmlElement>[];
      for (final t in si.findAllElements('t')) {
        tEls.add(t);
      }
      if (tEls.isEmpty) continue;
      final parts = tEls.map((t) => t.innerText).toList();
      final joined = parts.join('');
      if (!joined.contains(oldStr)) continue;
      mods += _replaceAll(joined, parts, tEls, oldStr, newStr);
    }
    if (mods > 0) return doc.toXmlString();

    // Inline strings in cells
    for (final c in doc.findAllElements('c')) {
      if (c.getAttribute('t') != 'inlineStr') continue;
      final isEl = c.findAllElements('is').firstOrNull;
      if (isEl == null) continue;
      final tEls = isEl.findAllElements('t').toList();
      if (tEls.isEmpty) continue;
      final parts = tEls.map((t) => t.innerText).toList();
      final joined = parts.join('');
      if (!joined.contains(oldStr)) continue;
      mods += _replaceAll(joined, parts, tEls, oldStr, newStr);
    }
    return mods > 0 ? doc.toXmlString() : null;
  }

  /// Edit inline text in sheet data cells (non-shared-string cells).
  static String? _inlineSheetEditor(String xml, String oldStr, String newStr) {
    final doc = XmlDocument.parse(xml);
    int mods = 0;
    for (final t in doc.findAllElements('t')) {
      if (!t.innerText.contains(oldStr)) continue;
      t.innerText = t.innerText.replaceAll(oldStr, newStr);
      mods++;
    }
    return mods > 0 ? doc.toXmlString() : null;
  }

  // ─── PPTX editor — cross-shape matching ──────────────────────────────

  static String? _pptxEditor(String xml, String oldStr, String newStr) {
    final doc = XmlDocument.parse(xml);

    // Phase 1: Within-shape matching
    for (final sp in doc.findAllElements('p:sp')) {
      final tEls = sp.findAllElements('a:t').toList();
      if (tEls.isEmpty) continue;
      final parts = tEls.map((t) => t.innerText).toList();
      final joined = parts.join('');
      if (!joined.contains(oldStr)) continue;
      _replaceAll(joined, parts, tEls, oldStr, newStr);
      return doc.toXmlString();
    }

    // Phase 2: Cross-shape matching (text spanning multiple shapes)
    final allEls = <XmlElement>[];
    final allParts = <String>[];
    for (final sp in doc.findAllElements('p:sp')) {
      final tEls = sp.findAllElements('a:t').toList();
      if (tEls.isEmpty) continue;
      // Insert a newline boundary between shapes
      if (allParts.isNotEmpty) {
        final boundary = XmlElement(XmlName('a:br'));
        boundary.innerText = '\n';
        allEls.add(boundary);
        allParts.add('\n');
      }
      for (int i = 0; i < tEls.length; i++) {
        allEls.add(tEls[i]);
        allParts.add(tEls[i].innerText);
      }
    }

    if (allParts.length < 2) return null;
    final joined = allParts.join('');
    if (!joined.contains(oldStr)) return null;

    _replaceAll(joined, allParts, allEls, oldStr, newStr);
    return doc.toXmlString();
  }

  // ─── Core: proportional-split replacement ────────────────────────────
  //
  // When [oldStr] spans multiple <w:t> / <a:t> elements (because of
  // formatting boundaries inside a paragraph), we proportionally split
  // [newStr] across the affected elements based on how much of [oldStr]
  // each element contributed.

  static int _replaceAll(
    String fullText, List<String> parts, List<XmlElement> tEls,
    String oldStr, String newStr,
  ) {
    int mods = 0;
    int searchFrom = 0;
    while (true) {
      final idx = fullText.indexOf(oldStr, searchFrom);
      if (idx < 0) break;
      mods++;

      final matchEnd = idx + oldStr.length;

      // Find affected elements
      int first = -1, last = -1, pos = 0;
      for (int i = 0; i < parts.length; i++) {
        final segEnd = pos + parts[i].length;
        if (pos < matchEnd && segEnd > idx) {
          if (first < 0) first = i;
          last = i;
        }
        pos += parts[i].length;
      }
      if (first < 0) { searchFrom = idx + 1; continue; }

      // Calculate each element's contribution to the match
      pos = 0;
      for (int i = 0; i < first; i++) {
        pos += parts[i].length;
      }

      final contribs = <int>[];
      int totalContrib = 0;
      for (int i = first; i <= last; i++) {
        final segStart = pos;
        final segEnd = pos + parts[i].length;
        final overlapStart = idx > segStart ? idx : segStart;
        final overlapEnd = matchEnd < segEnd ? matchEnd : segEnd;
        final overlap = overlapEnd - overlapStart;
        contribs.add(overlap);
        totalContrib += overlap;
        pos += parts[i].length;
      }

      // Distribute newStr proportionally
      int remaining = newStr.length;
      final allocs = <int>[];
      for (int i = first; i <= last; i++) {
        final ci = i - first;
        final alloc = i < last
            ? (totalContrib > 0
                ? ((newStr.length * contribs[ci]) / totalContrib).round().clamp(0, remaining)
                : 0)
            : remaining;
        allocs.add(alloc);
        remaining -= alloc;
      }

      // Apply the replacement to each affected element
      pos = 0;
      for (int i = 0; i < first; i++) {
        pos += parts[i].length;
      }

      int strPos = 0;
      for (int i = first; i <= last; i++) {
        final ci = i - first;
        final segStart = pos;
        final segEnd = pos + parts[i].length;
        final prefixLen = idx > segStart ? (idx - segStart).clamp(0, parts[i].length) : 0;
        final suffixStart = matchEnd < segEnd ? (matchEnd - segStart).clamp(0, parts[i].length) : parts[i].length;
        final suffixLen = parts[i].length - suffixStart;
        final prefix = parts[i].substring(0, prefixLen);
        final suffix = suffixLen > 0 ? parts[i].substring(suffixStart) : '';
        final alloc = allocs[ci];
        final mid = alloc > 0 ? newStr.substring(strPos, strPos + alloc) : '';
        strPos += alloc;

        final newValue = '$prefix$mid$suffix';
        tEls[i].innerText = newValue;
        // xml:space="preserve" for leading/trailing whitespace
        if (newValue.startsWith(' ') || newValue.endsWith(' ') || newValue.isEmpty) {
          tEls[i].setAttribute('xml:space', 'preserve');
        }
        parts[i] = newValue;
        pos += parts[i].length;
      }

      fullText = parts.join('');
      searchFrom = idx + newStr.length;
    }
    return mods;
  }
}
