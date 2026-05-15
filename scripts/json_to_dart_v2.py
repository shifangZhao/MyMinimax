"""Convert merged style_library.json to a clean Dart file."""
import json, os

DST = r"E:\CODEPROJECT\My minimax\lib\core\design\tokens"

with open(os.path.join(DST, 'style_library.json'), encoding='utf-8') as f:
    data = json.load(f)

def esc(s):
    return s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$')

items = []
for r in data:
    name = esc(r['name'])
    stype = esc(r['type'])
    keywords = esc(r['keywords'])
    prim_colors = esc(r['primaryColors'])
    sec_colors = esc(r['secondaryColors'])
    effects = esc(r['effects'])
    best_for = esc(r['bestFor'])
    dont_use = esc(r['dontUseFor'])
    dark = esc(r['darkMode'])
    perf = esc(r['performance'])
    access = esc(r['accessibility'])
    complexity = esc(r['complexity'])
    ai_prompt = esc(r['aiPrompt'])
    css_tech = esc(r['cssTech'])
    checklist = esc(r['checklist'])
    design_vars = esc(r['designVars'])
    deep_spec = esc(r['deepSpec'][:5000])  # Cap at 5000 chars
    deep_full_name = esc(r['deepFullName'])
    deep_desc = esc(r['deepDesc'])
    deep_best = esc(r['deepBestFor'])

    items.append(
        f"StyleEntry(name: '{name}', type: '{stype}', keywords: '{keywords}', "
        f"primaryColors: '{prim_colors}', secondaryColors: '{sec_colors}', "
        f"effects: '{effects}', bestFor: '{best_for}', dontUseFor: '{dont_use}', "
        f"darkMode: '{dark}', performance: '{perf}', accessibility: '{access}', "
        f"complexity: '{complexity}', aiPrompt: '{ai_prompt}', cssTech: '{css_tech}', "
        f"checklist: '{checklist}', designVars: '{design_vars}', "
        f"deepSpec: '{deep_spec}', deepFullName: '{deep_full_name}', "
        f"deepDesc: '{deep_desc}', deepBestFor: '{deep_best}')"
    )

code = f'''/// 84 visual styles with metadata + 9 deep design system specs.
/// Merged from ui-ux-pro-max/styles.csv + design.csv
class StyleLibrary {{
  StyleLibrary._();

  static const all = <StyleEntry>[
{',\n'.join(items)}
  ];

  /// Find styles matching a query in name, keywords, or best-for fields.
  static List<StyleEntry> search(String query) {{
    final q = query.toLowerCase();
    return all.where((s) =>
      s.name.toLowerCase().contains(q) ||
      s.keywords.toLowerCase().contains(q) ||
      s.bestFor.toLowerCase().contains(q)
    ).toList();
  }}

  /// Get styles with deep design system specs.
  static List<StyleEntry> get withDeepSpecs =>
      all.where((s) => s.deepSpec.isNotEmpty).toList();

  /// Find a style by exact name match (case-insensitive).
  static StyleEntry? find(String name) {{
    final n = name.toLowerCase();
    return all.cast<StyleEntry?>().firstWhere(
      (s) => s!.name.toLowerCase() == n || s!.name.toLowerCase().contains(n),
      orElse: () => null,
    );
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

  /// Whether this style has a deep design system spec attached.
  bool get hasDeepSpec => deepSpec.isNotEmpty;

  /// Concise prompt snippet covering key design guidance.
  String get promptBrief => '''
Style: $name
Type: $type | Keywords: $keywords
Colors: $primaryColors
Effects: $effects
Best for: $bestFor
Don\'t use for: $dontUseFor
AI prompt: $aiPrompt
CSS: $cssTech
Checklist: $checklist
Design vars: $designVars''';

  /// Deep design system prompt (if available).
  String get deepPrompt => hasDeepSpec
      ? 'Design spec for $deepFullName:\\n$deepSpec'
      : promptBrief;
}}
'''
with open(os.path.join(DST, 'style_library.dart'), 'w', encoding='utf-8') as f:
    f.write(code)
print(f"Generated style_library.dart ({len(code)} chars)")
