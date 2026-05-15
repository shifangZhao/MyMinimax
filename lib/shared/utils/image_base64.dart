import 'dart:convert';
import 'dart:typed_data';

/// 图片 base64 统一处理 —— 全项目唯一的编码/解码入口
///
/// 存储格式：纯 base64（无 data:...前缀），最紧凑
/// API 发送：根据需要加 data URI 前缀
/// 显示解码：自动处理两种格式（容错历史数据）
class ImageBase64 {
  ImageBase64._();

  /// Uint8List → 纯 base64（存储使用）
  static String encode(Uint8List bytes) => base64Encode(bytes);

  /// 纯 base64 → data URI（API 发送使用）
  static String toDataUri(String rawBase64, {String mime = 'image/jpeg'}) =>
      'data:$mime;base64,$rawBase64';

  /// 任意格式（data URI 或纯 base64）→ 纯 base64（容错归一化）
  static String normalize(String input) => input.split(',').last;

  /// 纯 base64 → Uint8List
  static Uint8List decode(String rawBase64) => base64Decode(rawBase64);

  /// 任意格式 → Uint8List（容错）
  static Uint8List decodeAny(String input) => base64Decode(normalize(input));
}
