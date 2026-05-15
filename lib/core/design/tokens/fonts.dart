/// Font catalog ported from shadcn/ui v4 font-definitions.ts.
/// Google Fonts CDN URLs for all 27 fonts.
class FontTokens {
  FontTokens._();

  static const sansFontNames = [
    'geist', 'inter', 'noto-sans', 'nunito-sans', 'figtree', 'roboto',
    'raleway', 'dm-sans', 'public-sans', 'outfit', 'oxanium', 'manrope',
    'space-grotesk', 'montserrat', 'ibm-plex-sans', 'source-sans-3',
    'instrument-sans',
  ];

  static const monoFontNames = ['jetbrains-mono', 'geist-mono'];

  static const serifFontNames = [
    'noto-serif', 'roboto-slab', 'merriweather', 'lora',
    'playfair-display', 'eb-garamond', 'instrument-serif',
  ];

  /// All font names (for LLM enum).
  static const allFontNames = [
    ...sansFontNames,
    ...monoFontNames,
    ...serifFontNames,
  ];

  /// Google Fonts CSS import URL for a font name.
  static String importUrl(String name) {
    final def = _defs[name];
    if (def == null) return _defs['inter']!.importUrl;
    return def.importUrl;
  }

  /// CSS font-family value.
  static String family(String name) {
    final def = _defs[name];
    if (def == null) return _defs['inter']!.family;
    return def.family;
  }

  /// Recommended font for a style. Returns import URL.
  static String pairForStyle(String styleName) {
    const map = {
      'vega': 'inter',
      'nova': 'inter',
      'maia': 'figtree',
      'lyra': 'jetbrains-mono',
      'mira': 'inter',
      'luma': 'manrope',
      'sera': 'playfair-display',
    };
    return map[styleName] ?? 'inter';
  }

  static final _defs = <String, _FontDef>{
    'geist': const _FontDef(
      family: "'Geist Variable', sans-serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&display=swap',
    ),
    'inter': const _FontDef(
      family: "'Inter Variable', sans-serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap',
    ),
    'noto-sans': const _FontDef(
      family: "'Noto Sans Variable', sans-serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Noto+Sans:wght@400;500;600;700&display=swap',
    ),
    'nunito-sans': const _FontDef(
      family: "'Nunito Sans Variable', sans-serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Nunito+Sans:wght@400;500;600;700&display=swap',
    ),
    'figtree': const _FontDef(
      family: "'Figtree Variable', sans-serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Figtree:wght@400;500;600;700&display=swap',
    ),
    'roboto': const _FontDef(
      family: "'Roboto Variable', sans-serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700&display=swap',
    ),
    'raleway': const _FontDef(
      family: "'Raleway Variable', sans-serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Raleway:wght@400;500;600;700&display=swap',
    ),
    'dm-sans': const _FontDef(
      family: "'DM Sans Variable', sans-serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;700&display=swap',
    ),
    'public-sans': const _FontDef(
      family: "'Public Sans Variable', sans-serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Public+Sans:wght@400;500;600;700&display=swap',
    ),
    'outfit': const _FontDef(
      family: "'Outfit Variable', sans-serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700&display=swap',
    ),
    'oxanium': const _FontDef(
      family: "'Oxanium Variable', sans-serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Oxanium:wght@400;500;600;700&display=swap',
    ),
    'manrope': const _FontDef(
      family: "'Manrope Variable', sans-serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700&display=swap',
    ),
    'space-grotesk': const _FontDef(
      family: "'Space Grotesk Variable', sans-serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&display=swap',
    ),
    'montserrat': const _FontDef(
      family: "'Montserrat Variable', sans-serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700&display=swap',
    ),
    'ibm-plex-sans': const _FontDef(
      family: "'IBM Plex Sans Variable', sans-serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600;700&display=swap',
    ),
    'source-sans-3': const _FontDef(
      family: "'Source Sans 3 Variable', sans-serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Source+Sans+3:wght@400;500;600;700&display=swap',
    ),
    'instrument-sans': const _FontDef(
      family: "'Instrument Sans Variable', sans-serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Instrument+Sans:wght@400;500;600;700&display=swap',
    ),
    // ── Mono ──
    'jetbrains-mono': const _FontDef(
      family: "'JetBrains Mono Variable', monospace",
      importUrl:
          'https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600;700&display=swap',
    ),
    'geist-mono': const _FontDef(
      family: "'Geist Mono Variable', monospace",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Geist+Mono:wght@400;500;600;700&display=swap',
    ),
    // ── Serif ──
    'noto-serif': const _FontDef(
      family: "'Noto Serif Variable', serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Noto+Serif:wght@400;500;700&display=swap',
    ),
    'roboto-slab': const _FontDef(
      family: "'Roboto Slab Variable', serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Roboto+Slab:wght@400;500;600;700&display=swap',
    ),
    'merriweather': const _FontDef(
      family: "'Merriweather Variable', serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Merriweather:wght@400;500;700&display=swap',
    ),
    'lora': const _FontDef(
      family: "'Lora Variable', serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Lora:wght@400;500;600;700&display=swap',
    ),
    'playfair-display': const _FontDef(
      family: "'Playfair Display Variable', serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;500;600;700&display=swap',
    ),
    'eb-garamond': const _FontDef(
      family: "'EB Garamond Variable', serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=EB+Garamond:wght@400;500;600;700&display=swap',
    ),
    'instrument-serif': const _FontDef(
      family: "'Instrument Serif', serif",
      importUrl:
          'https://fonts.googleapis.com/css2?family=Instrument+Serif&display=swap',
    ),
  };
}

class _FontDef {
  const _FontDef({required this.family, required this.importUrl});
  final String family;
  final String importUrl;
}
