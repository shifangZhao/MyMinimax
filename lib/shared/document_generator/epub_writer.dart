import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:markdown/markdown.dart' as md;

extension _N on md.Element {
  List<md.Node> get n => children ?? const [];
}

/// Markdown → EPUB 2.0.1 generator.
///
/// Conventions (Pandoc-compatible):
///   #  = book title (metadata + optional title page)
///   ## = chapter boundary (each H2 starts a new .xhtml file)
///   ### and below = sub-headings within chapters
class EpubWriter {

  EpubWriter({
    required this.markdown,
    this.title,
    this.author,
    this.language,
  });
  final String markdown;
  final String? title;
  final String? author;
  final String? language;

  Uint8List build() {
    final doc = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    final nodes = doc.parse(markdown);

    // Extract book title from first H1 if not explicitly provided
    String bookTitle = title ?? '';
    String? firstH1;
    final bodyNodes = <md.Node>[];
    for (final node in nodes) {
      if (node is md.Element && node.tag == 'h1' && bookTitle.isEmpty) {
        bookTitle = _extractText(node.n).trim();
        firstH1 = bookTitle;
      } else {
        bodyNodes.add(node);
      }
    }
    if (bookTitle.isEmpty) bookTitle = 'Untitled';

    // Split body into chapters by H2
    final chapters = <_Chapter>[];
    List<md.Node>? current;
    String? currentTitle;

    for (final node in bodyNodes) {
      if (node is md.Element && node.tag == 'h2') {
        if (current != null) {
          chapters.add(_Chapter(currentTitle ?? 'Untitled', current));
        }
        current = [node];
        currentTitle = _extractText(node.n).trim();
      } else if (current != null) {
        current.add(node);
      } else {
        // Content before first H2 → preamble chapter
        current = [node];
        currentTitle = firstH1 ?? bookTitle;
      }
    }
    if (current != null) {
      chapters.add(_Chapter(currentTitle ?? 'Untitled', current));
    }
    if (chapters.isEmpty) {
      chapters.add(_Chapter(bookTitle, const []));
    }

    // Generate unique IDs for chapters
    final chapterIds = <String>[];
    final usedIds = <String>{};
    for (int i = 0; i < chapters.length; i++) {
      var id = _toId(chapters[i].title);
      if (id.isEmpty || usedIds.contains(id)) {
        id = 'chapter_${i + 1}';
      }
      var uniqueId = id;
      var suffix = 1;
      while (usedIds.contains(uniqueId)) {
        uniqueId = '${id}_$suffix';
        suffix++;
      }
      usedIds.add(uniqueId);
      chapterIds.add(uniqueId);
    }

    // Build ZIP archive
    final archive = Archive();

    // mimetype must be first entry, stored uncompressed
    final mimeBytes = utf8.encode('application/epub+zip');
    final mimeFile = ArchiveFile('mimetype', mimeBytes.length, mimeBytes);
    archive.addFile(mimeFile);

    archive.addFile(_textFile('META-INF/container.xml', _containerXml(token: 'OEBPS/content.opf')));

    // Chapter XHTML files
    final lang = (language != null && language!.isNotEmpty) ? language! : 'en';
    for (int i = 0; i < chapters.length; i++) {
      final xhtml = _buildChapterXhtml(chapters[i], lang, chapterIds[i]);
      archive.addFile(_textFile('OEBPS/${chapterIds[i]}.xhtml', xhtml));
    }

    // OPF metadata
    archive.addFile(_textFile('OEBPS/content.opf', _buildOpf(bookTitle, chapterIds, chapters)));

    // NCX table of contents
    archive.addFile(_textFile('OEBPS/toc.ncx', _buildNcx(bookTitle, chapterIds, chapters)));

    // Minimal CSS
    archive.addFile(_textFile('OEBPS/styles.css', _css));

    final encoder = ZipEncoder();
    return Uint8List.fromList(encoder.encode(archive));
  }

  // ─── Chapter XHTML ─────────────────────────────────────────────────────

  String _buildChapterXhtml(_Chapter chapter, String lang, String chapterId) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<!DOCTYPE html>');
    buf.writeln('<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="$lang" lang="$lang">');
    buf.writeln('<head>');
    buf.writeln('  <title>${_escapeXml(chapter.title)}</title>');
    buf.writeln('  <link rel="stylesheet" href="styles.css" type="text/css"/>');
    buf.writeln('</head>');
    buf.writeln('<body>');
    buf.writeln('<section>');

    for (final node in chapter.nodes) {
      if (node is md.Element) _writeBlock(node, buf);
    }

    buf.writeln('</section>');
    buf.writeln('</body>');
    buf.writeln('</html>');
    return buf.toString();
  }

  void _writeBlock(md.Element el, StringBuffer buf) {
    switch (el.tag) {
      case 'h1': _wrapTag(buf, 'h1', el.n); break;
      case 'h2': _wrapTag(buf, 'h2', el.n); break;
      case 'h3': _wrapTag(buf, 'h3', el.n); break;
      case 'h4': _wrapTag(buf, 'h4', el.n); break;
      case 'h5': _wrapTag(buf, 'h5', el.n); break;
      case 'h6': _wrapTag(buf, 'h6', el.n); break;
      case 'p':
        buf.write('<p>');
        for (final c in el.n) {
          _writeInline(c, buf);
        }
        buf.writeln('</p>');
        break;
      case 'ul':
      case 'ol':
        _writeList(buf, el);
        break;
      case 'blockquote':
        buf.writeln('<blockquote>');
        for (final c in el.n) {
          if (c is md.Element) _writeBlock(c, buf);
        }
        buf.writeln('</blockquote>');
        break;
      case 'pre':
        final code = el.n.whereType<md.Element>().where((e) => e.tag == 'code').firstOrNull;
        final text = code != null ? _extractText(code.n) : _extractText(el.n);
        String? langClass;
        if (code != null) {
          final classes = code.attributes['class'];
          if (classes != null) {
            for (final c in classes.split(' ')) {
              if (c.startsWith('language-')) {
                langClass = c;
                break;
              }
            }
          }
        }
        if (langClass != null) {
          buf.writeln('<pre><code class="${_escapeAttr(langClass)}">${_escapeXml(text)}</code></pre>');
        } else {
          buf.writeln('<pre><code>${_escapeXml(text)}</code></pre>');
        }
        break;
      case 'table':
        _writeTable(buf, el);
        break;
      case 'hr':
        buf.writeln('<hr/>');
        break;
    }
  }

  void _writeList(StringBuffer buf, md.Element list) {
    buf.writeln('<${list.tag}>');
    for (final child in list.n) {
      if (child is md.Element && child.tag == 'li') {
        buf.write('<li>');
        // Inline content of <li> — skip nested lists for separate handling
        for (final c in child.n) {
          if (c is md.Element && (c.tag == 'ul' || c.tag == 'ol')) continue;
          _writeInline(c, buf);
        }
        // Nested lists
        for (final c in child.n) {
          if (c is md.Element && (c.tag == 'ul' || c.tag == 'ol')) {
            _writeList(buf, c);
          }
        }
        buf.writeln('</li>');
      }
    }
    buf.writeln('</${list.tag}>');
  }

  void _writeTable(StringBuffer buf, md.Element table) {
    final rows = <List<List<md.Node>>>[];
    bool hasHeader = false;
    for (final child in table.n) {
      if (child is md.Element) {
        if (child.tag == 'thead') {
          hasHeader = true;
          for (final tr in child.n) {
            if (tr is md.Element && tr.tag == 'tr') _collectRow(rows, tr);
          }
        } else if (child.tag == 'tbody') {
          for (final tr in child.n) {
            if (tr is md.Element && tr.tag == 'tr') _collectRow(rows, tr);
          }
        } else if (child.tag == 'tr') {
          _collectRow(rows, child);
        }
      }
    }
    if (rows.isEmpty) return;

    buf.writeln('<table>');
    for (int i = 0; i < rows.length; i++) {
      final cellTag = (hasHeader && i == 0) ? 'th' : 'td';
      buf.writeln('<tr>');
      for (final cell in rows[i]) {
        buf.write('<$cellTag>');
        for (final node in cell) {
          _writeInline(node, buf);
        }
        buf.writeln('</$cellTag>');
      }
      buf.writeln('</tr>');
    }
    buf.writeln('</table>');
  }

  void _collectRow(List<List<List<md.Node>>> rows, md.Element tr) {
    final row = <List<md.Node>>[];
    for (final cell in tr.n) {
      if (cell is md.Element && (cell.tag == 'th' || cell.tag == 'td')) {
        row.add(cell.n);
      }
    }
    if (row.isNotEmpty) rows.add(row);
  }

  // ─── Inline elements ───────────────────────────────────────────────────

  void _writeInline(md.Node node, StringBuffer buf) {
    if (node is md.Text) {
      buf.write(_escapeXml(node.text));
    } else if (node is md.Element) {
      switch (node.tag) {
        case 'strong': _wrapInline(buf, 'strong', node.n); break;
        case 'em': _wrapInline(buf, 'em', node.n); break;
        case 'del':
        case 'strikethrough': _wrapInline(buf, 'del', node.n); break;
        case 'code':
          buf.write('<code>${_escapeXml(_extractText(node.n))}</code>');
          break;
        case 'a':
          final href = node.attributes['href'] ?? '';
          buf.write('<a href="${_escapeAttr(href)}">');
          for (final c in node.n) {
            _writeInline(c, buf);
          }
          buf.write('</a>');
          break;
        case 'img':
          final src = node.attributes['src'] ?? '';
          final alt = node.attributes['alt'] ?? '';
          buf.write('<img src="${_escapeAttr(src)}" alt="${_escapeAttr(alt)}"/>');
          break;
        case 'br':
          buf.write('<br/>');
          break;
        default:
          for (final c in node.n) {
            _writeInline(c, buf);
          }
      }
    }
  }

  void _wrapTag(StringBuffer buf, String tag, List<md.Node> children) {
    buf.write('<$tag>');
    for (final c in children) {
      _writeInline(c, buf);
    }
    buf.writeln('</$tag>');
  }

  void _wrapInline(StringBuffer buf, String tag, List<md.Node> children) {
    buf.write('<$tag>');
    for (final c in children) {
      _writeInline(c, buf);
    }
    buf.write('</$tag>');
  }

  // ─── OPF metadata ──────────────────────────────────────────────────────

  String _buildOpf(String bookTitle, List<String> chapterIds, List<_Chapter> chapters) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<package xmlns="http://www.idpf.org/2007/opf" xmlns:opf="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="book-id">');
    buf.writeln('  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">');
    buf.writeln('    <dc:identifier id="book-id" opf:scheme="UUID">urn:uuid:${_uuid()}</dc:identifier>');
    buf.writeln('    <dc:title>${_escapeXml(bookTitle)}</dc:title>');
    if (author != null && author!.isNotEmpty) {
      buf.writeln('    <dc:creator opf:role="aut">${_escapeXml(author!)}</dc:creator>');
    }
    buf.writeln('    <dc:language>${(language != null && language!.isNotEmpty) ? language! : 'en'}</dc:language>');
    buf.writeln('    <meta name="generator" content="MyMinimax EpubWriter"/>');
    buf.writeln('  </metadata>');
    buf.writeln('  <manifest>');
    buf.writeln('    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>');
    buf.writeln('    <item id="css" href="styles.css" media-type="text/css"/>');
    for (int i = 0; i < chapterIds.length; i++) {
      buf.writeln('    <item id="${chapterIds[i]}" href="${chapterIds[i]}.xhtml" media-type="application/xhtml+xml"/>');
    }
    buf.writeln('  </manifest>');
    buf.writeln('  <spine toc="ncx">');
    for (final id in chapterIds) {
      buf.writeln('    <itemref idref="$id"/>');
    }
    buf.writeln('  </spine>');
    buf.writeln('</package>');
    return buf.toString();
  }

  // ─── NCX table of contents ─────────────────────────────────────────────

  String _buildNcx(String bookTitle, List<String> chapterIds, List<_Chapter> chapters) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">');
    buf.writeln('<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">');
    buf.writeln('  <head>');
    buf.writeln('    <meta name="dtb:uid" content="urn:uuid:${_uuid()}"/>');
    buf.writeln('    <meta name="dtb:depth" content="1"/>');
    buf.writeln('    <meta name="dtb:totalPageCount" content="0"/>');
    buf.writeln('    <meta name="dtb:maxPageNumber" content="0"/>');
    buf.writeln('  </head>');
    buf.writeln('  <docTitle><text>${_escapeXml(bookTitle)}</text></docTitle>');
    buf.writeln('  <navMap>');
    for (int i = 0; i < chapterIds.length; i++) {
      buf.writeln('    <navPoint id="nav_$i" playOrder="${i + 1}">');
      buf.writeln('      <navLabel><text>${_escapeXml(chapters[i].title)}</text></navLabel>');
      buf.writeln('      <content src="${chapterIds[i]}.xhtml"/>');
      buf.writeln('    </navPoint>');
    }
    buf.writeln('  </navMap>');
    buf.writeln('</ncx>');
    return buf.toString();
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  String _extractText(List<md.Node> nodes) {
    final buf = StringBuffer();
    for (final node in nodes) {
      if (node is md.Text) {
        buf.write(node.text);
      } else if (node is md.Element) {
        buf.write(_extractText(node.n));
      }
    }
    return buf.toString();
  }

  String _escapeXml(String s) => s
      .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String _escapeAttr(String s) => s
      .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;');

  /// Generate a stable chapter ID from a title.
  String _toId(String title) {
    final result = StringBuffer();
    for (int i = 0; i < title.length; i++) {
      final c = title[i];
      if ((c.codeUnitAt(0) >= 0x4e00 && c.codeUnitAt(0) <= 0x9fff) ||
          (c.codeUnitAt(0) >= 0x3400 && c.codeUnitAt(0) <= 0x4dbf)) {
        // CJK character: hex encode for URL safety
        result.write('u${c.codeUnitAt(0).toRadixString(16)}');
      } else if (RegExp(r'[a-zA-Z0-9_-]').hasMatch(c)) {
        result.write(c);
      } else if (c == ' ' || c == '-') {
        result.write('_');
      }
      // Other chars: skip
    }
    final id = result.toString().replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'(^_|_$)'), '');
    return id.isNotEmpty ? id : 'chapter';
  }

  // NOTE: Random.secure() would be cryptographically stronger but is
  // significantly slower. For document UUIDs, regular Random is sufficient
  // since uniqueness — not unpredictability — is the requirement here.
  static final _rng = Random();

  /// UUID v4 for document identifiers.
  String _uuid() {
    final r = List<int>.generate(16, (_) => _rng.nextInt(256));
    r[6] = (r[6] & 0x0f) | 0x40; // version 4
    r[8] = (r[8] & 0x3f) | 0x80; // variant
    return '${_hex(r, 0, 4)}-${_hex(r, 4, 2)}-${_hex(r, 6, 2)}-${_hex(r, 8, 2)}-${_hex(r, 10, 6)}';
  }

  String _hex(List<int> bytes, int offset, int count) {
    return bytes.sublist(offset, offset + count).map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  // ─── Container XML ─────────────────────────────────────────────────────

  static String _containerXml({required String token}) =>
      '<?xml version="1.0"?>\n'
      '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
      '  <rootfiles>\n'
      '    <rootfile full-path="$token" media-type="application/oebps-package+xml"/>\n'
      '  </rootfiles>\n'
      '</container>\n';

  // ─── Minimal CSS ───────────────────────────────────────────────────────

  static String get _css => '''
body { margin: 0; padding: 0.5em; font-family: serif; line-height: 1.5; }
h1 { font-size: 1.8em; margin: 0.8em 0 0.4em; }
h2 { font-size: 1.5em; margin: 0.7em 0 0.3em; }
h3 { font-size: 1.3em; margin: 0.6em 0 0.2em; }
h4 { font-size: 1.1em; margin: 0.5em 0 0.15em; }
h5, h6 { font-size: 1em; margin: 0.4em 0 0.1em; }
p { margin: 0.3em 0; }
blockquote { margin: 0.5em 1em; padding-left: 0.5em; border-left: 3px solid #ccc; color: #555; }
pre { background: #f5f5f5; padding: 0.5em; overflow-x: auto; font-size: 0.9em; }
code { font-family: monospace; background: #f0f0f0; padding: 0.1em 0.2em; font-size: 0.9em; }
pre code { background: none; padding: 0; }
table { border-collapse: collapse; width: 100%; margin: 0.5em 0; }
td, th { border: 1px solid #ccc; padding: 0.3em 0.5em; text-align: left; }
th { background: #eee; font-weight: bold; }
ul, ol { margin: 0.3em 0; padding-left: 1.5em; }
li { margin: 0.1em 0; }
hr { border: none; border-top: 1px solid #ccc; margin: 1em 0; }
img { max-width: 100%; height: auto; }
a { color: #06c; }
section { }
''';

  ArchiveFile _textFile(String path, String content) {
    final bytes = utf8.encode(content);
    return ArchiveFile(path, bytes.length, bytes);
  }
}

class _Chapter {
  _Chapter(this.title, this.nodes);
  final String title;
  final List<md.Node> nodes;
}
