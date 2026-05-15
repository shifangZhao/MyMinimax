"""Convert ui-ux-pro-max CSVs to Dart design data files."""
import csv, os, re, sys

SRC = r"E:\CODEPROJECT\开源项目\ui-ux-pro-max-skill-main\src\ui-ux-pro-max\data"
DST = r"E:\CODEPROJECT\My minimax\lib\core\design\tokens"

def safe(s):
    """Escape a string for Dart single-quoted string."""
    if s is None: return ''
    return s.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n').replace('\r', '')

def safe_multiline(s):
    """Escape for Dart triple-quoted string."""
    if s is None: return ''
    return s.replace('\\', '\\\\').replace('$', '\\$')

# ═══════════════════════════════════════════════════════════════════
# 1. ui-reasoning.csv → product_router.dart
# ═══════════════════════════════════════════════════════════════════
def gen_product_router():
    rows = []
    with open(os.path.join(SRC, 'ui-reasoning.csv'), encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)

    with open(os.path.join(DST, 'product_router.dart'), 'w', encoding='utf-8') as f:
        f.write('''/// Product type → design routing rules (161 industries).
/// Ported from ui-ux-pro-max/ui-reasoning.csv
class ProductRouter {
  ProductRouter._();

  static const productTypes = <String, ProductDesign>{''')

        for row in rows:
            cat = safe(row['UI_Category'])
            pattern = safe(row['Recommended_Pattern'])
            styles = safe(row['Style_Priority'])
            color_mood = safe(row['Color_Mood'])
            typo_mood = safe(row['Typography_Mood'])
            effects = safe(row['Key_Effects'])
            anti = safe(row['Anti_Patterns'])
            severity = safe(row['Severity'])

            f.write(f"""
    '{cat}': ProductDesign(
      category: '{cat}',
      recommendedPattern: '{pattern}',
      stylePriority: '{styles}',
      colorMood: '{color_mood}',
      typographyMood: '{typo_mood}',
      keyEffects: '{effects}',
      antiPatterns: '{anti}',
      severity: '{severity}',
    ),""")

        f.write('''
  };

  /// Find the best matching product type for a user query.
  /// Simple keyword-based matching — returns the closest match or null.
  static ProductDesign? match(String query) {
    final q = query.toLowerCase();
    ProductDesign? best;
    int bestScore = 0;
    for (final entry in productTypes.entries) {
      int score = 0;
      for (final word in entry.key.toLowerCase().split(RegExp(r'[/,\\s]+'))) {
        if (word.isNotEmpty && q.contains(word)) score += word.length;
      }
      if (score > bestScore) {
        bestScore = score;
        best = entry.value;
      }
    }
    return best;
  }
}

class ProductDesign {
  final String category;
  final String recommendedPattern;
  final String stylePriority;
  final String colorMood;
  final String typographyMood;
  final String keyEffects;
  final String antiPatterns;
  final String severity;

  const ProductDesign({
    required this.category,
    required this.recommendedPattern,
    required this.stylePriority,
    required this.colorMood,
    required this.typographyMood,
    required this.keyEffects,
    required this.antiPatterns,
    required this.severity,
  });

  /// Build a concise prompt snippet for LLM context.
  String get promptHint =>
      'Product type: $category\\n'
      '  Recommended style: $stylePriority\\n'
      '  Color mood: $colorMood\\n'
      '  Typography: $typographyMood\\n'
      '  Effects: $keyEffects\\n'
      '  Avoid: $antiPatterns';

  /// Match confidence is based on how well this matches a search query.
  String matchKey() => '$category $stylePriority $colorMood $typographyMood'.toLowerCase();
}
''')

# ═══════════════════════════════════════════════════════════════════
# 2. ux-guidelines.csv → ux_rules.dart
# ═══════════════════════════════════════════════════════════════════
def gen_ux_rules():
    rows = []
    with open(os.path.join(SRC, 'ux-guidelines.csv'), encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)

    with open(os.path.join(DST, 'ux_rules.dart'), 'w', encoding='utf-8') as f:
        f.write('''/// 99 UX guidelines ported from ui-ux-pro-max/ux-guidelines.csv
class UxRules {
  UxRules._();

  static const rules = <UxRule>[''')

        for row in rows:
            f.write(f"""
    UxRule(
      category: '{safe(row['Category'])}',
      issue: '{safe(row['Issue'])}',
      platform: '{safe(row['Platform'])}',
      description: '{safe(row['Description'])}',
      do_: '{safe(row['Do'])}',
      dont: '{safe(row["Don't"])}',
      codeGood: '{safe(row['Code Example Good'])}',
      codeBad: '{safe(row['Code Example Bad'])}',
      severity: '{safe(row['Severity'])}',
    ),""")

        f.write('''
  ];

  /// Build a pre-delivery checklist organized by category.
  static String buildChecklist() {
    final buf = StringBuffer();
    final byCategory = <String, List<UxRule>>{};
    for (final r in rules) {
      byCategory.putIfAbsent(r.category, () => []).add(r);
    }
    buf.writeln('## Pre-Delivery UX Checklist');
    for (final cat in byCategory.entries) {
      buf.writeln('\\n### ${cat.key}');
      for (final r in cat.value) {
        buf.writeln('- [ ] ${r.issue}: ${r.do_} (${r.severity})');
      }
    }
    return buf.toString();
  }

  /// Build a compact checklist string for injecting into LLM prompt.
  static String buildPromptChecklist() {
    final buf = StringBuffer();
    buf.writeln('## UX Quality Checklist (verify before output)');
    final highRules = rules.where((r) => r.severity == 'High' || r.severity == 'HIGH');
    for (final r in highRules) {
      buf.writeln('- ${r.issue}: ${r.do_} (NOT: ${r.dont})');
    }
    buf.writeln('\\n## Common UX Violations to Avoid');
    for (final r in rules.where((r) => r.severity == 'Medium' || r.severity == 'MEDIUM')) {
      buf.writeln('- ${r.issue}: ${r.do_}');
    }
    return buf.toString();
  }
}

class UxRule {
  final String category;
  final String issue;
  final String platform;
  final String description;
  final String do_;
  final String dont;
  final String codeGood;
  final String codeBad;
  final String severity;

  const UxRule({
    required this.category,
    required this.issue,
    required this.platform,
    required this.description,
    required this.do_,
    required this.dont,
    required this.codeGood,
    required this.codeBad,
    required this.severity,
  });
}
''')

# ═══════════════════════════════════════════════════════════════════
# 3. typography.csv → extend font_pairings.dart
# ═══════════════════════════════════════════════════════════════════
def gen_font_pairings():
    rows = []
    with open(os.path.join(SRC, 'typography.csv'), encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)

    with open(os.path.join(DST, 'font_pairings.dart'), 'w', encoding='utf-8') as f:
        f.write('''/// 57+ font pairings ported from ui-ux-pro-max/typography.csv
class FontPairings {
  FontPairings._();

  static const pairings = <FontPairing>[''')

        for row in rows:
            f.write(f"""
    FontPairing(
      name: '{safe(row['Font Pairing Name'])}',
      category: '{safe(row['Category'])}',
      headingFont: '{safe(row['Heading Font'])}',
      bodyFont: '{safe(row['Body Font'])}',
      mood: '{safe(row['Mood/Style Keywords'])}',
      bestFor: '{safe(row['Best For'])}',
      googleFontsUrl: '{safe(row['Google Fonts URL'])}',
      cssImport: '{safe(row['CSS Import'])}',
      tailwindConfig: '{safe(row['Tailwind Config'])}',
      notes: '{safe(row['Notes'])}',
    ),""")

        f.write('''
  ];

  /// Find pairings matching a mood/style query.
  static List<FontPairing> search(String query) {
    final q = query.toLowerCase();
    return pairings.where((p) =>
      p.name.toLowerCase().contains(q) ||
      p.mood.toLowerCase().contains(q) ||
      p.bestFor.toLowerCase().contains(q) ||
      p.headingFont.toLowerCase().contains(q)
    ).toList();
  }

  /// Get a random high-quality pairing.
  static FontPairing get default_ => pairings[0];
}

class FontPairing {
  final String name;
  final String category;
  final String headingFont;
  final String bodyFont;
  final String mood;
  final String bestFor;
  final String googleFontsUrl;
  final String cssImport;
  final String tailwindConfig;
  final String notes;

  const FontPairing({
    required this.name,
    required this.category,
    required this.headingFont,
    required this.bodyFont,
    required this.mood,
    required this.bestFor,
    required this.googleFontsUrl,
    required this.cssImport,
    required this.tailwindConfig,
    required this.notes,
  });

  String get promptHint =>
      'Font: $name — $headingFont (headings) + $bodyFont (body)\\n'
      '  Mood: $mood\\n'
      '  Import: $cssImport\\n'
      '  Notes: $notes';
}
''')

# ═══════════════════════════════════════════════════════════════════
# 4. landing.csv → landing_patterns.dart
# ═══════════════════════════════════════════════════════════════════
def gen_landing_patterns():
    rows = []
    with open(os.path.join(SRC, 'landing.csv'), encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)

    with open(os.path.join(DST, 'landing_patterns.dart'), 'w', encoding='utf-8') as f:
        f.write('''/// 34 landing page patterns ported from ui-ux-pro-max/landing.csv
class LandingPatterns {
  LandingPatterns._();

  static const patterns = <LandingPattern>[''')

        for row in rows:
            f.write(f"""
    LandingPattern(
      name: '{safe(row['Pattern Name'])}',
      keywords: '{safe(row['Keywords'])}',
      sectionOrder: '{safe(row['Section Order'])}',
      ctaPlacement: '{safe(row['Primary CTA Placement'])}',
      colorStrategy: '{safe(row['Color Strategy'])}',
      effects: '{safe(row['Recommended Effects'])}',
      conversionTips: '{safe(row['Conversion Optimization'])}',
    ),""")

        f.write('''
  ];

  static LandingPattern? match(String query) {
    final q = query.toLowerCase();
    for (final p in patterns) {
      if (p.keywords.toLowerCase().contains(q) || q.contains(p.name.toLowerCase().split('+')[0].trim())) {
        return p;
      }
    }
    return patterns[0]; // Default: Hero + Features + CTA
  }
}

class LandingPattern {
  final String name;
  final String keywords;
  final String sectionOrder;
  final String ctaPlacement;
  final String colorStrategy;
  final String effects;
  final String conversionTips;

  const LandingPattern({
    required this.name,
    required this.keywords,
    required this.sectionOrder,
    required this.ctaPlacement,
    required this.colorStrategy,
    required this.effects,
    required this.conversionTips,
  });

  String get promptHint =>
      'Landing pattern: $name\\n'
      '  Sections: $sectionOrder\\n'
      '  CTA: $ctaPlacement\\n'
      '  Color: $colorStrategy\\n'
      '  Effects: $effects\\n'
      '  Conversion: $conversionTips';
}
''')

# ═══════════════════════════════════════════════════════════════════
# 5. design.csv → style_specs.dart (67 full design system specs)
# ═══════════════════════════════════════════════════════════════════
def gen_style_specs():
    """Parse the design.csv into style blocks with full design system specs."""
    with open(os.path.join(SRC, 'design.csv'), encoding='utf-8') as f:
        content = f.read()

    # Split into blocks. Each block starts with a style name line
    # followed by description and best-for, then optionally <design-system> or Design Style: blocks
    blocks = re.split(r'\n(?=[A-Z][a-z].*(?:（|\())', content)

    styles = {}
    for block in blocks:
        if not block.strip():
            continue
        lines = block.strip().split('\n')
        if not lines:
            continue

        name = lines[0].strip()
        # Normalize name: remove Chinese parenthetical, trim
        name_en = re.sub(r'（.*?）|\(.*?\)', '', name).strip()

        # Extract description (first non-empty line after name that's not a list item)
        desc = ''
        best_for = []
        spec_start = 0
        for i, line in enumerate(lines[1:], 1):
            stripped = line.strip()
            if not stripped:
                continue
            if re.match(r'^\d+\.', stripped):
                best_for.append(stripped)
            elif not desc:
                desc = stripped
            if stripped.startswith('<design-system>') or stripped.startswith('Design Style:'):
                spec_start = i
                break
            if i > 5:
                break

        # Get the full spec
        spec = '\n'.join(lines[spec_start:]) if spec_start > 0 else '\n'.join(lines[1:])

        styles[name_en.lower()] = {
            'name': name_en,
            'full_name': name,
            'description': desc,
            'best_for': best_for,
            'spec': spec,
        }

    with open(os.path.join(DST, 'style_specs.dart'), 'w', encoding='utf-8') as f:
        f.write('''/// 67 complete design system specifications.
/// Each entry contains the full design philosophy, token system,
/// component styles, layout rules, and anti-patterns for one visual style.
/// Ported from ui-ux-pro-max/design.csv
class StyleSpecs {
  StyleSpecs._();

  /// All style specs indexed by normalized style name (lowercase english).
  static const specs = <String, StyleSpec>{
''')

        for key, style in sorted(styles.items()):
            name = safe(style['name'])
            full_name = safe(style['full_name'])
            desc = safe_multiline(style['description'])
            best = safe_multiline('|'.join(style['best_for']))
            spec = safe_multiline(style['spec'])

            f.write(f"""    '{safe(key)}': StyleSpec(
      name: r'{name}',
      fullName: r'{full_name}',
      description: r'{desc}',
      bestFor: r'{best}',
      spec: r'{spec}',
    ),
""")

        f.write('''  };

  /// Search for a style by name or keyword.
  static StyleSpec? find(String query) {
    final q = query.toLowerCase();
    for (final entry in specs.entries) {
      if (entry.key.contains(q) || entry.value.name.toLowerCase().contains(q) ||
          entry.value.description.toLowerCase().contains(q)) {
        return entry.value;
      }
    }
    return null;
  }

  /// List all available style names.
  static List<String> get allNames => specs.keys.toList();
}

class StyleSpec {
  final String name;
  final String fullName;
  final String description;
  final String bestFor;
  final String spec;

  const StyleSpec({
    required this.name,
    required this.fullName,
    required this.description,
    required this.bestFor,
    required this.spec,
  });

  /// Extract the design philosophy section for prompt injection.
  String get philosophy {
    final match = RegExp(r"(?:Design Philosophy|Core Principle|1\. Design Philosophy)(.*?)(?=\\n\\n\\d+\\.|\\n\\nDesign Token|\\n\\nThe DNA|\\n\\nColors \\()", dotAll: true).firstMatch(spec);
    return match?.group(1)?.trim() ?? spec.split('\\n\\n')[0];
  }

  /// Extract the anti-patterns section.
  String get antiPatterns {
    final match = RegExp(r"Anti-Patterns.*?(?=\\n\\n[A-Z]|\\Z)", dotAll: true).firstMatch(spec);
    return match?.group(0)?.trim() ?? '';
  }

  /// Extract bold/signature design choices.
  String get boldChoices {
    final match = RegExp(r"(?:Bold|Signature).*?(?=\\n\\n[A-Z]|\\Z)", dotAll: true).firstMatch(spec);
    return match?.group(0)?.trim() ?? '';
  }

  /// Build a concise prompt snippet covering the key design decisions.
  String get promptBrief => "'"'"'Style: $name\\n$description\\nBest for: \\${bestFor.split('"'"'"|"'"'"').take(3).join('"'"'", "'"'"')}'"'"'";
}
''')

if __name__ == '__main__':
    print('Generating product_router.dart...')
    gen_product_router()
    print('Generating ux_rules.dart...')
    gen_ux_rules()
    print('Generating font_pairings.dart...')
    gen_font_pairings()
    print('Generating landing_patterns.dart...')
    gen_landing_patterns()
    print('Generating style_specs.dart...')
    gen_style_specs()
    print('Done! All files generated.')
