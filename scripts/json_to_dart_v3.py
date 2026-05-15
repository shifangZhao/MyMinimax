"""Generate Dart file with embedded JSON string that gets parsed at runtime."""
import json, os

DST = r"E:\CODEPROJECT\My minimax\lib\core\design\tokens"

with open(os.path.join(DST, 'style_library.json'), encoding='utf-8') as f:
    data = json.load(f)

# Compact JSON
compact = json.dumps(data, ensure_ascii=False, separators=(',', ':'))

# Escape for Dart string: backslash, dollar, single quote, newlines
escaped = compact.replace('\\', '\\\\').replace('$', '\\$').replace("'", "\\'")

dart_code = f'''/// 84 visual styles with metadata + 9 deep design system specs.
/// Data embedded as JSON, parsed at first access.
/// Merged from ui-ux-pro-max/styles.csv + design.csv
import 'dart:convert';

class StyleLibrary {{
  StyleLibrary._();

  static List<StyleEntry>? _cache;

  static const _json = '{escaped}';

  static List<StyleEntry> get all {{
    if (_cache != null) return _cache!;
    final List<dynamic> raw = jsonDecode(_json) as List<dynamic>;
    _cache = raw.map((e) => StyleEntry.fromJson(e as Map<String, dynamic>)).toList();
    return _cache!;
  }}

  static List<StyleEntry> search(String query) {{
    final q = query.toLowerCase();
    return all.where((s) =>
      s.name.toLowerCase().contains(q) ||
      s.keywords.toLowerCase().contains(q) ||
      s.bestFor.toLowerCase().contains(q)
    ).toList();
  }}

  static List<StyleEntry> get withDeepSpecs =>
      all.where((s) => s.deepSpec.isNotEmpty).toList();

  static StyleEntry? find(String name) {{
    final n = name.toLowerCase();
    for (final s in all) {{
      if (s.name.toLowerCase().contains(n)) return s;
    }}
    return null;
  }}
}}

class StyleEntry {{
  final String name, type, keywords, primaryColors, secondaryColors;
  final String effects, bestFor, dontUseFor, darkMode, performance;
  final String accessibility, complexity, aiPrompt, cssTech, checklist, designVars;
  final String deepSpec, deepFullName, deepDesc, deepBestFor;

  const StyleEntry({{
    required this.name, required this.type, required this.keywords,
    required this.primaryColors, required this.secondaryColors,
    required this.effects, required this.bestFor, required this.dontUseFor,
    required this.darkMode, required this.performance, required this.accessibility,
    required this.complexity, required this.aiPrompt, required this.cssTech,
    required this.checklist, required this.designVars,
    required this.deepSpec, required this.deepFullName,
    required this.deepDesc, required this.deepBestFor,
  }});

  factory StyleEntry.fromJson(Map<String, dynamic> j) => StyleEntry(
    name: j['name'] as String? ?? '',
    type: j['type'] as String? ?? '',
    keywords: j['keywords'] as String? ?? '',
    primaryColors: j['primaryColors'] as String? ?? '',
    secondaryColors: j['secondaryColors'] as String? ?? '',
    effects: j['effects'] as String? ?? '',
    bestFor: j['bestFor'] as String? ?? '',
    dontUseFor: j['dontUseFor'] as String? ?? '',
    darkMode: j['darkMode'] as String? ?? '',
    performance: j['performance'] as String? ?? '',
    accessibility: j['accessibility'] as String? ?? '',
    complexity: j['complexity'] as String? ?? '',
    aiPrompt: j['aiPrompt'] as String? ?? '',
    cssTech: j['cssTech'] as String? ?? '',
    checklist: j['checklist'] as String? ?? '',
    designVars: j['designVars'] as String? ?? '',
    deepSpec: j['deepSpec'] as String? ?? '',
    deepFullName: j['deepFullName'] as String? ?? '',
    deepDesc: j['deepDesc'] as String? ?? '',
    deepBestFor: j['deepBestFor'] as String? ?? '',
  );

  bool get hasDeepSpec => deepSpec.isNotEmpty;

  String get promptBrief => 'Style: $name\\n'
      'Type: $type | Keywords: $keywords\\n'
      'Colors: $primaryColors\\n'
      'Effects: $effects\\n'
      'Best for: $bestFor\\n'
      'AI prompt: $aiPrompt\\n'
      'CSS: $cssTech\\n'
      'Checklist: $checklist\\n'
      'Design vars: $designVars';

  String get deepPrompt => hasDeepSpec
      ? 'Design spec for $deepFullName:\\n$deepSpec'
      : promptBrief;
}}
'''

path = os.path.join(DST, 'style_library.dart')
with open(path, 'w', encoding='utf-8') as f:
    f.write(dart_code)

print(f'Generated style_library.dart ({len(dart_code)} chars, {len(escaped)} bytes JSON)')
