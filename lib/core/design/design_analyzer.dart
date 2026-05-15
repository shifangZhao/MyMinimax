import 'dart:convert';
import '../instructor/instructor.dart';
import '../api/minimax_client.dart';
import 'tokens/style_presets.dart';
import 'tokens/component_recipes.dart';
import 'tokens/color_tokens.dart';
import 'tokens/fonts.dart';
import 'tokens/product_router.dart';
import 'tokens/ux_rules.dart';
import 'tokens/font_pairings.dart';
import 'tokens/landing_patterns.dart';
import 'tokens/style_library.dart';
import 'tokens/galaxy_ui.dart';
import 'tokens/style_bridge.dart';

/// Result of matching an extracted design to the shadcn preset library.
class MatchedDesign {

  const MatchedDesign({
    required this.style,
    required this.baseColor,
    required this.font, this.accentTheme,
    this.fontHeading,
  });
  final String style; // vega, nova, maia, lyra, mira, luma, sera
  final String baseColor; // neutral, stone, zinc, mauve, olive, mist, taupe
  final String? accentTheme; // blue, amber, emerald, etc.
  final String font; // inter, figtree, jetbrains-mono, etc.
  final String? fontHeading;

  StylePreset get stylePreset => StylePreset.find(style);

  /// Default design — clean, neutral, universal.
  static const fallback = MatchedDesign(
    style: 'vega',
    baseColor: 'neutral',
    font: 'inter',
  );
}

/// Maps extracted website design data to the closest shadcn/ui preset.
///
/// Instead of asking the LLM to freely invent a design brief (which produces
/// inconsistent, often low-quality output), we ask it to answer 4 specific
/// multiple-choice questions. The output is a concrete selection from our
/// curated library of styles, colors, and fonts.
class DesignAnalyzer {

  DesignAnalyzer(this._client);
  final MinimaxClient _client;

  /// Schema that forces the LLM to pick from our curated options.
  static final _matchSchema = SchemaDefinition(
    name: 'match_design',
    description: 'Match an extracted website design to the closest shadcn/ui preset',
    inputSchema: {
      'type': 'object',
      'properties': {
        'style': {
          'type': 'string',
          'description': 'Which visual style does this page most resemble?\n'
              'Options and their characteristics:\n'
              '- vega: clean, neutral, rounded-medium, balanced — the default\n'
              '- nova: compact, reduced padding, efficient — good for dashboards\n'
              '- maia: very rounded, generous spacing, soft — consumer apps\n'
              '- lyra: sharp corners, small text, boxy — brutalist/editorial\n'
              '- mira: smallest scale, densest — data-heavy interfaces\n'
              '- luma: highly rounded, rich shadows, glossy — premium brands\n'
              '- sera: sharp corners, uppercase labels, serif fonts — editorial/fashion\n'
              'Pick the ONE best match.',
          'enum': StylePreset.presets.map((s) => s.name).toList(),
        },
        'baseColor': {
          'type': 'string',
          'description': 'Which neutral/gray base does this page use?\n'
              '- neutral: pure gray, no color cast\n'
              '- stone: warm gray, slight brown undertone\n'
              '- zinc: cool gray, slight blue undertone\n'
              '- mauve: purple-tinted gray\n'
              '- olive: green-tinted gray\n'
              '- mist: blue-gray, airy\n'
              '- taupe: brown-gray, earthy',
          'enum': ColorTokens.baseColorNames,
        },
        'accentTheme': {
          'type': 'string',
          'description': 'What accent/highlight color does this page use? '
              'Leave empty if the page is monochrome or neutral-only. '
              'Pick from: amber, blue, cyan, emerald, fuchsia, green, indigo, '
              'lime, orange, pink, purple, red, rose, sky, teal, violet, yellow.',
          'enum': ['', ...ColorTokens.accentThemeNames],
        },
        'font': {
          'type': 'string',
          'description': 'Which font most closely matches the page typography?\n'
              'Sans: inter, geist, figtree, roboto, raleway, dm-sans, outfit, '
              'manrope, space-grotesk, montserrat, ibm-plex-sans\n'
              'Mono: jetbrains-mono, geist-mono\n'
              'Serif: noto-serif, merriweather, lora, playfair-display, eb-garamond\n'
              'Pick the closest match.',
          'enum': FontTokens.allFontNames,
        },
      },
    },
    fromJson: (json) => MatchedDesign(
      style: (json['style'] as String? ?? 'vega'),
      baseColor: (json['baseColor'] as String? ?? 'neutral'),
      accentTheme: _nonEmpty((json['accentTheme'] as String?) ?? ''),
      font: (json['font'] as String? ?? 'inter'),
    ),
  );

  /// Match an extracted design to the closest shadcn preset.
  ///
  /// [extractionJson] is the raw JSON output from [browser_extract_design].
  /// [screenshotDescription] is an optional text description of visual appearance.
  ///
  /// Returns a [MatchedDesign] with concrete style/color/font choices.
  /// Falls back to [MatchedDesign.fallback] on failure.
  Future<MatchedDesign> matchPreset(
    String extractionJson, {
    String? screenshotDescription,
  }) async {
    try {
      final raw = jsonDecode(extractionJson) as Map<String, dynamic>;

      // Trim the extraction to key data — field names match the JS output
      final brief = <String, dynamic>{};
      // JS outputs 'colors', but also support 'palette' for compatibility
      if (raw['colors'] != null) {
        brief['colors'] = raw['colors'];
      } else if (raw['palette'] != null) {
        brief['colors'] = raw['palette'];
      }
      // JS outputs 'fonts' (array of {family, size, weight, role})
      if (raw['fonts'] != null) brief['fonts'] = raw['fonts'];
      if (raw['typography'] != null) brief['typography'] = raw['typography'];
      if (raw['layout'] != null) brief['layout'] = raw['layout'];
      if (raw['interactions'] != null) {
        brief['interactions'] = raw['interactions'];
      }
      if (raw['components'] != null) brief['components'] = raw['components'];
      if (raw['spacing'] != null) brief['spacing'] = raw['spacing'];
      if (raw['borders'] != null) brief['borders'] = raw['borders'];
      if (raw['buttonVariants'] != null) brief['buttonVariants'] = raw['buttonVariants'];

      var userContent =
          '## Extracted Design Data\n```json\n${const JsonEncoder.withIndent('  ').convert(brief)}\n```';

      if (screenshotDescription != null && screenshotDescription.isNotEmpty) {
        userContent += '\n\n## Visual Appearance\n$screenshotDescription';
      }

      userContent +=
          '\n\nTask: match this extracted design data to the closest shadcn/ui v4 preset. '
              'Answer each question with the single best choice.';

      final instructor = Instructor.fromClient(
        _client,
        retryPolicy: const RetryPolicy(maxRetries: 1),
      );

      final maybe = await instructor.extract<MatchedDesign>(
        schema: _matchSchema,
        messages: [Message.user(userContent)],
        systemPrompt:
            '将提取的 CSS 数据匹配到最接近的预设。关注整体感受（圆角策略、间距密度、色温、排版特征），'
            '不追求像素级精确。不确定时默认 vega + neutral + inter。',
        maxRetries: 1,
      );

      if (maybe.isSuccess) return maybe.value;
    } catch (_) {
      // Fall through to fallback
    }
    return MatchedDesign.fallback;
  }

  /// 基于匹配到的设计预设，构建完整的页面生成提示词。
  ///
  /// [design] 是 [matchPreset] 返回的匹配预设。
  /// [userRequirements] 是用户要构建的内容。
  /// [contentText] 是可选参考页面预提取的文本内容。
  String buildPageGenerationPrompt({
    required MatchedDesign design,
    required String userRequirements,
    String? contentText,
  }) {
    final s = design.stylePreset;
    final buf = StringBuffer();

    buf.writeln('你是资深前端开发兼UX设计师。创造有辨识度的页面，不要通用"AI模板风"。');
    buf.writeln();

    // 反模式
    buf.writeln('## 禁止');
    buf.writeln('- 线性渐变按钮（bg-gradient-to-r）');
    buf.writeln('- 紫/靛蓝色强调色（除非风格明确要求）');
    buf.writeln('- 巨大圆角卡片 + 全页面重阴影（shadow-2xl）');
    buf.writeln('- 居中的 h1 + 副标题 + CTA 的英雄区——变换你的版式');
    buf.writeln('- "颠覆你的工作流"之类的空洞标语');
    buf.writeln('- 千篇一律的 图标+标题+描述 卡片网格');
    buf.writeln();

    // 设计系统
    buf.writeln('## 设计系统');
    buf.writeln(s.promptDescription);
    buf.writeln('基础色: ${design.baseColor}');
    if (design.accentTheme != null) {
      buf.writeln('强调色: ${design.accentTheme}');
    }
    buf.writeln('字体: ${design.font}');
    buf.writeln();

    // 组件配方
    buf.writeln(ComponentRecipes.buildPromptReference(s));
    buf.writeln();

    // CSS 技术参考（从 Galaxy UI 库按需注入）
    final keywords = s.bestFor.toLowerCase();
    final relevantTechs = <String>[];
    if (keywords.contains('compact') || keywords.contains('dense') || keywords.contains('data')) {
      relevantTechs.addAll(['sharp-corners', 'glow-shadow']);
    }
    if (keywords.contains('rounded') || keywords.contains('soft') || keywords.contains('spacious')) {
      relevantTechs.addAll(['gradient', 'glassmorphism', 'text-shadow']);
    }
    if (keywords.contains('sharp') || keywords.contains('brutal') || keywords.contains('mono')) {
      relevantTechs.addAll(['sharp-corners', 'typography-transform', 'svg-icon']);
    }
    if (keywords.contains('luxury') || keywords.contains('premium') || keywords.contains('gloss')) {
      relevantTechs.addAll(['glassmorphism', 'glow-shadow', 'cubic-bezier', 'gradient']);
    }
    relevantTechs.addAll(['3d-transform', 'animation']);

    for (final tech in relevantTechs.toSet().take(4)) {
      final ref = GalaxyUI.buildTechniqueRef(tech);
      if (ref.isNotEmpty) buf.writeln(ref);
    }
    buf.writeln();

    // 色板 Token
    buf.writeln('## 色板Token');
    buf.writeln('所有颜色用 CSS 变量 (--primary, --background, --border 等)，系统已预注入。');
    buf.writeln('用 class="bg-primary text-primary-foreground"，禁止 style="background: #3B82F6"。');
    buf.writeln('<style> 块仅用于页面特定覆盖（动画、网格），不要重定义核心 token。');
    buf.writeln();

    // 页面需求
    buf.writeln('## 页面需求');
    buf.writeln(userRequirements);

    if (contentText != null && contentText.isNotEmpty) {
      buf.writeln();
      buf.writeln('## 参考内容');
      buf.writeln('以下真实文本可酌情使用：');
      buf.writeln(contentText);
    }

    buf.writeln();
    buf.writeln('## 输出要求');
    buf.writeln('- 单文件 HTML: `<!DOCTYPE html>` 到 `</html>`');
    buf.writeln('- Tailwind v4 CDN + Google Fonts 字体导入');
    buf.writeln('- `<body class="style-${design.style}">`');
    buf.writeln('- 移动优先，语义 HTML，真实内容（非 Lorem ipsum）');
    buf.writeln('- 交互元素加 hover/transition（150-250ms）');
    buf.writeln('- 只输出完整 HTML，不要 markdown 围栏、不要解释');
    buf.writeln();
    buf.writeln(UxRules.promptChecklist);

    final fp = FontPairings.find(design.font);
    if (fp != null) {
      buf.writeln();
      buf.writeln('## 字体搭配建议');
      buf.writeln(fp.promptHint);
    }

    return buf.toString();
  }

  /// 构建自由风格提示词（无参考设计）。
  /// 由 LLM 自行选择最适合用户描述的风格。
  String buildFreestylePrompt(String userRequirements) {
    final buf = StringBuffer();

    buf.writeln('你是资深前端开发兼UX设计师，有很强的审美判断力。');
    buf.writeln();

    // 产品类型检测
    final product = ProductRouter.match(userRequirements);
    if (product != null) {
      buf.writeln('## 产品语境');
      buf.writeln('用户需求暗示产品类型: **${product.category}**');
      buf.writeln('- 推荐风格: ${product.styles}');
      buf.writeln('- 色彩方向: ${product.color}');
      buf.writeln('- 排版感觉: ${product.typo}');
      buf.writeln('- 效果: ${product.effects}');
      buf.writeln('- 避免: ${product.anti}');
      buf.writeln();

      // 匹配风格详情
      for (final styleName in product.styles.split('+').map((s) => s.trim())) {
        final spec = StyleLibrary.find(styleName);
        if (spec != null && spec.hasDeepSpec) {
          buf.writeln('### ${spec.deepFullName}');
          buf.writeln(spec.deepDesc);
          buf.writeln();
          break;
        }
      }

      final fontPair = FontPairings.find(product.typo);
      if (fontPair != null) {
        buf.writeln('### 推荐字体搭配');
        buf.writeln(fontPair.promptHint);
        buf.writeln();
      }

      final landing = LandingPatterns.match(product.pattern);
      if (landing != null) {
        buf.writeln('### 推荐分区结构');
        buf.writeln(landing.promptHint);
        buf.writeln();
      }

      final bridge = StyleBridge.bridge(product.styles);
      buf.writeln('### Shadcn 风格映射');
      buf.writeln('推荐 shadcn 预设: **${bridge.style}** (基础: ${bridge.baseColor})');
      buf.writeln('- 强调色方向: ${bridge.accentHint}');
      buf.writeln('- 字体方向: ${bridge.fontHint}');
      buf.writeln('除非用户明确反对，否则使用此推荐。');
      buf.writeln();
    }

    // 风格选择 — 注入所有预设
    buf.writeln('## 风格选择');
    buf.writeln('选择最匹配的一套 风格+颜色+字体 组合：');
    buf.writeln();
    for (final s in StylePreset.presets) {
      buf.writeln('- **${s.title}** (${s.name}): ${s.description}。适合: ${s.bestFor}');
    }
    buf.writeln();
    buf.writeln('基础色: neutral(纯灰), stone(暖灰), zinc(冷灰), mauve(紫灰), olive(绿灰), mist(蓝灰), taupe(棕灰)');
    buf.writeln('强调色(可选): amber, blue, cyan, emerald, fuchsia, green, indigo, lime, orange, pink, purple, red, rose, sky, teal, violet, yellow');
    buf.writeln('字体: inter, geist, figtree, roboto, manrope, space-grotesk, montserrat, jetbrains-mono, playfair-display, merriweather, lora, eb-garamond');
    buf.writeln();
    buf.writeln('选定后在 HTML 最开头插入注释:');
    buf.writeln('`<!-- style:风格名 base:基础色 accent:强调色 font:字体 -->`');
    buf.writeln();

    // 反模式
    buf.writeln('## 禁止');
    buf.writeln('- 线性渐变按钮');
    buf.writeln('- 全页面重阴影的大圆角卡片');
    buf.writeln('- "居中 h1 + 副标题 + CTA按钮" 式英雄区');
    buf.writeln('- 千篇一律的 图标+标题+描述 卡片网格');
    buf.writeln('- 空洞标语如"颠覆你的工作流"');
    buf.writeln('- 过度饱和配色——只选一个强调色，克制使用');
    buf.writeln('- 系统默认字体——始终导入你选的 Google Font');
    if (product != null) {
      buf.writeln('- 行业特化: ${product.anti}');
    }
    buf.writeln();

    // 组件类
    buf.writeln('## 组件类');
    buf.writeln('按钮: `inline-flex items-center justify-center rounded-md text-sm font-medium transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50 disabled:pointer-events-none disabled:opacity-50 [&_svg]:size-4`');
    buf.writeln('- default: `bg-primary text-primary-foreground hover:bg-primary/80 h-9 px-4`');
    buf.writeln('- outline: `border border-input bg-background hover:bg-muted h-9 px-4`');
    buf.writeln('- ghost: `hover:bg-muted h-9 px-4`');
    buf.writeln('- destructive: `bg-destructive/10 text-destructive hover:bg-destructive/20 h-9 px-4`');
    buf.writeln();
    buf.writeln('卡片: `rounded-xl border bg-card text-card-foreground shadow-sm`');
    buf.writeln('输入框: `flex h-9 rounded-md border border-input bg-background px-3 py-1 text-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50`');
    buf.writeln('徽标: `inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold transition-colors`');
    buf.writeln();

    // 色彩规则
    buf.writeln('## 色彩规则');
    buf.writeln('所有颜色必须用 CSS 自定义属性（Tailwind 工具类形式）：');
    buf.writeln('- 背景: bg-background, bg-card, bg-popover, bg-muted, bg-primary, bg-secondary, bg-accent');
    buf.writeln('- 文字: text-foreground, text-card-foreground, text-muted-foreground, text-primary-foreground');
    buf.writeln('- 边框: border-border, border-input, border-ring');
    buf.writeln('- 禁止: 原始 hex/rgb() 或 Tailwind 颜色名 (blue-500, gray-100)');
    buf.writeln('- 禁止: inline style="color: ..."——用 class token');
    buf.writeln();

    buf.writeln('## 用户需求');
    buf.writeln(userRequirements);
    buf.writeln();

    buf.writeln('## 输出');
    buf.writeln('- 单文件 HTML');
    buf.writeln('- Tailwind v4 CDN + Google Fonts 字体导入');
    buf.writeln('- `<style>` 块仅用于页面特定覆盖，核心 token 系统已预注入');
    buf.writeln('- `<body>` 带风格 class');
    buf.writeln('- 真实内容，移动优先，语义 HTML');
    buf.writeln('- 只输出 HTML——不要 markdown 围栏、不要解释');
    buf.writeln();
    buf.writeln(UxRules.promptChecklist);

    return buf.toString();
  }

  // ═══════════════════════════════════════════════════════════════
  // Complexity detection + compact mode
  // ═══════════════════════════════════════════════════════════════

  /// Detect whether the user's request is simple or complex.
  /// Simple = single component, no layout decisions needed.
  /// Complex = full page with multiple sections.
  static bool isSimpleRequest(String userRequirements) {
    final q = userRequirements.toLowerCase();
    final complexKeywords = [
      '页面', '网站', '官网', 'landing', '首页', '主页', '博客', 'blog',
      '多个', '多个section', '布局', 'layout', '完整', '页面结构',
      'hero', 'feature', 'testimonial', 'pricing', 'footer', 'header',
      'portfolio', 'dashboard', '多种', '电商', '商店',
    ];
    final simpleKeywords = [
      '按钮', 'button', '卡片', 'card', '表单', 'form', '输入框', 'input',
      '弹窗', 'modal', '导航栏', 'navbar', '标签', 'badge', '开关', 'toggle',
    ];

    for (final kw in complexKeywords) {
      if (q.contains(kw)) return false;
    }
    for (final kw in simpleKeywords) {
      if (q.contains(kw)) return true;
    }
    return false; // Default to complex (use full pipeline)
  }

  /// 为简单需求构建轻量提示词（单个组件）。
  /// 跳过重量级设计分析，只给 LLM 基本指引。
  String buildCompactPrompt({
    required MatchedDesign design,
    required String userRequirements,
  }) {
    final s = design.stylePreset;
    final buf = StringBuffer();

    buf.writeln('创建一个 UI 元素，不是完整页面，仅组件本身。');
    buf.writeln();
    buf.writeln('风格: ${s.title} — ${s.description}');
    buf.writeln('基础: ${design.baseColor}${design.accentTheme != null ? ' + 强调: ${design.accentTheme}' : ''}');
    buf.writeln('字体: ${design.font}');
    buf.writeln();
    buf.writeln('需求: $userRequirements');
    buf.writeln();
    buf.writeln('规则:');
    buf.writeln('- 仅语义 token (bg-primary, text-foreground, border-border)');
    buf.writeln('- ${s.fontSize} ${s.fontWeight}, ${s.radius}, ${s.focusRing}');
    buf.writeln('- 微妙 hover 过渡 (150-250ms)');
    buf.writeln('- 禁止: 线性渐变, emoji 图标, 过度阴影');
    buf.writeln('- 包含注释: <!-- style:${design.style} base:${design.baseColor} font:${design.font} -->');
    buf.writeln('- 只输出 HTML — 不要 markdown 围栏');

    return buf.toString();
  }
}

// ── Helpers ──
String? _nonEmpty(String s) => s.isNotEmpty ? s : null;
