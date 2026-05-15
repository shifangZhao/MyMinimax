import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';

/// Best-effort PDF in-place text editor.
///
/// Two strategies, tried in order:
/// 1. **Raw byte replace** — works for uncompressed text-based PDFs.
/// 2. **Stream decompress/recompress** — decompresses FlateDecode content
///    streams, replaces text only in streams confirmed to contain text
///    operators (BT/ET), then recompresses. Binary streams (images, fonts)
///    are never touched.
///
/// **Note about latin1**: ISO-8859-1 maps every byte 0x00-0xFF to a unique
/// character point. The decode → edit → encode round-trip IS lossless for
/// all byte values. The fragility in prior versions was about editing
/// mixed-content streams, not about latin1 itself. We now guard by only
/// editing streams that contain BT/ET text markers.
class PdfEditor {
  /// Replace [oldStr] with [newStr] in a PDF file.
  /// Returns modified bytes on success, or throws a descriptive error.
  static Uint8List edit(Uint8List bytes, String oldStr, String newStr) {
    // Strategy 1: Raw byte-level replacement
    final rawResult = _rawEdit(bytes, oldStr, newStr);
    if (rawResult != null) return rawResult;

    // Strategy 2: Decompress content streams, replace, recompress
    final streamResult = _streamEdit(bytes, oldStr, newStr);
    if (streamResult != null) return streamResult;

    throw Exception(
      'Failed to edit PDF text. Possible reasons:\n'
      '1. The text does not exist or spelling does not match (case-sensitive)\n'
      '2. PDF text is stored in encrypted streams\n'
      '3. The PDF is a scanned image (no extractable text layer)\n\n'
      'For scanned/image PDFs: readFile to OCR → edit Markdown → generatePdf.',
    );
  }

  // ─── Strategy 1: Raw byte replacement ────────────────────────────────

  static Uint8List? _rawEdit(Uint8List bytes, String oldStr, String newStr) {
    // Use latin1 for 1:1 byte↔char mapping (lossless for all 0x00-0xFF)
    final content = latin1.decode(bytes);
    if (!content.contains(oldStr)) return null;

    // Only replace if oldStr appears inside a text operator context:
    // BT...ET blocks or PDF string literals before Tj/TJ/' operators
    if (!_isSafeToEdit(content, oldStr)) return null;

    final replaced = content.replaceAll(oldStr, newStr);
    return Uint8List.fromList(latin1.encode(replaced));
  }

  /// Check that [target] appears inside a text-producing region of the PDF
  /// content stream — not in metadata, font definitions, or binary data.
  static bool _isSafeToEdit(String content, String target) {
    // Check BT..ET text blocks
    final btPattern = RegExp(r'BT(.*?)ET', dotAll: true);
    for (final m in btPattern.allMatches(content)) {
      if (m.group(1)!.contains(target)) return true;
    }

    // Check PDF string before text operators: (...) Tj / TJ / ' / " / hex
    final tjPattern = RegExp(r'\([^)]*\)\s*T[Jj]');
    for (final m in tjPattern.allMatches(content)) {
      if (m.group(0)!.contains(target)) return true;
    }

    final sqPattern = RegExp(r"\([^)]*\)\s*'");
    for (final m in sqPattern.allMatches(content)) {
      if (m.group(0)!.contains(target)) return true;
    }

    final dqPattern = RegExp(r'\([^)]*\)\s*"');
    for (final m in dqPattern.allMatches(content)) {
      if (m.group(0)!.contains(target)) return true;
    }

    final hexPattern = RegExp(r'<[0-9A-Fa-f]*>\s*T[Jj]');
    for (final m in hexPattern.allMatches(content)) {
      if (m.group(0)!.contains(target)) return true;
    }

    return false;
  }

  // ─── Strategy 2: Decompress FlateDecode streams ───────────────────────

  static Uint8List? _streamEdit(Uint8List bytes, String oldStr, String newStr) {
    final content = latin1.decode(bytes);
    if (!content.contains(oldStr)) return null;

    final output = BytesBuilder();
    int pos = 0;
    bool modified = false;

    // Match PDF indirect objects: "N N obj ... endobj"
    final objPattern = RegExp(r'(\d+ \d+ obj.*?endobj)', dotAll: true);

    for (final objMatch in objPattern.allMatches(content)) {
      // Copy bytes between objects verbatim
      output.add(latin1.encode(content.substring(pos, objMatch.start)));
      pos = objMatch.end;

      final objContent = objMatch.group(1)!;
      final hasFlate = objContent.contains('/Filter') && objContent.contains('FlateDecode');

      if (!hasFlate || !objContent.contains(oldStr)) {
        output.add(latin1.encode(objContent));
        continue;
      }

      // Find the stream data
      final streamMatch = RegExp(r'stream\r?\n(.*?)endstream', dotAll: true).firstMatch(objContent);
      if (streamMatch == null) {
        output.add(latin1.encode(objContent));
        continue;
      }

      // Extract raw stream bytes (before stream marker is ASCII, after is binary)
      final streamStart = streamMatch.start;
      final streamDataStart = streamMatch.group(0)!.indexOf('\n') + 1;
      final streamDataEnd = streamMatch.group(1)!.length - _trailingNewline(streamMatch.group(1)!);

      // Get the bytes before/after stream data for reconstruction
      final prefix = latin1.encode(objContent.substring(0, streamStart));
      final streamHeader = RegExp(r'stream\r?\n').firstMatch(objContent.substring(streamStart))!;
      final streamSuffix = latin1.encode('endstream${objContent.substring(streamMatch.end)}');
      final rawStreamData = latin1.encode(streamMatch.group(1)!);

      try {
        // Decompress — only process if stream is text content
        final decompressed = const ZLibDecoder().decodeBytes(rawStreamData);

        // Guard: only edit content streams (those containing PDF text operators)
        final decompStr = latin1.decode(Uint8List.fromList(decompressed));
        final hasTextOps = RegExp(r'\bBT\b').hasMatch(decompStr) ||
            RegExp(r'\bTj\b').hasMatch(decompStr) ||
            RegExp(r'\bTJ\b').hasMatch(decompStr) ||
            RegExp(r"\b'\b").hasMatch(decompStr) ||
            RegExp(r'\b"\b').hasMatch(decompStr);
        if (!hasTextOps) {
          output.add(latin1.encode(objContent));
          continue;
        }

        if (!decompStr.contains(oldStr)) {
          output.add(latin1.encode(objContent));
          continue;
        }

        // Replace text in decompressed content
        final replacedStr = decompStr.replaceAll(oldStr, newStr);
        final replacedBytes = latin1.encode(replacedStr);
        final recompressed = const ZLibEncoder().encode(replacedBytes);

        // Rebuild object with updated /Length
        final objPrefix = objContent.substring(0, streamMatch.start);
        final updatedPrefix = objPrefix.replaceAll(
          RegExp(r'/Length\s+\d+'),
          '/Length ${recompressed.length}',
        );

        output.add(latin1.encode(updatedPrefix));
        output.add(latin1.encode('stream\n'));
        output.add(recompressed);
        output.add(latin1.encode('\nendstream'));
        output.add(streamSuffix);
        modified = true;
      } catch (_) {
        // Decompression or recompression failed — keep original
        output.add(latin1.encode(objContent));
      }
    }

    // Copy remaining bytes
    output.add(latin1.encode(content.substring(pos)));

    if (!modified) return null;
    return output.toBytes();
  }

  static int _trailingNewline(String data) {
    if (data.endsWith('\r\n')) return 2;
    if (data.endsWith('\n')) return 1;
    return 0;
  }
}
