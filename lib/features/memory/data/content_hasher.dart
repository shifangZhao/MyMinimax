/// Content normalisation and SHA-256 hashing for memory deduplication.
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';

class ContentHasher {

  ContentHasher._();
  /// Normalize content for consistent hashing.
  ///
  /// - trim whitespace
  /// - collapse multiple spaces/newlines to single space
  /// - lowercase
  static String normalize(String content) {
    return content
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
  }

  /// SHA-256 hex digest of normalized content.
  static String hash(String content) {
    final normalized = normalize(content);
    final bytes = utf8.encode(normalized);
    return sha256.convert(bytes).toString();
  }
}
