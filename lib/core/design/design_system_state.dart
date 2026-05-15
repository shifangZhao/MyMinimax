import 'dart:convert';
import 'dart:io';
import 'design_analyzer.dart';

/// Persistent design system state across page generations.
///
/// When the user builds multiple pages in one session, this ensures
/// consistent design tokens (style, colors, fonts) carry over.
class DesignSystemState {
  DesignSystemState._();
  static final DesignSystemState instance = DesignSystemState._();

  MatchedDesign? _current;
  final List<MatchedDesign> _history = [];
  static const _maxHistory = 20;

  /// Current active design system (null if none set).
  MatchedDesign? get current => _current;
  bool get hasActiveDesign => _current != null;
  List<MatchedDesign> get history => List.unmodifiable(_history);

  /// Set the active design from a newly generated page.
  void commit(MatchedDesign design) {
    _current = design;
    _history.add(design);
    if (_history.length > _maxHistory) _history.removeAt(0);
  }

  /// Clear the active design (user wants a fresh start).
  void reset() {
    _current = null;
  }

  /// Build a prompt snippet telling the LLM what design system is active.
  String get promptContext {
    if (_current == null) return '';
    final d = _current!;
    final s = d.stylePreset;
    return '''
## Active Design System (from previous page)
The user has already established a design system. You MUST use the same core tokens:
- Style: ${s.title} (${d.style}) — ${s.description}
- Base color: ${d.baseColor}${d.accentTheme != null ? ' + accent: ${d.accentTheme}' : ''}
- Font: ${d.font}
- Radius strategy: ${s.radius}, cards: ${s.cardRadius}
- Shadow depth: ${s.cardShadow}
- Input style: ${s.inputStyle}

Consistency rules:
1. Use the SAME style, baseColor, accentTheme, and font as above
2. Use the SAME component classes (button variants, card patterns)
3. The CSS token block is identical — do not redefine variables
4. You MAY vary the LAYOUT and CONTENT, but the visual LANGUAGE must be consistent
5. Include this comment: <!-- style:${d.style} base:${d.baseColor}${d.accentTheme != null ? ' accent:${d.accentTheme}' : ''} font:${d.font} -->
''';
  }

  /// Serialize to JSON for disk persistence.
  Map<String, dynamic> toJson() => {
        if (_current != null) 'current': _designToJson(_current!),
        'history': _history.map(_designToJson).toList(),
      };

  Map<String, dynamic> _designToJson(MatchedDesign d) => {
        'style': d.style,
        'baseColor': d.baseColor,
        if (d.accentTheme != null) 'accentTheme': d.accentTheme,
        'font': d.font,
        if (d.fontHeading != null) 'fontHeading': d.fontHeading,
      };

  /// Save to file in workspace.
  Future<void> saveToFile(String workspaceDir) async {
    final dir = Directory('$workspaceDir/.my_minimax');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/design_system.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()));
  }

  /// Load from file in workspace.
  Future<bool> loadFromFile(String workspaceDir) async {
    final file = File('$workspaceDir/.my_minimax/design_system.json');
    if (!await file.exists()) return false;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (json['current'] != null) {
        _current = _designFromJson(json['current'] as Map<String, dynamic>);
      }
      if (json['history'] != null) {
        _history.clear();
        for (final h in json['history'] as List<dynamic>) {
          _history.add(_designFromJson(h as Map<String, dynamic>));
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  MatchedDesign _designFromJson(Map<String, dynamic> j) => MatchedDesign(
        style: j['style'] as String? ?? 'vega',
        baseColor: j['baseColor'] as String? ?? 'neutral',
        accentTheme: j['accentTheme'] as String?,
        font: j['font'] as String? ?? 'inter',
        fontHeading: j['fontHeading'] as String?,
      );
}
