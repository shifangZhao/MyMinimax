/// Holds the result of a document-to-markdown conversion.
class DocumentConverterResult {

  const DocumentConverterResult({
    required this.markdownContent,
    this.title,
    this.mimeType,
    this.detectedFormat,
    this.metadata,
  });
  final String markdownContent;
  final String? title;
  final String? mimeType;
  final String? detectedFormat;
  final Map<String, dynamic>? metadata;
}
