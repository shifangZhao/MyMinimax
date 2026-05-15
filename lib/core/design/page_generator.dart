import '../api/minimax_client.dart';
import '../instructor/instructor.dart';
import 'design_analyzer.dart';
import 'tokens/style_presets.dart';
import 'tokens/color_tokens.dart';
import 'tokens/fonts.dart';

class GeneratedPage {

  const GeneratedPage({
    required this.html,
    required this.design,
    this.summary = '',
    this.iterations = 1,
    this.error,
  });
  final String html;
  final MatchedDesign design;
  final String summary;
  final int iterations;
  final String? error;
}

class VariantResult {

  const VariantResult({
    required this.variants,
    required this.best,
    required this.analysis,
  });
  final List<GeneratedPage> variants;
  final GeneratedPage best;
  final String analysis;
}

/// Page generator using the shadcn/ui design system.
///
/// Two modes:
/// 1. **Reference mode**: extract design → match preset → generate page in that style
/// 2. **Freestyle mode**: LLM picks a style based on user's intent → generate page
///
/// In both modes, the LLM does NOT invent colors or component classes.
/// It assembles pages using the curated design token + component recipe library.
class PageGenerator {

  PageGenerator(this._client) : _analyzer = DesignAnalyzer(_client);
  final MinimaxClient _client;
  final DesignAnalyzer _analyzer;

  // ═══════════════════════════════════════════════════════════════
  // Post-processing: guarantee correct CSS injection
  // ═══════════════════════════════════════════════════════════════

  /// Rewrap the LLM's HTML output with guaranteed-correct theme CSS.
  ///
  /// LLMs are unreliable at copying long CSS blocks verbatim. This method
  /// extracts the body content from whatever the LLM generated and rebuilds
  /// a clean HTML document with our exact design token CSS injected.
  /// If parsing fails, returns the original HTML unchanged.
  String _injectThemeCSS(String rawHtml, MatchedDesign design) {
    try {
      // Extract title
      final titleMatch =
          RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(rawHtml);
      final title = titleMatch?.group(1)?.trim() ?? 'Generated Page';

      // Extract body content — everything between <body...> and </body>
      final bodyMatch = RegExp(
        r'<body([^>]*)>(.*)</body>',
        dotAll: true,
      ).firstMatch(rawHtml);

      if (bodyMatch == null) {
        // Can't parse — return original. The LLM might have output something
        // without <body> tags, which is unusual but possible.
        return rawHtml;
      }

      final bodyAttrs = bodyMatch.group(1) ?? '';
      var bodyContent = bodyMatch.group(2) ?? '';

      // Preserve non-style body classes, replace only the style-XXX class
      final classMatch =
          RegExp(r'class="([^"]*)"').firstMatch(bodyAttrs);
      final existingClasses =
          classMatch?.group(1)?.split(' ').where((c) => !c.startsWith('style-'));
      final preservedClasses = [
        'style-${design.style}',
        if (existingClasses != null) ...existingClasses,
      ];
      final cleanBodyAttrs = bodyAttrs
          .replaceAll(RegExp(r'class="[^"]*"'), '')
          .trim();
      final newClassAttr =
          'class="${preservedClasses.join(' ')}"';

      // Extract any <head> content OTHER than <style> (like meta, links)
      final headContent = _extractHeadNonStyle(rawHtml);

      // Extract any <script> tags from the original (Tailwind CDN, config, etc.)
      final scripts = _extractScripts(rawHtml);

      // Build guaranteed-correct CSS
      final css = _buildThemeCSS(design);

      // Reassemble
      return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$title</title>
$headContent
  <style>
/* ═══════════════════════════════════════════════════════════
   Design tokens injected by My Minimax (shadcn/ui system)
   Style: ${design.stylePreset.title} / Base: ${design.baseColor}${design.accentTheme != null ? ' + ${design.accentTheme}' : ''} / Font: ${design.font}
   ═══════════════════════════════════════════════════════════ */
$css
  </style>
$scripts
</head>
<body $cleanBodyAttrs $newClassAttr>
$bodyContent
</body>
</html>''';
    } catch (_) {
      return rawHtml;
    }
  }

  /// Extract non-style head elements (meta, link, preserved <style> blocks).
  String _extractHeadNonStyle(String html) {
    final headMatch =
        RegExp(r'<head>(.*?)</head>', dotAll: true).firstMatch(html);
    if (headMatch == null) return '';
    final head = headMatch.group(1) ?? '';
    // Remove script blocks (we add our own), but preserve <style> blocks.
    // Our theme CSS is injected AFTER preserved styles, so our tokens win.
    return head
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
        .trim();
  }

  /// Extract script tags (Tailwind CDN, config, etc.)
  String _extractScripts(String html) {
    final matches =
        RegExp(r'(<script[^>]*>.*?</script>)', dotAll: true).allMatches(html);
    if (matches.isEmpty) {
      // Default: inject Tailwind CDN
      return '<script src="https://cdn.tailwindcss.com"></script>';
    }
    return matches.map((m) => m.group(1)!).join('\n');
  }

  static final _pageOutputSchema = SchemaDefinition(
    name: 'generate_page',
    description:
        'Generate a complete, self-contained HTML page with Tailwind CSS and theme tokens',
    inputSchema: {
      'type': 'object',
      'properties': {
        'html': {
          'type': 'string',
          'description':
              'Complete HTML document including <!DOCTYPE html>, <head> with Tailwind CDN, font import, theme CSS block, and <body> with page content.',
        },
        'summary': {
          'type': 'string',
          'description':
              'Brief description of the generated page (2-3 sentences).',
        },
      },
      'required': ['html', 'summary'],
    },
    fromJson: (json) => GeneratedPage(
      html: json['html'] as String? ?? '',
      design: MatchedDesign.fallback,
      summary: json['summary'] as String? ?? '',
    ),
  );

  // ═══════════════════════════════════════════════════════════════
  // Reference mode — from extraction
  // ═══════════════════════════════════════════════════════════════

  Future<GeneratedPage> generate({
    required String userRequirements,
    String? extractionJson,
    String? screenshotDescription,
    String? contentText,
    String? style,
    String? baseColor,
    String? accentTheme,
    String? font,
  }) async {
    // Step 1: determine the design
    final MatchedDesign design;
    if (extractionJson != null && extractionJson.isNotEmpty) {
      design = await _analyzer.matchPreset(
        extractionJson,
        screenshotDescription: screenshotDescription,
      );
    } else {
      design = MatchedDesign(
        style: style ?? 'vega',
        baseColor: baseColor ?? 'neutral',
        accentTheme: accentTheme,
        font: font ?? FontTokens.pairForStyle(style ?? 'vega'),
      );
    }

    // Step 2: build the generation prompt
    final prompt = _analyzer.buildPageGenerationPrompt(
      design: design,
      userRequirements: userRequirements,
      contentText: contentText,
    );

    // Step 3: append final instructions
    final fullPrompt = StringBuffer();
    fullPrompt.writeln(prompt);
    fullPrompt.writeln();
    fullPrompt.writeln('## Theme CSS Reference');
    fullPrompt.writeln('The theme CSS will be automatically injected by the system. '
        'Your job is to build the HTML body structure using the semantic tokens. '
        'You can include a `<style>` block for PAGE-SPECIFIC custom styles '
        '(unique layout tweaks, special animations), but the core design tokens '
        '(--primary, --background, --border, etc.) are handled automatically.');
    fullPrompt.writeln();
    fullPrompt.writeln('These CSS variables will be available (defined in the injected theme):');
    for (final key in [
      '--background', '--foreground',
      '--card', '--card-foreground',
      '--primary', '--primary-foreground',
      '--secondary', '--secondary-foreground',
      '--muted', '--muted-foreground',
      '--accent', '--accent-foreground',
      '--destructive', '--destructive-foreground',
      '--border', '--input', '--ring',
      '--radius', '--radius-md', '--radius-lg', '--radius-xl', '--radius-2xl',
    ]) {
      fullPrompt.writeln('- `$key`');
    }
    fullPrompt.writeln();
    fullPrompt.writeln('REMEMBER: `<body>` must have class="style-${design.style}". '
        'All colors via semantic tokens (bg-primary not bg-blue-500). '
        'Any `<style>` you add is for page-specific overrides only. '
        'OUTPUT ONLY the complete HTML file.');

    // Step 4: generate
    try {
      final instructor = Instructor.fromClient(
        _client,
        retryPolicy: const RetryPolicy(maxRetries: 1),
      );
      final maybe = await instructor.extract<GeneratedPage>(
        schema: _pageOutputSchema,
        messages: [Message.user(fullPrompt.toString())],
        maxRetries: 1,
      );

      if (maybe.isSuccess) {
        var html = _injectThemeCSS(maybe.value.html, design);
        if (_isHtmlTruncated(html)) {
          html = await _repairTruncatedHtml(html, design);
        }
        return GeneratedPage(
          html: html,
          design: design,
          summary: maybe.value.summary,
        );
      } else {
        final errMsg = maybe.isFailure ? maybe.error.message : 'Unknown error';
        return GeneratedPage(
          html: '',
          design: design,
          summary: 'Page generation failed. Design preset: ${design.style} + ${design.baseColor}.',
          error: errMsg,
        );
      }
    } catch (e) {
      print('[page] error: \$e');
      return GeneratedPage(
        html: '',
        design: design,
        summary: 'Page generation failed. Design preset: ${design.style} + ${design.baseColor}.',
        error: 'LLM call exception: $e',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Freestyle mode — no reference, LLM picks style
  // ═══════════════════════════════════════════════════════════════

  Future<GeneratedPage> generateFreestyle(String userRequirements) async {
    final prompt = _analyzer.buildFreestylePrompt(userRequirements);

    try {
      final instructor = Instructor.fromClient(
        _client,
        retryPolicy: const RetryPolicy(maxRetries: 1),
      );
      final maybe = await instructor.extract<GeneratedPage>(
        schema: _pageOutputSchema,
        messages: [Message.user(prompt)],
        systemPrompt:
            'You are a world-class frontend designer. You create pages with '
            'strong visual personality. You NEVER output generic AI-looking designs. '
            'Every page you make could be in a design portfolio.',
        maxRetries: 1,
      );

      if (maybe.isSuccess) {
        final rawHtml = maybe.value.html;

        // Extract the style comment to determine the design
        final match = RegExp(
          r'<!--\s*style:(\w+)\s+base:(\w+)\s*(?:accent:(\w+))?\s*font:(\S+)\s*-->',
        ).firstMatch(rawHtml);

        MatchedDesign design = MatchedDesign.fallback;
        if (match != null) {
          design = MatchedDesign(
            style: match.group(1) ?? 'vega',
            baseColor: match.group(2) ?? 'neutral',
            accentTheme: match.group(3),
            font: match.group(4) ?? 'inter',
          );
        }

        // Inject guaranteed-correct CSS, then check for truncation
        var html = _injectThemeCSS(rawHtml, design);
        if (_isHtmlTruncated(html)) {
          html = await _repairTruncatedHtml(html, design);
        }
        return GeneratedPage(
          html: html,
          design: design,
          summary: maybe.value.summary,
        );
      } else {
        final errMsg = maybe.isFailure ? maybe.error.message : 'Unknown error';
        return GeneratedPage(
          html: '',
          design: MatchedDesign.fallback,
          summary: 'Freestyle generation failed.',
          error: errMsg,
        );
      }
    } catch (e) {
      print('[page] error: \$e');
      return GeneratedPage(
        html: '',
        design: MatchedDesign.fallback,
        summary: 'Freestyle generation failed.',
        error: 'LLM call exception: $e',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Convenience
  // ═══════════════════════════════════════════════════════════════

  Future<String> generateHtml({
    required String userRequirements,
    String? extractionJson,
    String? screenshotDescription,
    String? contentText,
    String? style,
    String? baseColor,
    String? accentTheme,
    String? font,
  }) async {
    final result = await generate(
      userRequirements: userRequirements,
      extractionJson: extractionJson,
      screenshotDescription: screenshotDescription,
      contentText: contentText,
      style: style,
      baseColor: baseColor,
      accentTheme: accentTheme,
      font: font,
    );
    if (result.html.isEmpty) {
      throw Exception('Page generation returned empty HTML');
    }
    return result.html;
  }

  // ═══════════════════════════════════════════════════════════════
  // CSS generation
  // ═══════════════════════════════════════════════════════════════

  String _buildThemeCSS(MatchedDesign design) {
    final buf = StringBuffer();

    // Font import
    final fontUrl = FontTokens.importUrl(design.font);
    final fontFamily = FontTokens.family(design.font);
    buf.writeln('/* Font: ${design.font} */');
    buf.writeln('@import url("$fontUrl");');
    buf.writeln();

    // Radius scale
    final s = design.stylePreset;
    final radius = _radiusValue(s);
    buf.writeln(':root {');
    buf.writeln('  --radius: $radius;');
    buf.writeln('  --radius-sm: calc(var(--radius) * 0.6);');
    buf.writeln('  --radius-md: calc(var(--radius) * 0.8);');
    buf.writeln('  --radius-lg: var(--radius);');
    buf.writeln('  --radius-xl: calc(var(--radius) * 1.4);');
    buf.writeln('  --radius-2xl: calc(var(--radius) * 1.8);');
    buf.writeln('  --radius-3xl: calc(var(--radius) * 2.2);');
    buf.writeln('  --radius-4xl: calc(var(--radius) * 2.6);');
    buf.writeln('  --font-sans: $fontFamily;');
    if (design.fontHeading != null) {
      buf.writeln('  --font-heading: ${FontTokens.family(design.fontHeading!)};');
    }
    buf.writeln('}');
    buf.writeln();

    // Color tokens
    buf.write(ColorTokens.buildCSSVars(
      baseColor: design.baseColor,
      accentTheme: design.accentTheme,
    ));
    buf.writeln();

    // Surface & utility tokens
    buf.writeln(':root {');
    buf.writeln('  --surface: var(--background);');
    buf.writeln('  --surface-foreground: var(--foreground);');
    buf.writeln('  --code: var(--muted);');
    buf.writeln('  --code-foreground: var(--muted-foreground);');
    buf.writeln('  --selection: var(--primary);');
    buf.writeln('  --selection-foreground: var(--primary-foreground);');
    buf.writeln('}');
    buf.writeln();

    // Style-specific overrides
    buf.writeln('/* Style overrides for ${s.title} */');
    buf.writeln('.style-${s.name} {');
    buf.writeln('  font-family: var(--font-sans);');
    buf.writeln('  -webkit-font-smoothing: antialiased;');
    buf.writeln('  -moz-osx-font-smoothing: grayscale;');
    buf.writeln('}');
    if (s.uppercase) {
      buf.writeln(
          '.style-${s.name} label, .style-${s.name} .label { text-transform: uppercase; letter-spacing: 0.1em; }');
    }
    buf.writeln();

    // Animation keyframes
    buf.writeln('/* Shared animations */');
    buf.writeln('@keyframes accordion-down {');
    buf.writeln('  from { height: 0; opacity: 0; }');
    buf.writeln('  to { height: var(--accordion-height, auto); opacity: 1; }');
    buf.writeln('}');
    buf.writeln('@keyframes accordion-up {');
    buf.writeln('  from { height: var(--accordion-height, auto); opacity: 1; }');
    buf.writeln('  to { height: 0; opacity: 0; }');
    buf.writeln('}');
    buf.writeln('@keyframes fade-in {');
    buf.writeln('  from { opacity: 0; }');
    buf.writeln('  to { opacity: 1; }');
    buf.writeln('}');
    buf.writeln('@keyframes zoom-in-95 {');
    buf.writeln('  from { opacity: 0; transform: scale(0.95); }');
    buf.writeln('  to { opacity: 1; transform: scale(1); }');
    buf.writeln('}');
    buf.writeln();
    buf.writeln('.animate-in { animation: fade-in 0.15s ease-out, zoom-in-95 0.15s ease-out; }');
    buf.writeln('.animate-out { animation: fade-in 0.1s ease-in reverse, zoom-in-95 0.1s ease-in reverse; }');

    return buf.toString();
  }

  // ═══════════════════════════════════════════════════════════════
  // Compact mode — for simple requests (single component, fast)
  // ═══════════════════════════════════════════════════════════════

  /// Generate a single UI element using a lightweight prompt.
  /// Skips the full intelligence pipeline — 1 API call, ~500 token prompt.
  Future<GeneratedPage> generateCompact({
    required String userRequirements,
    required MatchedDesign design,
  }) async {
    final prompt = _analyzer.buildCompactPrompt(
      design: design,
      userRequirements: userRequirements,
    );

    try {
      final instructor = Instructor.fromClient(
        _client,
        retryPolicy: const RetryPolicy(maxRetries: 0),
      );
      final maybe = await instructor.extract<GeneratedPage>(
        schema: _pageOutputSchema,
        messages: [Message.user(prompt)],
        maxRetries: 0,
      );

      if (maybe.isSuccess && maybe.value.html.isNotEmpty) {
        var html = _injectThemeCSS(maybe.value.html, design);
        if (_isHtmlTruncated(html)) {
          html = await _repairTruncatedHtml(html, design);
        }
        return GeneratedPage(
          html: html,
          design: design,
          summary: maybe.value.summary,
        );
      } else {
        final errMsg = maybe.isFailure ? maybe.error.message : 'Empty response from model';
        return GeneratedPage(
          html: '',
          design: design,
          summary: 'Compact generation failed.',
          error: errMsg,
        );
      }
    } catch (e) {
      print('[page] error: \$e');
      return GeneratedPage(
        html: '',
        design: design,
        summary: 'Compact generation failed.',
        error: 'LLM call exception: $e',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // HTML completeness check + auto-repair
  // ═══════════════════════════════════════════════════════════════

  /// Check if HTML appears truncated (missing closing tags).
  bool _isHtmlTruncated(String html) {
    final trimmed = html.trim();
    return !trimmed.endsWith('</html>') ||
        !trimmed.contains('</body>') ||
        (trimmed.contains('<body') && !trimmed.contains('</body>'));
  }

  /// Attempt to auto-repair truncated HTML by asking LLM to complete it.
  Future<String> _repairTruncatedHtml(String truncated, MatchedDesign design) async {
    final lastChars = truncated.length > 800 ? truncated.substring(truncated.length - 800) : truncated;
    final prompt = '''
The HTML page below was cut off mid-generation. Continue from exactly where it stopped.
Output ONLY the CONTINUATION (the rest of the HTML from the cut point), without repeating any part that's already present.
End with </body></html>.

Last portion of the truncated page:
```html
$lastChars
```

CONTINUE FROM HERE:''';

    try {
      final instructor = Instructor.fromClient(_client, retryPolicy: const RetryPolicy(maxRetries: 0));
      // Use a simple completion schema
      final schema = SchemaDefinition(
        name: 'complete_html',
        description: 'Return only the completion text',
        inputSchema: {
          'type': 'object',
          'properties': {
            'text': {'type': 'string', 'description': 'The continuation HTML'},
          },
          'required': ['text'],
        },
        fromJson: (json) => json['text'] as String? ?? '',
      );
      final maybe = await instructor.extract<String>(
        schema: schema,
        messages: [Message.user(prompt)],
        maxRetries: 0,
      );
      if (maybe.isSuccess && maybe.value.isNotEmpty) {
        final repaired = '$truncated\n${maybe.value}';
        var finalHtml = repaired;
        if (!finalHtml.trim().endsWith('</html>')) {
          finalHtml = '$finalHtml\n</body>\n</html>';
        }
        return _injectThemeCSS(finalHtml, design);
      }
    } catch (_) {}

    // Fallback: just close the tags
    return '$truncated\n</body>\n</html>';
  }

  String _radiusValue(StylePreset s) {
    switch (s.name) {
      case 'lyra':
        return '0';
      case 'sera':
        return '0';
      case 'maia':
        return '0.75rem';
      case 'luma':
        return '0.75rem';
      default:
        return '0.625rem';
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Critique + Refine (iterative polish)
  // ═══════════════════════════════════════════════════════════════

  /// Critique a generated page and refine it. Up to [maxIterations] rounds.
  /// Each round: LLM reviews → identifies issues → regenerates improved version.
  Future<GeneratedPage> critiqueAndRefine(
    GeneratedPage page, {
    int maxIterations = 2,
  }) async {
    var current = page;
    var round = 0;

    while (round < maxIterations) {
      round++;
      final critiquePrompt = '''
## Page to Critique (Round $round/$maxIterations)

Below is an HTML page. Review it against these criteria and identify SPECIFIC issues:

### Review Criteria
1. **Layout & Composition**: Is the visual hierarchy clear? Are sections varied (not all centered heroes)? Is the spacing rhythm intentional?
2. **Typography**: Is there a clear heading/body hierarchy? Are font sizes proportional? Is line-height comfortable?
3. **Interaction**: Do buttons have hover/active states? Are transitions smooth (150-300ms)? Are touch targets adequate?
4. **Originality**: Does this look like a template? Are there distinctive design decisions that give it character?
5. **Anti-patterns**: Linear gradients? Over-shadowed cards? Meaningless taglines? Lorem ipsum?
6. **Color usage**: Are semantic tokens used consistently? Is the accent color used sparingly as a highlight?

### HTML to Review
```html
${current.html.length > 4000 ? '${current.html.substring(0, 4000)}...' : current.html}
```

Output a JSON object with:
- "score": overall score 1-10
- "topIssues": array of 3 most impactful problems (be specific about what to change)
- "quickWins": array of 2 small changes that would make a big difference
- "verdict": "pass" if score >= 8, "refine" otherwise

Respond ONLY with valid JSON: {"score": N, "topIssues": [...], "quickWins": [...], "verdict": "pass"|"refine"}
''';

      try {
        final instructor = Instructor.fromClient(
          _client,
          retryPolicy: const RetryPolicy(maxRetries: 0),
        );
        final critiqueSchema = _critiqueSchema;
        final maybe = await instructor.extract<_CritiqueResult>(
          schema: critiqueSchema,
          messages: [Message.user(critiquePrompt)],
          maxRetries: 0,
        );

        if (!maybe.isSuccess) break;

        final critique = maybe.value;
        if (critique.verdict == 'pass') break;

        // Refine: feed critique back as improvement instructions
        final refinePrompt = '''
## Refinement Instructions
The previous version had these issues (score: ${critique.score}/10):

${critique.topIssues.map((s) => '- $s').join('\n')}

Quick improvements to apply:
${critique.quickWins.map((s) => '- $s').join('\n')}

Regenerate the COMPLETE HTML with these fixes. Keep the same design system (style, colors, font).
The theme CSS is auto-injected — you only need to fix the HTML structure and content.
OUTPUT ONLY the complete HTML file.
''';

        final maybe2 = await instructor.extract<GeneratedPage>(
          schema: _pageOutputSchema,
          messages: [Message.user(refinePrompt)],
          maxRetries: 0,
        );

        if (maybe2.isSuccess && maybe2.value.html.isNotEmpty) {
          current = GeneratedPage(
            html: _injectThemeCSS(maybe2.value.html, current.design),
            design: current.design,
            summary: '${maybe2.value.summary} (refined round $round, was ${critique.score}/10)',
            iterations: round + 1,
          );
        } else {
          break;
        }
      } catch (_) {
        break;
      }
    }

    return current;
  }

  static final _critiqueSchema = SchemaDefinition(
    name: 'critique_page',
    description: 'Critique a generated web page against quality criteria',
    inputSchema: {
      'type': 'object',
      'properties': {
        'score': {'type': 'integer', 'description': 'Overall score 1-10'},
        'topIssues': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'Top 3 most impactful problems',
        },
        'quickWins': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '2 small changes with big impact',
        },
        'verdict': {
          'type': 'string',
          'enum': ['pass', 'refine'],
          'description': 'pass if score >= 8, refine otherwise',
        },
      },
      'required': ['score', 'topIssues', 'quickWins', 'verdict'],
    },
    fromJson: (json) => _CritiqueResult(
      score: (json['score'] as num?)?.toInt() ?? 5,
      topIssues: (json['topIssues'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      quickWins: (json['quickWins'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      verdict: json['verdict'] as String? ?? 'refine',
    ),
  );

  // ═══════════════════════════════════════════════════════════════
  // Multi-variant generation + self-evaluation
  // ═══════════════════════════════════════════════════════════════

  /// Generate 2-3 variants with different layout approaches, then
  /// let the LLM evaluate and pick the best one.
  Future<VariantResult> generateMultiVariant({
    required String userRequirements,
    String? extractionJson,
    String? style,
    String? baseColor,
    String? accentTheme,
    String? font,
  }) async {
    final variants = <GeneratedPage>[];
    final approaches = [
      'Hero-centric: bold full-width hero with large imagery, then feature sections below',
      'Split layout: asymmetric two-column layout, text-heavy with bold typography',
      'Card grid: modular card-based layout, information-dense with clear visual grouping',
    ];

    // Generate variants in parallel if possible, sequentially to be safe
    for (int i = 0; i < approaches.length; i++) {
      final variantReq = '$userRequirements\n\nLayout approach: ${approaches[i]}';
      final page = await generate(
        userRequirements: variantReq,
        extractionJson: extractionJson,
        style: style,
        baseColor: baseColor,
        accentTheme: accentTheme,
        font: font,
      );
      if (page.html.isNotEmpty) {
        variants.add(page);
      }
    }

    if (variants.length < 2) {
      final fallback = variants.isNotEmpty
          ? variants.first
          : const GeneratedPage(html: '', design: MatchedDesign.fallback, summary: 'No variants generated');
      return VariantResult(variants: variants, best: fallback, analysis: 'Not enough variants for comparison.');
    }

    // Evaluate all variants
    final evalPrompt = StringBuffer();
    evalPrompt.writeln('## Evaluate ${variants.length} Page Variants');
    evalPrompt.writeln('Pick the BEST one. Judge on: visual impact, layout originality, information clarity, mobile responsiveness, and overall polish.');
    evalPrompt.writeln();
    for (int i = 0; i < variants.length; i++) {
      final snippet = variants[i].html.length > 2500
          ? '${variants[i].html.substring(0, 2500)}...'
          : variants[i].html;
      evalPrompt.writeln('### Variant ${i + 1} (approach: ${approaches[i]})');
      evalPrompt.writeln('```html');
      evalPrompt.writeln(snippet);
      evalPrompt.writeln('```');
      evalPrompt.writeln();
    }
    evalPrompt.writeln('Output JSON: {"bestIndex": N (1-based), "scores": [N, N, N] (1-10 each), '
        '"analysis": "why the winner is best (2-3 sentences)"}');

    try {
      final instructor = Instructor.fromClient(_client, retryPolicy: const RetryPolicy(maxRetries: 0));
      final evalSchema = _evalSchema;
      final maybe = await instructor.extract<_EvalResult>(
        schema: evalSchema,
        messages: [Message.user(evalPrompt.toString())],
        maxRetries: 0,
      );

      if (maybe.isSuccess) {
        final eval = maybe.value;
        final bestIdx = (eval.bestIndex - 1).clamp(0, variants.length - 1);
        return VariantResult(
          variants: variants,
          best: variants[bestIdx],
          analysis: eval.analysis,
        );
      }
    } catch (_) {}

    // Fallback: return first variant
    return VariantResult(
      variants: variants,
      best: variants.first,
      analysis: 'Auto-selected first variant.',
    );
  }

  static final _evalSchema = SchemaDefinition(
    name: 'evaluate_variants',
    description: 'Evaluate multiple page variants and pick the best',
    inputSchema: {
      'type': 'object',
      'properties': {
        'bestIndex': {
          'type': 'integer',
          'description': '1-based index of the best variant',
        },
        'scores': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'Score 1-10 for each variant in order',
        },
        'analysis': {
          'type': 'string',
          'description': 'Why the winner is best (2-3 sentences)',
        },
      },
      'required': ['bestIndex', 'scores', 'analysis'],
    },
    fromJson: (json) => _EvalResult(
      bestIndex: (json['bestIndex'] as num?)?.toInt() ?? 1,
      scores: (json['scores'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
      analysis: json['analysis'] as String? ?? '',
    ),
  );
}

class _CritiqueResult {
  const _CritiqueResult({
    required this.score,
    required this.topIssues,
    required this.quickWins,
    required this.verdict,
  });
  final int score;
  final List<String> topIssues;
  final List<String> quickWins;
  final String verdict;
}

class _EvalResult {
  const _EvalResult({
    required this.bestIndex,
    required this.scores,
    required this.analysis,
  });
  final int bestIndex;
  final List<int> scores;
  final String analysis;
}
