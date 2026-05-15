import 'dart:convert';

/// 安全 API 响应提取工具 — 防止 "type 'X' is not a subtype of type 'Y'" 崩溃
class SafeResponse {
  /// 安全提取顶层响应 Map（处理 String/Map 两种返回）
  static Map<String, dynamic> asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.cast<String, dynamic>();
    if (v is String) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  /// 安全提取嵌套 Map 字段
  static Map<String, dynamic> mapField(Map map, String key) {
    final v = map[key];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  /// 安全提取嵌套 List<Map> 字段
  static List<Map<String, dynamic>> listField(Map map, String key) {
    final v = map[key];
    if (v == null) return [];
    if (v is List) {
      return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return [];
  }

  /// 安全提取 List<dynamic>（简单值列表，如 guidance）
  static List listRaw(Map map, String key) {
    final v = map[key];
    if (v is List) return v;
    return [];
  }

  /// 安全提取字符串
  static String str(Map map, String key, [String fallback = '']) {
    final v = map[key];
    if (v == null) return fallback;
    return v.toString();
  }

  /// 安全提取 int（处理 String "123" 的情况）
  static int? intField(Map map, String key) {
    final v = map[key];
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString());
  }

  /// 从响应数据中安全提取 String 字段（处理 int 值等）
  static String? strOrNull(Map map, String key) {
    final v = map[key];
    if (v == null) return null;
    return v.toString();
  }
}
