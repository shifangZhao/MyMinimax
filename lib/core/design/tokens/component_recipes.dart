/// Component Tailwind class recipes ported from shadcn/ui v4.
///
/// Every recipe produces HTML-ready class strings that use ONLY semantic
/// CSS custom property tokens (var(--primary), var(--border), etc.).
/// No color names, no hex values — the CSS variable layer handles theming.
///
/// The LLM's job is to assemble these classes into HTML elements, not
/// to invent new class combinations.
library;
import 'style_presets.dart';

class ComponentRecipes {
  ComponentRecipes._();

  // ═══════════════════════════════════════════════════════════════
  // BUTTON
  // ═══════════════════════════════════════════════════════════════

  static const buttonBase =
      'inline-flex shrink-0 items-center justify-center border border-transparent '
      'font-medium whitespace-nowrap transition-all outline-none select-none '
      'focus-visible:border-ring focus-visible:ring-ring/50 '
      'active:not-aria-[haspopup]:translate-y-px '
      'disabled:pointer-events-none disabled:opacity-50 '
      'aria-invalid:border-destructive aria-invalid:ring-destructive/20 '
      '[&_svg]:pointer-events-none [&_svg]:shrink-0 '
      '[&_svg:not([class*=\'size-\'])]:size-4';

  static const buttonVariants = {
    'default': 'bg-primary text-primary-foreground hover:bg-primary/80',
    'outline':
        'border-border bg-background shadow-xs hover:bg-muted hover:text-foreground',
    'secondary':
        'bg-secondary text-secondary-foreground hover:bg-secondary/80',
    'ghost': 'hover:bg-muted hover:text-foreground',
    'destructive':
        'bg-destructive/10 text-destructive hover:bg-destructive/20',
    'link': 'text-primary underline-offset-4 hover:underline',
  };

  static Map<String, String> buttonSizes(StylePreset s) => {
        'default':
            '${s.buttonDefaultH} gap-1.5 px-2.5 ${s.buttonRadius} ${s.fontSize}',
        'xs':
            '${s.buttonXsH} gap-1 rounded-[min(var(--radius-md),8px)] px-2 text-xs',
        'sm':
            'h-8 gap-1 rounded-[min(var(--radius-md),10px)] px-2.5 text-xs',
        'lg': 'h-10 gap-1.5 px-2.5 ${s.radius} ${s.fontSize}',
        'icon': s.iconSize,
        'icon-xs': 'size-6',
        'icon-sm': 'size-8',
      };

  static String buttonClass(StylePreset s, String variant, String size) {
    final v = buttonVariants[variant] ?? buttonVariants['default']!;
    final sz = buttonSizes(s)[size] ?? buttonSizes(s)['default']!;
    final tw = s.uppercase ? 'uppercase ${s.tracking}' : '';
    return '$buttonBase $v $sz $tw'.trim();
  }

  // ═══════════════════════════════════════════════════════════════
  // CARD
  // ═══════════════════════════════════════════════════════════════

  static String cardClass(StylePreset s) =>
      'flex flex-col gap-${s.name == 'nova' || s.name == 'mira' ? '4' : '6'} '
      'overflow-hidden ${s.cardRadius} bg-card py-${s.name == 'nova' ? '4' : s.name == 'mira' ? '3' : '6'} '
      'text-sm text-card-foreground ${s.cardShadow} '
      '${s.name == 'luma' ? 'ring-1 ring-foreground/10' : ''}';

  static String cardHeader =
      'grid auto-rows-min grid-rows-[auto_auto] items-start gap-1.5 px-6 has-data-[slot=card-action]:grid-cols-[1fr_auto]';
  static String cardTitle =
      'font-medium leading-none tracking-tight';
  static String cardDescription = 'text-muted-foreground text-sm';
  static String cardContent = 'px-6 text-sm';
  static String cardFooter(StylePreset s) =>
      'flex items-center px-6 ${s.name == 'nova' ? 'pt-0 pb-4 bg-muted/50 border-t' : 'pt-0 pb-6'}';

  // ═══════════════════════════════════════════════════════════════
  // BADGE
  // ═══════════════════════════════════════════════════════════════

  static String badgeBase(StylePreset s) =>
      'inline-flex items-center gap-1 rounded-4xl border border-transparent '
      'px-2 py-0.5 text-xs font-medium transition-all '
      '${s.name == 'mira' ? 'text-[0.625rem]' : 'text-xs font-medium'} '
      '[&>svg]:size-3';

  static const badgeVariants = {
    'default': 'bg-primary text-primary-foreground',
    'secondary': 'bg-secondary text-secondary-foreground',
    'outline': 'border-border text-foreground',
    'destructive': 'bg-destructive/10 text-destructive',
    'ghost': 'bg-muted text-muted-foreground hover:bg-muted/80',
    'link': 'text-primary underline-offset-4 hover:underline',
  };

  static String badgeClass(StylePreset s, String variant) {
    final v = badgeVariants[variant] ?? badgeVariants['default']!;
    final tw = s.uppercase ? 'uppercase ${s.tracking}' : '';
    return '${badgeBase(s)} $v $tw'.trim();
  }

  // ═══════════════════════════════════════════════════════════════
  // INPUT / TEXTAREA / SELECT
  // ═══════════════════════════════════════════════════════════════

  static String inputClass(StylePreset s) {
    final base =
        'flex w-full ${s.inputH} ${s.inputRadius} border bg-background '
        'px-3 py-1 text-sm transition-all '
        'file:border-0 file:bg-transparent file:text-sm file:font-medium '
        'placeholder:text-muted-foreground '
        'focus-visible:outline-none focus-visible:ring-ring/50 '
        'disabled:cursor-not-allowed disabled:opacity-50';

    switch (s.inputStyle) {
      case 'borderless-bottom':
        return '$base border-transparent border-b-input rounded-none focus-visible:border-ring ${s.focusRing}';
      case 'filled':
        return '$base bg-input/30 border-transparent focus-visible:border-ring ${s.focusRing}';
      case 'soft':
        return '$base bg-input/50 border-transparent focus-visible:border-ring ${s.focusRing} focus-visible:bg-background';
      default: // full-border
        return '$base border-input focus-visible:border-ring ${s.focusRing}';
    }
  }

  static String textareaClass(StylePreset s) =>
      '${inputClass(s)} min-h-[80px] resize-y';

  static String selectClass(StylePreset s) =>
      '${inputClass(s)} appearance-none pr-8 bg-no-repeat '
      '[background-position:right_0.5rem_center] '
      '[background-size:1.5em_1.5em]';

  // ═══════════════════════════════════════════════════════════════
  // DIALOG / MODAL
  // ═══════════════════════════════════════════════════════════════

  static String dialogOverlay(StylePreset s) =>
      'fixed inset-0 z-50 bg-black/10 data-open:animate-in data-closed:animate-out '
      'data-closed:fade-out-0 data-open:fade-in-0 duration-100 '
      '${s.name == 'luma' ? 'supports-backdrop-filter:backdrop-blur-xs' : ''}';

  static String dialogContent(StylePreset s) =>
      'fixed top-1/2 left-1/2 z-50 grid w-full max-w-[calc(100%-2rem)] '
      '-translate-x-1/2 -translate-y-1/2 gap-6 ${s.cardRadius} bg-popover '
      'p-6 text-sm text-popover-foreground ring-1 ring-foreground/10 '
      'duration-100 outline-none sm:max-w-md '
      'data-open:animate-in data-open:fade-in-0 data-open:zoom-in-95 '
      'data-closed:animate-out data-closed:fade-out-0 data-closed:zoom-out-95';

  static String dialogHeader =
      'flex flex-col gap-1.5 text-center sm:text-left';
  static String dialogFooter =
      'flex flex-col-reverse gap-2 sm:flex-row sm:justify-end';
  static String dialogTitle = 'text-lg font-medium leading-none tracking-tight';
  static String dialogDescription = 'text-sm text-muted-foreground';

  // ═══════════════════════════════════════════════════════════════
  // NAV / NAVBAR
  // ═══════════════════════════════════════════════════════════════

  static String navInline(StylePreset s) =>
      'sticky top-0 z-40 w-full border-b bg-background/95 backdrop-blur '
      'supports-backdrop-filter:bg-background/60';

  static String navInner =
      'flex h-14 items-center justify-between px-4 sm:px-6';

  static String navLinks =
      'flex items-center gap-4 text-sm font-medium text-muted-foreground';

  static String navLinkActive = 'text-foreground';

  static String navSidebar(StylePreset s) =>
      'fixed top-0 left-0 z-30 h-full w-64 border-r bg-sidebar '
      'text-sidebar-foreground';

  // ═══════════════════════════════════════════════════════════════
  // SECTION LAYOUTS
  // ═══════════════════════════════════════════════════════════════

  static String section =
      'w-full py-12 md:py-16 lg:py-20';

  static String sectionHero =
      'w-full py-16 md:py-24 lg:py-32';

  static String sectionCta =
      'w-full py-12 md:py-16 bg-muted';

  static String container =
      'mx-auto max-w-6xl px-4 sm:px-6 lg:px-8';

  static String containerNarrow =
      'mx-auto max-w-3xl px-4 sm:px-6 lg:px-8';

  // ═══════════════════════════════════════════════════════════════
  // AVATAR
  // ═══════════════════════════════════════════════════════════════

  static String avatar(StylePreset s) =>
      'inline-flex size-8 shrink-0 items-center justify-center rounded-full '
      'bg-muted text-muted-foreground overflow-hidden '
      'data-[size=lg]:size-10 data-[size=sm]:size-6';

  static String avatarFallback =
      'flex h-full w-full items-center justify-center rounded-full bg-muted '
      'text-muted-foreground text-xs font-medium';

  static String avatarImage = 'h-full w-full rounded-full object-cover';

  // ═══════════════════════════════════════════════════════════════
  // UTILITY: full component class reference for LLM prompt
  // ═══════════════════════════════════════════════════════════════

  /// Build a complete component class reference to inject into the
  /// page generation prompt. The LLM should use these exact classes
  /// rather than inventing new ones.
  static String buildPromptReference(StylePreset s) {
    final buf = StringBuffer();

    buf.writeln('## Component Class Reference');
    buf.writeln();
    buf.writeln('Use THESE EXACT Tailwind classes for every component. '
        'Do not invent new class combinations. '
        'All color tokens (primary, muted, border, etc.) are CSS variables '
        'defined in the theme layer — they work directly as Tailwind utilities.');
    buf.writeln();

    // Button
    buf.writeln('### Button');
    buf.writeln('Base: `$buttonBase`');
    buf.writeln();
    buf.writeln('Variants:');
    for (final v in buttonVariants.entries) {
      buf.writeln('- `${v.key}`: `$buttonBase ${v.value} ${buttonSizes(s)['default']}`');
    }
    buf.writeln();
    buf.writeln('Sizes:');
    for (final sz in buttonSizes(s).entries) {
      buf.writeln('- `${sz.key}`: ... `${sz.value}`');
    }
    buf.writeln();
    buf.writeln('Icons inside buttons: add `[&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*=\'size-\'])]:size-4`');
    buf.writeln();

    // Card
    buf.writeln('### Card');
    buf.writeln('- Card: `${cardClass(s)}`');
    buf.writeln('- CardHeader: `$cardHeader`');
    buf.writeln('- CardTitle: `$cardTitle`');
    buf.writeln('- CardDescription: `$cardDescription`');
    buf.writeln('- CardContent: `$cardContent`');
    buf.writeln('- CardFooter: `${cardFooter(s)}`');
    buf.writeln();

    // Badge
    buf.writeln('### Badge');
    buf.writeln('- Base: `${badgeBase(s)}`');
    for (final v in badgeVariants.entries) {
      buf.writeln('- ${v.key}: ... `${v.value}`');
    }
    buf.writeln();

    // Input
    buf.writeln('### Input / Textarea / Select');
    buf.writeln('- Input: `${inputClass(s)}`');
    buf.writeln('- Textarea: `${textareaClass(s)}`');
    buf.writeln('- Select: `${selectClass(s)}`');
    buf.writeln();

    // Dialog
    buf.writeln('### Dialog / Modal');
    buf.writeln('- Overlay: `${dialogOverlay(s)}`');
    buf.writeln('- Content: `${dialogContent(s)}`');
    buf.writeln('- Header: `$dialogHeader`');
    buf.writeln('- Footer: `$dialogFooter`');
    buf.writeln('- Title: `$dialogTitle`');
    buf.writeln('- Description: `$dialogDescription`');
    buf.writeln();

    // Nav
    buf.writeln('### Navigation');
    buf.writeln('- Top nav bar: `${navInline(s)}`');
    buf.writeln('- Nav inner: `$navInner`');
    buf.writeln('- Nav links: `$navLinks`');
    buf.writeln('- Active link: `$navLinkActive`');
    buf.writeln('- Sidebar: `${navSidebar(s)}`');
    buf.writeln();

    // Sections
    buf.writeln('### Section Layouts');
    buf.writeln('- Default section: `$section`');
    buf.writeln('- Hero section: `$sectionHero`');
    buf.writeln('- CTA section: `$sectionCta`');
    buf.writeln('- Container: `$container`');
    buf.writeln('- Narrow container: `$containerNarrow`');
    buf.writeln();

    // Avatar
    buf.writeln('### Avatar');
    buf.writeln('- Avatar: `${avatar(s)}`');
    buf.writeln('- Fallback: `$avatarFallback`');
    buf.writeln('- Image: `$avatarImage`');
    buf.writeln();

    buf.writeln('## Key Rules');
    buf.writeln('1. All interactive elements need `focus-visible:outline-none` + the focus ring from the style');
    buf.writeln('2. No hardcoded colors. Use semantic tokens: bg-primary, text-muted-foreground, border-border, ring-ring/50');
    buf.writeln('3. All disabled states: `disabled:pointer-events-none disabled:opacity-50`');
    buf.writeln('4. Hover states should be subtle: `hover:bg-muted`, `hover:text-foreground`, `hover:underline`');
    buf.writeln('5. NEVER use: linear gradients on buttons, over-saturated shadows, excessive rounded corners outside the style, purple/blue as default accent without the user asking');
    buf.writeln('6. Use real content — no Lorem ipsum. If you need placeholder data, make it realistic for the page context.');
    buf.writeln('7. Mobile-first: stack on small screens (`flex-col`), side-by-side on md+ (`md:flex-row`).');
    buf.writeln('8. Page must have a clear visual hierarchy: one primary heading (h1), section headings (h2), and body text.');

    return buf.toString();
  }
}
