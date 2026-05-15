import 'dart:typed_data';
import 'document_converter_result.dart';

class ConverterPriority {
  static const int specific = 100;
  static const int extension = 50;
  static const int fallback = 10;
}

abstract class BaseDocumentConverter {
  int get priority;
  List<String> get supportedMimeTypes;
  List<String> get supportedExtensions;
  String get formatName;

  Future<DocumentConverterResult> convert({
    required Uint8List bytes,
    String? mimeType,
    String? fileName,
    Map<String, dynamic>? options,
  });

  bool supports({required String? mimeType, required String? fileName}) {
    if (mimeType != null) {
      for (final m in supportedMimeTypes) {
        if (m.endsWith('*')) {
          final prefix = m.substring(0, m.length - 1);
          if (mimeType.toLowerCase().startsWith(prefix)) return true;
        } else {
          if (mimeType.toLowerCase() == m.toLowerCase()) return true;
        }
      }
    }
    if (fileName != null) {
      final lower = fileName.toLowerCase();
      for (final ext in supportedExtensions) {
        if (lower.endsWith(ext.toLowerCase())) return true;
      }
    }
    return false;
  }
}
