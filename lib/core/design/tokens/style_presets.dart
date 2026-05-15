/// 7 visual style presets ported from shadcn/ui v4.
/// Each style defines a complete visual language: radius strategy, spacing,
/// typography scale, shadow depth, and input border treatment.
class StylePreset {

  const StylePreset({
    required this.name,
    required this.title,
    required this.description,
    required this.radius,
    required this.cardRadius,
    required this.buttonRadius,
    required this.inputRadius,
    required this.menuRadius,
    required this.fontSize,
    required this.fontWeight,
    required this.buttonDefaultH, required this.buttonXsH, required this.inputH, required this.iconSize, required this.cardShadow, required this.focusRing, required this.dialogShadow, required this.inputStyle, required this.bestFor, required this.pairFont, this.uppercase = false,
    this.tracking = '',
  });
  final String name;
  final String title;
  final String description;

  // ── Core geometry ──
  final String radius; // rounded-md, rounded-lg, rounded-4xl, rounded-none
  final String cardRadius;
  final String buttonRadius;
  final String inputRadius;
  final String menuRadius;

  // ── Typography ──
  final String fontSize;
  final String fontWeight;
  final bool uppercase;
  final String tracking;

  // ── Sizing ──
  final String buttonDefaultH;
  final String buttonXsH;
  final String inputH;
  final String iconSize;

  // ── Depth ──
  final String cardShadow;
  final String focusRing;
  final String dialogShadow;

  // ── Input strategy ──
  final String inputStyle; // full-border, borderless-bottom, filled, soft

  // ── Best pairing ──
  final String bestFor;
  final String pairFont;

  static const presets = [
    StylePreset(
      name: 'vega',
      title: 'Vega',
      description: 'Clean, neutral, and familiar — the canonical starting point',
      radius: 'rounded-md',
      cardRadius: 'rounded-xl',
      buttonRadius: 'rounded-md',
      inputRadius: 'rounded-md',
      menuRadius: 'rounded-md',
      fontSize: 'text-sm',
      fontWeight: 'font-medium',
      buttonDefaultH: 'h-9',
      buttonXsH: 'h-6',
      inputH: 'h-9',
      iconSize: 'size-9',
      cardShadow: 'shadow-xs',
      focusRing: 'ring-3',
      dialogShadow: '',
      inputStyle: 'full-border',
      bestFor: 'SaaS dashboards, admin panels, general-purpose apps',
      pairFont: 'inter',
    ),
    StylePreset(
      name: 'nova',
      title: 'Nova',
      description: 'Reduced padding and margins — information-dense but comfortable',
      radius: 'rounded-lg',
      cardRadius: 'rounded-xl',
      buttonRadius: 'rounded-lg',
      inputRadius: 'rounded-lg',
      menuRadius: 'rounded-lg',
      fontSize: 'text-sm',
      fontWeight: 'font-medium',
      buttonDefaultH: 'h-8',
      buttonXsH: 'h-6',
      inputH: 'h-8',
      iconSize: 'size-8',
      cardShadow: '',
      focusRing: 'ring-3',
      dialogShadow: '',
      inputStyle: 'full-border',
      bestFor: 'Data-heavy tools, internal dashboards, developer tools',
      pairFont: 'inter',
    ),
    StylePreset(
      name: 'maia',
      title: 'Maia',
      description: 'Rounded, with generous spacing — soft and approachable',
      radius: 'rounded-4xl',
      cardRadius: 'rounded-2xl',
      buttonRadius: 'rounded-4xl',
      inputRadius: 'rounded-4xl',
      menuRadius: 'rounded-2xl',
      fontSize: 'text-sm',
      fontWeight: 'font-medium',
      buttonDefaultH: 'h-9',
      buttonXsH: 'h-6',
      inputH: 'h-9',
      iconSize: 'size-9',
      cardShadow: 'shadow-xs',
      focusRing: 'ring-[3px]',
      dialogShadow: 'shadow-2xl',
      inputStyle: 'filled',
      bestFor: 'Consumer apps, lifestyle, wellness, community platforms',
      pairFont: 'figtree',
    ),
    StylePreset(
      name: 'lyra',
      title: 'Lyra',
      description: 'Boxy and sharp. For mono fonts — brutalist clarity',
      radius: 'rounded-none',
      cardRadius: 'rounded-none',
      buttonRadius: 'rounded-none',
      inputRadius: 'rounded-none',
      menuRadius: 'rounded-none',
      fontSize: 'text-xs',
      fontWeight: 'font-medium',
      buttonDefaultH: 'h-8',
      buttonXsH: 'h-6',
      inputH: 'h-8',
      iconSize: 'size-8',
      cardShadow: 'shadow-xs',
      focusRing: 'ring-1',
      dialogShadow: '',
      inputStyle: 'full-border',
      bestFor: 'Architecture portfolios, editorial, code-focused tools',
      pairFont: 'jetbrains-mono',
    ),
    StylePreset(
      name: 'mira',
      title: 'Mira',
      description: 'Made for compact interfaces — smallest scale, highest density',
      radius: 'rounded-md',
      cardRadius: 'rounded-md',
      buttonRadius: 'rounded-md',
      inputRadius: 'rounded-md',
      menuRadius: 'rounded-md',
      fontSize: 'text-xs',
      fontWeight: 'font-medium',
      buttonDefaultH: 'h-7',
      buttonXsH: 'h-5',
      inputH: 'h-7',
      iconSize: 'size-7',
      cardShadow: '',
      focusRing: 'ring-2',
      dialogShadow: '',
      inputStyle: 'filled',
      bestFor: 'Data grids, trading terminals, analytics dashboards',
      pairFont: 'inter',
    ),
    StylePreset(
      name: 'luma',
      title: 'Luma',
      description: 'Fluid, luminous, and soft — glossy depth with rich shadows',
      radius: 'rounded-4xl',
      cardRadius: 'rounded-4xl',
      buttonRadius: 'rounded-4xl',
      inputRadius: 'rounded-3xl',
      menuRadius: 'rounded-2xl',
      fontSize: 'text-sm',
      fontWeight: 'font-medium',
      buttonDefaultH: 'h-9',
      buttonXsH: 'h-6',
      inputH: 'h-9',
      iconSize: 'size-9',
      cardShadow: 'shadow-xl',
      focusRing: 'ring-3',
      dialogShadow: 'shadow-xl',
      inputStyle: 'soft',
      bestFor: 'Premium brand pages, creative portfolios, luxury products',
      pairFont: 'manrope',
    ),
    StylePreset(
      name: 'sera',
      title: 'Sera',
      description: 'Editorial and typographic — magazine-like, uppercase labels',
      radius: 'rounded-none',
      cardRadius: 'rounded-none',
      buttonRadius: 'rounded-none',
      inputRadius: 'rounded-none',
      menuRadius: 'rounded-none',
      fontSize: 'text-xs',
      fontWeight: 'font-semibold',
      uppercase: true,
      tracking: 'tracking-widest',
      buttonDefaultH: 'h-10',
      buttonXsH: 'h-7',
      inputH: 'h-10',
      iconSize: 'size-10',
      cardShadow: '',
      focusRing: 'ring-2',
      dialogShadow: '',
      inputStyle: 'borderless-bottom',
      bestFor: 'Fashion, editorial, luxury editorial, high-end brand stories',
      pairFont: 'playfair-display',
    ),
  ];

  static StylePreset find(String name) =>
      presets.firstWhere((s) => s.name == name, orElse: () => presets[0]);

  /// Build a concise style description for the LLM generation prompt.
  String get promptDescription => '''
Style: $title — $description
- Radius: $radius (cards: $cardRadius, buttons: $buttonRadius, inputs: $inputRadius)
- Typography: $fontSize $fontWeight${uppercase ? ' uppercase $tracking' : ''}
- Button: $buttonDefaultH default, $buttonXsH compact
- Input: $inputH, $inputStyle
- Card shadow: ${cardShadow.isEmpty ? 'none' : cardShadow}
- Focus ring: $focusRing
- Best for: $bestFor
- Recommended font: $pairFont''';
}
