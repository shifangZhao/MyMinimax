"""Convert extracted JSON files to Dart source with embedded data."""
import json, os

DST = r"E:\CODEPROJECT\My minimax\lib\core\design\tokens"
JSON_DIR = DST  # JSON files are here too

def load_json(name):
    with open(os.path.join(JSON_DIR, name), encoding='utf-8') as f:
        return json.load(f)

def write_dart(filename, content):
    path = os.path.join(DST, filename)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"  Wrote {filename} ({len(content)} chars)")

# ═══════════════════════════════════════════════════════════════
# 1. Product Router
# ═══════════════════════════════════════════════════════════════
def gen_product_router():
    data = load_json('product_router.json')
    items = []
    for r in data:
        cat = r['category'].replace("'", "\\'")
        styles = r['styles'].replace("'", "\\'")
        color = r['color'].replace("'", "\\'")
        typo = r['typo'].replace("'", "\\'")
        effects = r['effects'].replace("'", "\\'")
        anti = r['anti'].replace("'", "\\'")
        pattern = r['pattern'].replace("'", "\\'")
        severity = r['severity'].replace("'", "\\'")
        items.append(f"  ProductDesign(category: '{cat}', pattern: '{pattern}', styles: '{styles}', color: '{color}', typo: '{typo}', effects: '{effects}', anti: '{anti}', severity: '{severity}')")

    code = f'''/// 161 product types → design routing.
/// Ported from ui-ux-pro-max/ui-reasoning.csv
class ProductRouter {{
  ProductRouter._();

  static const all = [
{",\n".join(items)}
  ];

  static ProductDesign? match(String query) {{
    final q = query.toLowerCase();
    ProductDesign? best;
    int bestScore = 0;
    for (final p in all) {{
      int score = 0;
      for (final w in p.category.toLowerCase().split(RegExp(r'[/,\\\\s]+'))) {{
        if (w.isNotEmpty && q.contains(w)) score += w.length * w.length;
      }}
      for (final w in p.styles.toLowerCase().split(RegExp(r'[\\s+]+'))) {{
        if (w.isNotEmpty && q.contains(w)) score += w.length;
      }}
      if (score > bestScore) {{ bestScore = score; best = p; }}
    }}
    return best;
  }}
}}

class ProductDesign {{
  final String category, pattern, styles, color, typo, effects, anti, severity;
  const ProductDesign({{required this.category, required this.pattern, required this.styles, required this.color, required this.typo, required this.effects, required this.anti, required this.severity}});

  String get promptHint => 'Product: $category\\nStyle: $styles\\nColor: $color\\nType: $typo\\nAvoid: $anti';
}}
'''
    write_dart('product_router.dart', code)

# ═══════════════════════════════════════════════════════════════
# 2. UX Rules
# ═══════════════════════════════════════════════════════════════
def gen_ux_rules():
    data = load_json('ux_rules.json')
    items = []
    for r in data:
        cat = r['cat'].replace("'", "\\'")
        issue = r['issue'].replace("'", "\\'")
        do_ = r['do'].replace("'", "\\'")
        dont = r['dont'].replace("'", "\\'")
        good = r['good'].replace("'", "\\'")
        bad = r['bad'].replace("'", "\\'")
        sev = r['severity'].replace("'", "\\'")
        items.append(f"  UxRule('{cat}', '{issue}', '{do_}', '{dont}', '{good}', '{bad}', '{sev}')")

    code = f'''/// 99 UX guidelines from ui-ux-pro-max/ux-guidelines.csv
class UxRules {{
  UxRules._();

  static const all = [
{",\n".join(items)}
  ];

  static String buildChecklist() {{
    final buf = StringBuffer();
    final cats = <String, List<UxRule>>{{}};
    for (final r in all) {{ cats.putIfAbsent(r.cat, () => []).add(r); }}
    buf.writeln('## Pre-Delivery UX Checklist');
    for (final e in cats.entries) {{
      buf.writeln('\\n### ' + e.key);
      for (final r in e.value) {{
        buf.writeln('- [${{r.sev == "High" ? "x" : " "}}] ${{r.issue}}: ${{r.do_}}');
      }}
    }}
    return buf.toString();
  }}

  static String get promptChecklist {{
    final buf = StringBuffer();
    buf.writeln('\\n## UX MUST-FOLLOW RULES');
    for (final r in all.where((r) => r.sev == 'High')) {{
      buf.writeln('${{r.sev}}: ${{r.issue}} — ${{r.do_}} (NOT: ${{r.dont}})');
    }}
    buf.writeln('\\n## UX SHOULD-FOLLOW RULES');
    for (final r in all.where((r) => r.sev == 'Medium')) {{
      buf.writeln('${{r.sev}}: ${{r.issue}} — ${{r.do_}}');
    }}
    return buf.toString();
  }}
}}

class UxRule {{
  final String cat, issue, do_, dont, good, bad, sev;
  const UxRule(this.cat, this.issue, this.do_, this.dont, this.good, this.bad, this.sev);
}}
'''
    write_dart('ux_rules.dart', code)

# ═══════════════════════════════════════════════════════════════
# 3. Font Pairings
# ═══════════════════════════════════════════════════════════════
def gen_font_pairings():
    data = load_json('font_pairings.json')
    items = []
    for r in data:
        name = r['name'].replace("'", "\\'")
        cat = r['category'].replace("'", "\\'")
        heading = r['heading'].replace("'", "\\'")
        body = r['body'].replace("'", "\\'")
        mood = r['mood'].replace("'", "\\'")
        best = r['bestFor'].replace("'", "\\'")
        imprt = r['import'].replace("'", "\\'")
        notes = r['notes'].replace("'", "\\'")
        items.append(f"  FontPairing('{name}', '{cat}', '{heading}', '{body}', '{mood}', '{best}', '{imprt}', '{notes}')")

    code = f'''/// 57+ font pairings from ui-ux-pro-max/typography.csv
class FontPairings {{
  FontPairings._();

  static const all = [
{",\n".join(items)}
  ];

  static FontPairing? find(String query) {{
    final q = query.toLowerCase();
    for (final p in all) {{
      if (p.name.toLowerCase().contains(q) || p.mood.contains(q) || p.bestFor.contains(q)) return p;
    }}
    return all.firstOrNull;
  }}

  static List<FontPairing> search(String query) {{
    final q = query.toLowerCase();
    return all.where((p) => p.name.toLowerCase().contains(q) || p.mood.contains(q) || p.bestFor.contains(q) || p.heading.toLowerCase().contains(q)).toList();
  }}
}}

class FontPairing {{
  final String name, cat, heading, body, mood, bestFor, cssImport, notes;
  const FontPairing(this.name, this.cat, this.heading, this.body, this.mood, this.bestFor, this.cssImport, this.notes);

  String get promptHint => 'Font pair: $name — $heading + $body\\n  Mood: $mood\\n  Import: $cssImport';
}}
'''
    write_dart('font_pairings.dart', code)

# ═══════════════════════════════════════════════════════════════
# 4. Landing Patterns
# ═══════════════════════════════════════════════════════════════
def gen_landing_patterns():
    data = load_json('landing_patterns.json')
    items = []
    for r in data:
        name = r['name'].replace("'", "\\'")
        kw = r['keywords'].replace("'", "\\'")
        sec = r['sections'].replace("'", "\\'")
        cta = r['cta'].replace("'", "\\'")
        color = r['color'].replace("'", "\\'")
        eff = r['effects'].replace("'", "\\'")
        conv = r['conversion'].replace("'", "\\'")
        items.append(f"  LandingPattern('{name}', '{kw}', '{sec}', '{cta}', '{color}', '{eff}', '{conv}')")

    code = f'''/// 34 landing page patterns from ui-ux-pro-max/landing.csv
class LandingPatterns {{
  LandingPatterns._();

  static const all = [
{",\n".join(items)}
  ];

  static LandingPattern? match(String query) {{
    final q = query.toLowerCase();
    for (final p in all) {{
      if (p.keywords.contains(q)) return p;
    }}
    return all.firstOrNull;
  }}
}}

class LandingPattern {{
  final String name, keywords, sections, cta, color, effects, conversion;
  const LandingPattern(this.name, this.keywords, this.sections, this.cta, this.color, this.effects, this.conversion);

  String get promptHint => 'Landing: $name\\nSections: $sections\\nCTA: $cta\\nColor: $color';
}}
'''
    write_dart('landing_patterns.dart', code)

# ═══════════════════════════════════════════════════════════════
# 5. Style Specs
# ═══════════════════════════════════════════════════════════════
def gen_style_specs():
    data = load_json('style_specs.json')
    items = []
    for r in data:
        name = r['name'].replace("'", "\\'").replace("$", "\\$")
        full_name = r['fullName'].replace("'", "\\'").replace("$", "\\$")
        desc = r['desc'].replace("'", "\\'").replace("$", "\\$")
        best = r['bestFor'].replace("'", "\\'").replace("$", "\\$")
        # For the full spec, we keep it but store compactly
        # Only store first 3000 chars of spec to keep file manageable
        spec = r['spec'][:3000].replace("'", "\\'").replace("$", "\\$").replace("\n", "\\n")
        items.append(f"StyleSpec('{name}', '{full_name}', '{desc}', '{best}', '{spec}')")

    code = f'''/// 151 complete design system specs from ui-ux-pro-max/design.csv
class StyleSpecs {{
  StyleSpecs._();

  static const all = <StyleSpec>[
{",\n".join(items)}
  ];

  static StyleSpec? find(String query) {{
    final q = query.toLowerCase();
    for (final s in all) {{
      if (s.name.toLowerCase().contains(q) || s.fullName.contains(q) || s.desc.contains(q)) return s;
    }}
    return null;
  }}

  static StyleSpec? get default_ => all.isNotEmpty ? all[0] : null;
}}

class StyleSpec {{
  final String name, fullName, desc, bestFor, spec;
  const StyleSpec(this.name, this.fullName, this.desc, this.bestFor, this.spec);

  /// Design philosophy section.
  String get philosophy {{
    final idx = spec.indexOf('Design Philosophy');
    if (idx < 0) return spec.split('\\\\n\\\\n')[0];
    return spec.substring(idx).split('\\\\n\\\\n')[0];
  }}

  /// Anti-patterns section.
  String get antiPatterns {{
    final idx = spec.indexOf('Anti-Pattern');
    if (idx < 0) return '';
    final end = spec.indexOf('\\\\n\\\\n', idx + 20);
    return end > 0 ? spec.substring(idx, end) : spec.substring(idx);
  }}

  /// Prompt brief for LLM context.
  String get promptBrief => 'Style: $fullName\\\\n$desc\\\\nBest for: $bestFor';
}}
'''
    write_dart('style_specs.dart', code)

if __name__ == '__main__':
    gen_product_router()
    gen_ux_rules()
    gen_font_pairings()
    gen_landing_patterns()
    gen_style_specs()
    print("All Dart files generated!")
