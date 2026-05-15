import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/settings/data/settings_repository.dart';

class I18nService {

  I18nService._(this.locale, this._strings);
  static const supportedLocales = ['zh', 'en'];
  static const defaultLocale = 'zh';

  final String locale;
  final Map<String, String> _strings;

  bool get isZh => locale == 'zh';

  String t(String key) => _strings[key] ?? key;

  String tWith(String key, Map<String, String> params) {
    var text = _strings[key] ?? key;
    for (final entry in params.entries) {
      text = text.replaceAll('{${entry.key}}', entry.value);
    }
    return text;
  }

  static Future<I18nService> load() async {
    final repo = SettingsRepository();
    final locale = await repo.getLanguage();
    final strings = await _loadJson(locale);
    return I18nService._(locale, strings);
  }

  static Future<I18nService> forLocale(String locale) async {
    final strings = await _loadJson(locale);
    return I18nService._(locale, strings);
  }

  static Future<Map<String, String>> _loadJson(String locale) async {
    final jsonStr = await rootBundle.loadString('lib/core/i18n/$locale.json');
    final flat = <String, String>{};
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    _flatten(map, '', flat);
    return flat;
  }

  static void _flatten(Map<String, dynamic> map, String prefix, Map<String, String> out) {
    for (final entry in map.entries) {
      final key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      if (entry.value is String) {
        out[key] = entry.value as String;
      } else if (entry.value is Map<String, dynamic>) {
        _flatten(entry.value as Map<String, dynamic>, key, out);
      }
    }
  }
}

final i18nProvider = StateNotifierProvider<I18nNotifier, I18nService?>((ref) {
  return I18nNotifier();
});

class I18nNotifier extends StateNotifier<I18nService?> {
  I18nNotifier() : super(null);

  I18nNotifier.withService(I18nService super.service);

  Future<void> init() async {
    state = await I18nService.load();
  }

  Future<void> switchLanguage(String locale) async {
    if (locale == state?.locale) return;
    final repo = SettingsRepository();
    await repo.setLanguage(locale);
    state = await I18nService.forLocale(locale);
  }
}
