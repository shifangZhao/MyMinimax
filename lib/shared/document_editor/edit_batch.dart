import 'dart:typed_data';
import 'text_chunk.dart';

class EditOperation {
  EditOperation({
    required this.coordinate,
    required this.newText,
  });

  final DocxCoordinate coordinate;
  final String newText;

  int get newTextLength => newText.length;
}

class EditBatch {
  EditBatch({bool autoReorder = true}) : _autoReorder = autoReorder;
  final bool _autoReorder;
  final List<_TrackedOperation> _operations = [];

  void add(EditOperation op) {
    _operations.add(_TrackedOperation(op, op.newText.length));
  }

  void addAll(List<EditOperation> ops) {
    for (final op in ops) add(op);
  }

  List<EditOperation> get operations =>
      _operations.map((t) => t.operation).toList();

  bool get isEmpty => _operations.isEmpty;
  int get length => _operations.length;

  Future<void> commit(
    Uint8List Function(Uint8List, TextChunk, String) editFn,
    Uint8List bytes,
    List<TextChunk> chunkMap,
  ) async {
    if (_operations.isEmpty) return;

    final ops = _autoReorder
        ? (_operations.toList()
          ..sort((a, b) {
            final aC = a.operation.coordinate;
            final bC = b.operation.coordinate;
            final para = bC.paragraphIndex.compareTo(aC.paragraphIndex);
            if (para != 0) return para;
            final run = bC.runIndex.compareTo(aC.runIndex);
            if (run != 0) return run;
            return bC.textElementIndex.compareTo(aC.textElementIndex);
          }))
        : _operations;

    var currentBytes = bytes;
    var currentChunks = List<TextChunk>.from(chunkMap);

    for (int i = 0; i < ops.length; i++) {
      final tracked = ops[i];

      final chunk = _findChunkForCoordinate(
          currentChunks, tracked.operation.coordinate);
      if (chunk == null) {
        throw Exception('EditBatch: chunk not found at $tracked.operation.coordinate');
      }

      currentBytes = editFn(currentBytes, chunk, tracked.operation.newText);

      if (i < ops.length - 1) {
        currentChunks = _rebuildChunkMap(currentBytes);
      }
    }
  }

  TextChunk? _findChunkForCoordinate(
      List<TextChunk> chunks, DocxCoordinate coord) {
    for (final c in chunks) {
      if (c.paragraphIndex == coord.paragraphIndex &&
          c.runIndex == coord.runIndex &&
          c.textElementIndex == coord.textElementIndex) {
        return c;
      }
    }
    return null;
  }

  List<TextChunk> _rebuildChunkMap(Uint8List bytes) {
    return buildChunksFromBytes(bytes);
  }
}

class _TrackedOperation {
  _TrackedOperation(this.operation, int textLength) : delta = textLength - 1;
  final EditOperation operation;
  final int delta;
}

typedef EditFn = Uint8List Function(Uint8List, TextChunk, String);

List<TextChunk> buildChunksFromBytes(Uint8List bytes) {
  return [];
}