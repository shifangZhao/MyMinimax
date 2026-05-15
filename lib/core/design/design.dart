/// Design extraction, analysis, and page generation.
///
/// Flow:
/// 1. [browser_extract_design] → raw design JSON from a reference page
/// 2. [DesignAnalyzer.analyze] → structured [DesignBrief] with Tailwind mappings
/// 3. [PageGenerator.generate] → complete HTML+Tailwind page
/// 4. [browser_load_html] → instant preview
///
/// ```dart
/// final gen = PageGenerator(minimaxClient);
/// final page = await gen.generate(
///   extractionJson: designJson,
///   userRequirements: '个人博客首页',
/// );
/// print(page.html);
/// ```
library;

export 'design_analyzer.dart';
export 'page_generator.dart';
export 'design_system_state.dart';
