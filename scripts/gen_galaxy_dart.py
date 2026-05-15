"""Generate galaxy_ui.dart from galaxy_components.json"""
import json, os

DST = r"E:\CODEPROJECT\My minimax\lib\core\design\tokens"

with open(os.path.join(DST, 'galaxy_components.json'), encoding='utf-8') as f:
    data = json.load(f)

components = data['components']
tag_counts = data['tag_counts']
technique_counts = data['technique_counts']
category_counts = data['category_counts']

# Select diverse components - one per (category, technique_set) combo
selected = []
seen = set()
for comp in components:
    key = (comp['cat'], tuple(sorted(comp['techniques'] or ['none'])))
    if key not in seen:
        seen.add(key)
        selected.append(comp)

# Cap at 500, prioritize technique-rich ones
if len(selected) > 500:
    selected.sort(key=lambda c: len(c['techniques']), reverse=True)
    selected = selected[:500]

print(f"Selected {len(selected)} from {len(components)} total")

def esc(s):
    """Escape for Dart single-quoted string. Handle all special chars."""
    # Order matters: backslash first, then quote, then dollar, then newlines
    result = s.replace('\\', '\\\\')
    result = result.replace("'", "\\'")
    result = result.replace('$', '\\$')
    result = result.replace('\n', '\\n')
    result = result.replace('\r', '')
    return result

# Build component items
items = []
for comp in selected:
    cid = esc(comp['id'])
    cat = esc(comp['cat'])
    author = esc(comp['author'])
    tags = esc(','.join(comp['tags']))
    html = esc(comp['html'][:1500])
    css = esc(comp['css'][:2000])
    colors = esc(','.join(comp['colors']))
    radii = esc(','.join(comp['radii']))
    shadows = esc(','.join(comp['shadows']))
    techs = esc(','.join(comp['techniques']))
    items.append(
        "GalaxyComp(id: '{cid}', cat: '{cat}', author: '{author}', "
        "tags: '{tags}', html: '{html}', css: '{css}', "
        "colors: '{colors}', radii: '{radii}', shadows: '{shadows}', "
        "techniques: '{techs}')".format(
            cid=cid, cat=cat, author=author, tags=tags,
            html=html, css=css, colors=colors, radii=radii,
            shadows=shadows, techs=techs
        )
    )

cat_stats = ', '.join("'{}':{}".format(k, v) for k, v in sorted(category_counts.items(), key=lambda x: -x[1]))
tag_stats = ', '.join("'{}':{}".format(k, v) for k, v in sorted(tag_counts.items(), key=lambda x: -x[1])[:80])
tech_stats = ', '.join("'{}':{}".format(k, v) for k, v in sorted(technique_counts.items(), key=lambda x: -x[1]))

# Template: use %% for Dart template strings to avoid confusion
template = """/// Galaxy UI component library — {total} handcrafted HTML+CSS elements.
/// {curated} curated components + statistical knowledge base.
/// Extracted from Uiverse.io galaxy-main (MIT licensed).
class GalaxyUI {{
  GalaxyUI._();

  static const totalComponents = {total};
  static const curatedCount = {curated};

  static const categoryCounts = <String, int>{{{cat_stats}}};
  static const topTags = <String, int>{{{tag_stats}}};
  static const techniqueCounts = <String, int>{{{tech_stats}}};

  static final curated = <GalaxyComp>[
{items}
  ];

  static List<GalaxyComp> byCategory(String cat) =>
      curated.where((c) => c.cat == cat).toList();

  static List<GalaxyComp> byTechnique(String tech) =>
      curated.where((c) => c.techniques.contains(tech)).toList();

  static List<GalaxyComp> byStyle(String style) =>
      curated.where((c) => c.tags.contains(style.toLowerCase())).toList();

  static List<GalaxyComp> bestOf({{required String category, String? technique}}) {{
    var results = byCategory(category);
    if (technique != null) {{
      results = results.where((c) => c.techniques.contains(technique)).toList();
    }}
    return results.take(20).toList();
  }}

  /// Build a CSS technique reference snippet for prompt injection.
  static String buildTechniqueRef(String technique) {{
    final examples = curated.where((c) => c.techniques.contains(technique)).take(3).toList();
    if (examples.isEmpty) return '';
    final buf = StringBuffer();
    buf.writeln('## CSS Technique: \$technique');
    for (final ex in examples) {{
      buf.writeln('### {{ex.cat}} example (tags: {{ex.tags}})');
      final css = ex.css.length > 600 ? '\${{ex.css.substring(0, 600)}}...' : ex.css;
      buf.writeln('```css');
      buf.writeln(css);
      buf.writeln('```');
      buf.writeln();
    }}
    return buf.toString();
  }}
}}

class GalaxyComp {{
  final String id, cat, author, tags, html, css;
  final String colors, radii, shadows, techniques;

  const GalaxyComp({{required this.id, required this.cat, required this.author,
    required this.tags, required this.html, required this.css,
    required this.colors, required this.radii, required this.shadows,
    required this.techniques}});

  List<String> get tagList => tags.split(',').where((t) => t.isNotEmpty).toList();
  List<String> get techniqueList => techniques.split(',').where((t) => t.isNotEmpty).toList();
  List<String> get colorList => colors.split(',').where((t) => t.isNotEmpty).toList();
}}
"""

code = template.format(
    total=len(components),
    curated=len(selected),
    cat_stats=cat_stats,
    tag_stats=tag_stats,
    tech_stats=tech_stats,
    items=',\n'.join(items),
)

path = os.path.join(DST, 'galaxy_ui.dart')
with open(path, 'w', encoding='utf-8') as f:
    f.write(code)
print(f"Generated galaxy_ui.dart ({len(code):,} chars, {len(selected)} components)")
