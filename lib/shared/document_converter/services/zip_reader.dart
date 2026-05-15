/// Lightweight selective ZIP reader for mobile memory efficiency.
///
/// Avoids the all-or-nothing [package:archive] ZipDecoder().decodeBytes()
/// which decompresses every entry into memory. Instead:
/// 1. Parses only the central directory (tiny, at end of file)
/// 2. Decompresses individual files on demand via [readFile]
///
/// For DOCX/XLSX/PPTX, the media files (images/audio) account for >95% of
/// the archive size. This reader skips them entirely unless explicitly
/// requested, keeping memory usage at ~2-5 MB instead of 200+ MB.
library;

import 'dart:typed_data';
import 'package:archive/archive_io.dart' show ZLibDecoder;

class ZipEntry {

  const ZipEntry._({
    required this.name,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.compressionMethod,
    required int localHeaderOffset,
  }) : _localHeaderOffset = localHeaderOffset;
  final String name;
  final int compressedSize;
  final int uncompressedSize;
  final int compressionMethod; // 0=store, 8=deflate
  final int _localHeaderOffset;
}

class ZipReader {

  ZipReader._(this._bytes, this._entries);
  final Uint8List _bytes;
  final Map<String, ZipEntry> _entries;

  /// Parse ZIP central directory from [bytes] and build file index.
  /// This is O(central-directory-size), not O(archive-size).
  /// Returns null if the data is not a valid ZIP.
  static ZipReader? tryParse(Uint8List bytes) {
    try {
      final entries = <String, ZipEntry>{};

      // 1. Find End of Central Directory Record (signature: PK\x05\x06)
      int eocdOffset = _findEocd(bytes);
      if (eocdOffset < 0) return null;

      // 2. Read central directory offset and entry count from EOCD
      final eocd = ByteData.sublistView(bytes, eocdOffset);
      final cdOffset = eocd.getUint32(16, Endian.little);
      final cdSize = eocd.getUint32(12, Endian.little);
      final totalEntries = eocd.getUint16(10, Endian.little);

      if (cdOffset + cdSize > bytes.length) return null;
      if (totalEntries == 0 || totalEntries > 50000) return null;

      // 3. Parse central directory entries
      int pos = cdOffset;
      final cdEnd = cdOffset + cdSize;

      for (int i = 0; i < totalEntries && pos + 46 <= cdEnd; i++) {
        final cd = ByteData.sublistView(bytes, pos);
        final sig = cd.getUint32(0, Endian.little);
        if (sig != 0x02014b50) break; // not a central directory header

        final compressionMethod = cd.getUint16(10, Endian.little);
        final compressedSize = cd.getUint32(20, Endian.little);
        final uncompressedSize = cd.getUint32(24, Endian.little);
        final fileNameLen = cd.getUint16(28, Endian.little);
        final extraFieldLen = cd.getUint16(30, Endian.little);
        final commentLen = cd.getUint16(32, Endian.little);
        final localHeaderOffset = cd.getUint32(42, Endian.little);

        pos += 46;
        if (pos + fileNameLen > bytes.length) break;

        final nameBytes = bytes.sublist(pos, pos + fileNameLen);
        final name = String.fromCharCodes(nameBytes);

        // Normalize path separator (some ZIPs use backslash)
        final normalizedName = name.replaceAll('\\', '/');

        entries[normalizedName] = ZipEntry._(
          name: normalizedName,
          compressedSize: compressedSize,
          uncompressedSize: uncompressedSize,
          compressionMethod: compressionMethod,
          localHeaderOffset: localHeaderOffset,
        );

        pos += fileNameLen + extraFieldLen + commentLen;
      }

      return ZipReader._(bytes, entries);
    } catch (_) {
      return null;
    }
  }

  /// List all entry names in this archive.
  Iterable<String> get fileNames => _entries.keys;

  /// Check if an entry exists.
  bool containsFile(String name) => _entries.containsKey(name);

  /// Read and decompress a single file from the archive.
  /// Returns null if the file is not found or decompression fails.
  Uint8List? readFile(String name) {
    final entry = _entries[name];
    if (entry == null) return null;

    final offset = entry._localHeaderOffset;
    if (offset + 30 > _bytes.length) return null;

    // Parse local file header to find data start
    final lh = ByteData.sublistView(_bytes, offset);
    if (lh.getUint32(0, Endian.little) != 0x04034b50) return null;

    final fileNameLen = lh.getUint16(26, Endian.little);
    final extraFieldLen = lh.getUint16(28, Endian.little);

    // Data starts after: local header (30) + filename + extra field
    final dataStart = offset + 30 + fileNameLen + extraFieldLen;
    final dataEnd = dataStart + entry.compressedSize;

    if (dataEnd > _bytes.length) return null;

    final compressedData = _bytes.sublist(dataStart, dataEnd);

    switch (entry.compressionMethod) {
      case 0: // Store (no compression)
        return compressedData;

      case 8: // Deflate
        try {
          final decompressed = const ZLibDecoder().decodeBytes(compressedData);
          return Uint8List.fromList(decompressed);
        } catch (_) {
          return null;
        }

      default:
        return null; // Unsupported compression method
    }
  }

  /// Read a file as UTF-8 text. Returns null if not found or not valid UTF-8.
  String? readFileAsString(String name) {
    final bytes = readFile(name);
    if (bytes == null) return null;
    try {
      return String.fromCharCodes(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Find all entry names matching [pattern] (glob-style with ** and *).
  /// e.g., "xl/worksheets/sheet*.xml", "ppt/slides/slide*.xml"
  List<String> findMatching(String pattern) {
    // Convert glob to regex
    var regexStr = pattern
        .replaceAll('.', r'\.')
        .replaceAll('**', '__DOUBLESTAR__')
        .replaceAll('*', r'[^/]*')
        .replaceAll('__DOUBLESTAR__', '.*');
    final regex = RegExp('^$regexStr\$');
    return _entries.keys.where((name) => regex.hasMatch(name)).toList()
      ..sort((a, b) => a.compareTo(b));
  }

  /// Find the End of Central Directory Record by scanning backwards from
  /// the end of the file for the signature 0x06054b50.
  /// The EOCD may have a variable-length comment (max 65535 bytes).
  static int _findEocd(Uint8List bytes) {
    final searchStart = bytes.length - 65557; // 65535 + 22 (EOCD size)
    final start = searchStart < 0 ? 0 : searchStart;

    for (int i = bytes.length - 22; i >= start; i--) {
      if (bytes[i] == 0x50 &&
          bytes[i + 1] == 0x4B &&
          bytes[i + 2] == 0x05 &&
          bytes[i + 3] == 0x06) {
        // Verify: comment length must fit
        final eocd = ByteData.sublistView(bytes, i);
        final commentLen = eocd.getUint16(20, Endian.little);
        if (i + 22 + commentLen <= bytes.length) {
          return i;
        }
      }
    }
    return -1;
  }
}
