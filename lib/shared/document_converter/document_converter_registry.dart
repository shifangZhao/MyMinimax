import 'domain/document_converter_interface.dart';

class DocumentConverterRegistry {
  factory DocumentConverterRegistry() => _instance;
  DocumentConverterRegistry._internal();
  static final DocumentConverterRegistry _instance =
      DocumentConverterRegistry._internal();

  final List<BaseDocumentConverter> _converters = [];

  void register(BaseDocumentConverter converter) {
    _converters.add(converter);
    _converters.sort((a, b) => b.priority.compareTo(a.priority));
  }

  void registerAll(List<BaseDocumentConverter> converters) {
    _converters.addAll(converters);
    _converters.sort((a, b) => b.priority.compareTo(a.priority));
  }

  BaseDocumentConverter? findConverter({
    required String? mimeType,
    required String? fileName,
  }) {
    for (final converter in _converters) {
      if (converter.supports(mimeType: mimeType, fileName: fileName)) {
        return converter;
      }
    }
    return null;
  }

  List<BaseDocumentConverter> get converters =>
      List.unmodifiable(_converters);
}
