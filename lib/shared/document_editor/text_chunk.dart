import 'package:xml/xml.dart';

/// Represents a text fragment with its position in the document.
/// Used for precise text editing in Office documents.
class TextChunk {
  const TextChunk({
    required this.text,
    required this.startOffset,
    required this.endOffset,
    required this.paragraphIndex,
    required this.runIndex,
    required this.textElementIndex,
    this.elementPath = '',
  });

  final String text;
  final int startOffset;
  final int endOffset;
  final int paragraphIndex;
  final int runIndex;
  final int textElementIndex;
  final String elementPath;

  int get length => endOffset - startOffset;

  @override
  String toString() =>
      'TextChunk("$text", para=$paragraphIndex, run=$runIndex, t=$textElementIndex, offs=$startOffset-$endOffset)';
}

/// Coordinate for precise DOCX text location.
/// Points to exact XmlElement in the document XML tree.
class DocxCoordinate {
  const DocxCoordinate({
    required this.paragraphIndex,
    required this.runIndex,
    required this.textElementIndex,
  });

  final int paragraphIndex;
  final int runIndex;
  final int textElementIndex;

  @override
  String toString() =>
      'DocxCoordinate(p=$paragraphIndex, r=$runIndex, t=$textElementIndex)';
}

/// Chunk list with helper methods for text lookup.
class TextChunkMap {
  TextChunkMap(this.chunks) {
    _buildIndex();
  }
  final List<TextChunk> chunks;

  final Map<int, List<TextChunk>> _byParagraph = {};
  final Map<String, TextChunk> _byPath = {};

  void _buildIndex() {
    for (final chunk in chunks) {
      _byParagraph.putIfAbsent(chunk.paragraphIndex, () => []).add(chunk);
      if (chunk.elementPath.isNotEmpty) {
        _byPath[chunk.elementPath] = chunk;
      }
    }
  }

  List<TextChunk> byParagraph(int paraIdx) => _byParagraph[paraIdx] ?? [];

  TextChunk? byPath(String path) => _byPath[path];

  TextChunk? findChunkContaining(int globalOffset) {
    for (final chunk in chunks) {
      if (globalOffset >= chunk.startOffset && globalOffset < chunk.endOffset) {
        return chunk;
      }
    }
    return null;
  }

  TextChunk? findChunkAt(int paragraphIndex, int runIndex, int textElementIndex) {
    for (final chunk in chunks) {
      if (chunk.paragraphIndex == paragraphIndex &&
          chunk.runIndex == runIndex &&
          chunk.textElementIndex == textElementIndex) {
        return chunk;
      }
    }
    return null;
  }

  DocxCoordinate? findCoordinate(int globalOffset) {
    final chunk = findChunkContaining(globalOffset);
    if (chunk == null) return null;
    return DocxCoordinate(
      paragraphIndex: chunk.paragraphIndex,
      runIndex: chunk.runIndex,
      textElementIndex: chunk.textElementIndex,
    );
  }

  /// Find all chunks whose text contains [query].
  List<TextChunk> findAll(String query) {
    final result = <TextChunk>[];
    for (final chunk in chunks) {
      if (chunk.text.contains(query)) {
        result.add(chunk);
      }
    }
    return result;
  }
}

/// Build element path for XmlElement (e.g. "w:body/w:p[2]/w:r[0]/w:t[1]")
String buildElementPath(XmlElement element) {
  final parts = <String>[];
  var current = element;
  while (current.parent is XmlElement) {
    final parent = current.parent as XmlElement;
    final siblings = parent.childElements.where((e) => e.localName == current.localName).toList();
    final idx = siblings.indexOf(current);
    parts.insert(0, '${current.localName}[$idx]');
    current = parent;
  }
  parts.insert(0, current.localName ?? 'root');
  return parts.join('/');
}