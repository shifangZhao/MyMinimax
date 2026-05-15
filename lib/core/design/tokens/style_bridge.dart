/// Bridge between ui-ux-pro-max visual style recommendations
/// and shadcn/ui geometric style presets.
///
/// When ProductRouter says "Neumorphism", this maps to "Maia" (rounded, soft).
/// When it says "Brutalist", this maps to "Lyra" (sharp, boxy).
class StyleBridge {
  StyleBridge._();

  /// Map a ui-ux-pro-max style name to the closest shadcn StylePreset.
  /// Returns (styleName, baseColor, accentTheme, font).
  static BridgeResult bridge(String uxStyleRecommendation) {
    final q = uxStyleRecommendation.toLowerCase();

    // Round, soft, pill-shaped → Maia
    if (_matches(q, ['soft', 'rounded', 'pill', 'neumorphism', 'claymorphism',
        'neumorphic', 'claymorphic', 'soft ui', 'gentle', 'friendly'])) {
      return const BridgeResult(
        style: 'maia', baseColor: 'neutral',
        accentHint: 'pink or rose (soft warmth)',
        fontHint: 'figtree (friendly geometric)',
      );
    }

    // Sharp, boxy, brutalist, editorial → Lyra or Sera
    if (_matches(q, ['sharp', 'boxy', 'brutalist', 'brutalism', 'mono',
        'editorial', 'typographic', 'architectural', 'raw'])) {
      if (q.contains('editorial') || q.contains('typographic') ||
          q.contains('serif') || q.contains('fashion')) {
        return const BridgeResult(
          style: 'sera', baseColor: 'stone',
          accentHint: 'none (editorial monochrome)',
          fontHint: 'playfair-display (editorial serif)',
        );
      }
      return const BridgeResult(
        style: 'lyra', baseColor: 'zinc',
        accentHint: 'amber or red (bold accent)',
        fontHint: 'jetbrains-mono or space-grotesk (mono/tech)',
      );
    }

    // Compact, dense, data-heavy → Mira or Nova
    if (_matches(q, ['compact', 'dense', 'data', 'dashboard', 'terminal',
        'code', 'developer', 'minimal', 'efficient'])) {
      return const BridgeResult(
        style: 'nova', baseColor: 'zinc',
        accentHint: 'blue or cyan (professional)',
        fontHint: 'inter (clean, readable)',
      );
    }

    // Glossy, premium, luxury, glass → Luma
    if (_matches(q, ['glass', 'gloss', 'luxury', 'premium', 'glossy',
        'glassmorphism', 'luminous', 'vibrant', 'rich shadow', 'brand'])) {
      return const BridgeResult(
        style: 'luma', baseColor: 'neutral',
        accentHint: 'violet or fuchsia (premium pop)',
        fontHint: 'manrope (modern luxury)',
      );
    }

    // Minimal, clean, swiss, neutral → Vega
    if (_matches(q, ['minimal', 'clean', 'swiss', 'neutral', 'simple',
        'professional', 'corporate', 'enterprise', 'saas', 'flat'])) {
      return const BridgeResult(
        style: 'vega', baseColor: 'neutral',
        accentHint: 'blue or indigo (trust, professional)',
        fontHint: 'inter (universal clean)',
      );
    }

    // Dark mode focused → Vega with darker base
    if (_matches(q, ['dark', 'oled', 'night', 'cyberpunk', 'synthwave'])) {
      return const BridgeResult(
        style: 'vega', baseColor: 'zinc',
        accentHint: 'cyan or emerald (neon on dark)',
        fontHint: 'geist or jetbrains-mono',
      );
    }

    // 3D, realistic, hyperreal → Vega with stronger shadows
    if (_matches(q, ['3d', 'realistic', 'hyperreal', 'skeuomorphic',
        'depth', 'layered', 'material'])) {
      return const BridgeResult(
        style: 'luma', baseColor: 'neutral',
        accentHint: 'blue (material trustworthy)',
        fontHint: 'roboto (material native)',
      );
    }

    // Default fallback
    return const BridgeResult(
      style: 'vega', baseColor: 'neutral',
      accentHint: 'blue (safe default)',
      fontHint: 'inter (safe default)',
    );
  }

  static bool _matches(String query, List<String> keywords) {
    return keywords.any((k) => query.contains(k));
  }
}

class BridgeResult {   // recommended font direction

  const BridgeResult({
    required this.style,
    required this.baseColor,
    required this.accentHint,
    required this.fontHint,
  });
  final String style;      // shadcn style name
  final String baseColor;  // shadcn base color
  final String accentHint; // recommended accent direction
  final String fontHint;
}
