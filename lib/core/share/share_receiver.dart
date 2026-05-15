import 'dart:convert';
import 'package:flutter/services.dart';

class ShareReceiver {
  static const _channel = MethodChannel('com.myminimax/share');

  /// 检查是否有待处理的分享内容（来自其他 App 的 SEND intent）
  /// 返回 null 表示没有，否则返回 SharedContent
  static Future<SharedContent?> getPendingShare() async {
    try {
      final result = await _channel.invokeMapMethod<String, String>('getPendingShare');
      if (result == null) return null;
      final imageBase64 = result['imageBase64'];
      final imageMimeType = result['imageMimeType'];
      final imageFileName = result['imageFileName'];
      final imageSizeStr = result['imageSize'];
      final imageSize = imageSizeStr != null ? int.tryParse(imageSizeStr) : null;

      Uint8List? imageBytes;
      if (imageBase64 != null && imageBase64.isNotEmpty) {
        imageBytes = base64Decode(imageBase64);
      }

      return SharedContent(
        text: result['text'],
        uri: result['uri'],
        imageBytes: imageBytes,
        imageMimeType: imageMimeType,
        imageFileName: imageFileName,
        imageSize: imageSize,
      );
    } catch (_) {
      return null;
    }
  }
}

class SharedContent {

  SharedContent({
    this.text,
    this.uri,
    this.imageBytes,
    this.imageMimeType,
    this.imageFileName,
    this.imageSize,
  });
  final String? text;
  final String? uri;
  final Uint8List? imageBytes;
  final String? imageMimeType;
  final String? imageFileName;
  final int? imageSize;

  bool get hasText => text != null && text!.isNotEmpty;
  bool get hasImage => imageBytes != null && imageBytes!.isNotEmpty;
  bool get hasUri => uri != null && uri!.isNotEmpty;

  /// 提取可用的输入文本（优先用分享的文字，其次是 URI）
  String? get effectiveText {
    if (hasText) return text;
    if (hasImage) return null; // Image will be handled as attachment
    if (hasUri) return '[图片] $uri';
    return null;
  }
}
