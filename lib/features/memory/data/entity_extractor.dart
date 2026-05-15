/// Regex-based entity extraction for Chinese and English text.
///
/// Extracts proper nouns, place names, dates, and structured identifiers
/// from memory content. Pure Dart — no ML model, no spaCy.
library;

class EntityExtractor {
  EntityExtractor._();

  // ---- Chinese person names (common surname + 1-3 chars) ----

  static final _surnamePattern = RegExp(
    r'[王李张刘陈杨黄赵周吴徐孙马朱胡郭何高林罗郑梁谢宋唐许韩冯邓曹彭曾肖田董袁潘于蒋蔡余杜叶程苏魏吕丁任沈姚卢姜崔钟谭陆汪范金石廖贾夏韦付方白邹孟熊秦邱江尹薛闫段雷侯龙史陶黎贺顾毛郝龚邵万钱严覃武戴莫孔向汤]'
    r'[一-鿿]{1,3}',
  );

  // ---- Chinese place names ----

  static final _placePattern = RegExp(
    r'(?:[一-鿿]{2,6}(?:市|省|区|县|镇|路|街|大厦|广场|中心|公园|大学|中学|小学|医院|公司|集团|银行|酒店|餐厅|咖啡))'
    r'|(?:北京|上海|广州|深圳|杭州|南京|成都|武汉|重庆|天津|苏州|西安|长沙|青岛|大连|厦门|宁波|昆明|郑州|合肥|济南|福州|东莞|佛山|无锡|沈阳)',
  );

  // ---- English proper nouns ----

  static final _englishProperPattern = RegExp(
    r'\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b',
  );

  // ---- Dates ----

  static final _datePattern = RegExp(
    r'\d{4}[-/年]\d{1,2}[-/月]\d{1,2}[日号]?',
  );

  // ---- URLs ----

  static final _urlPattern = RegExp(r'https?://[^\s一-鿿]+');

  // ---- Email ----

  static final _emailPattern = RegExp(
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
  );

  /// Extract all entity strings from [text].
  static List<String> extract(String text) {
    final entities = <String>[];

    entities.addAll(
        _placePattern.allMatches(text).map((m) => m.group(0)!));
    entities.addAll(
        _surnamePattern.allMatches(text).map((m) => m.group(0)!));
    entities.addAll(
        _englishProperPattern.allMatches(text).map((m) => m.group(0)!));
    entities.addAll(
        _datePattern.allMatches(text).map((m) => m.group(0)!));
    entities.addAll(
        _urlPattern.allMatches(text).map((m) => m.group(0)!));
    entities.addAll(
        _emailPattern.allMatches(text).map((m) => m.group(0)!));

    // Deduplicate, filter noise
    final seen = <String>{};
    final result = <String>[];
    for (final e in entities) {
      final norm = e.toLowerCase().trim();
      if (seen.contains(norm) || norm.length < 2) continue;
      // Filter generic noise
      if (_isGeneric(norm)) continue;
      seen.add(norm);
      result.add(e.trim());
    }
    return result;
  }

  /// Extract from multiple texts and deduplicate globally.
  static List<String> extractBatch(List<String> texts) {
    final all = <String>{};
    for (final t in texts) {
      all.addAll(extract(t));
    }
    return all.toList();
  }

  static bool _isGeneric(String text) {
    const generics = {
      'this', 'that', 'there', 'here', 'then', 'now',
      'ok', 'yes', 'no', 'hi', 'hello', 'thanks',
      'the', 'and', 'for', 'from', 'with', 'about',
    };
    return generics.contains(text) || text.length < 2;
  }
}
