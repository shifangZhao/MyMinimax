import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../shared/utils/responsive.dart';

class PixelTheme {
  // Light mode
  static const Color primary = Color(0xFF4F6EF7);
  static const Color primaryDark = Color(0xFF3B5DE7);
  static const Color secondary = Color(0xFF8b5cf6);
  static const Color accent = Color(0xFF06b6d4);
  static const Color background = Color(0xFFF2F3F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF0F0F0);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color primaryText = Color(0xFF1A1A1A);
  static const Color textPrimary = primaryText;  // Alias for compatibility
  static const Color secondaryText = Color(0xFF6B7280);
  static const Color textSecondary = secondaryText;  // Alias for compatibility
  static const Color border = pixelBorder;  // Alias for compatibility
  static const double radiusSmall = 8.0;  // Alias for compatibility
  static const List<BoxShadow> glowShadow = [
    BoxShadow(color: Color(0x404F6EF7), blurRadius: 20, offset: Offset(0, 4)),
  ];  // Alias for compatibility
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF06b6d4), Color(0xFF0891b2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );  // Alias for compatibility
  static const Color textMuted = Color(0xFF9CA3AF);
  static const Color brandBlue = Color(0xFF4F6EF7);
  static const Color codeBlockBg = Color(0xFFF8F9FA);
  static const Color pixelBorder = Color(0xFFE5E7EB);
  static const Color userBubble = Color(0xFF7C3AED);  // 紫罗兰色，与助手气泡区分
  static const Color userBubbleText = Color(0xFFFFFFFF);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);

  // Dark mode — 蓝紫底色，拉大层级差距，避免纯灰反转
  // Background层级（从深到浅，差距明显可辨）
  static const Color darkBase = Color(0xFF0B0B14);       // bg-base: 页面底层（深蓝黑）
  static const Color darkSurface = Color(0xFF151524);     // bg-surface: 卡片、面板（蓝调）
  static const Color darkElevated = Color(0xFF212139);    // bg-elevated: 下拉菜单、浮层
  static const Color darkHighElevated = Color(0xFF2D2D4F); // bg-input: 输入框、对话框
  static const Color darkSurfaceHighest = Color(0xFF3A3A5C);
  static const Color darkBackground = darkBase;
  static const Color darkCard = darkSurface;

  // 文字层级 — 暖灰白，确保在深色背景上清晰可读
  static const Color darkPrimaryText = Color(0xFFF0F0F6);  // text-primary: 主标题（近乎白）
  static const Color darkSecondaryText = Color(0xFFD0D0DE); // text-secondary: 正文
  static const Color darkTextMuted = Color(0xFFA0A0B8);    // text-tertiary: 辅助文字（提高对比度）
  static const Color darkTextDisabled = Color(0xFF6A6A82); // text-disabled: 禁用状态

  // 边框与分隔 — 清晰可辨的层级
  static const Color darkBorderSubtle = Color(0xFF212139);   // border-subtle: 卡片边框（同elevated）
  static const Color darkBorderDefault = Color(0xFF38385A); // border-default: 输入框边框
  static const Color darkBorderStrong = Color(0xFF52527A);  // border-strong: 焦点状态
  static const Color darkBorder = Color(0x24FFFFFF);        // 兼容旧代码
  static const Color darkDivider = Color(0xFF2A2A2A);   // divider: 深色分割线（实色）
  static const Color lightDivider = Color(0xFFE8E8E8);  // divider: 浅色分割线（实色）

  // Dark mode primary — 降低饱和度，更柔和
  static const Color darkPrimary = Color(0xFF7B92F5);
  static const Color darkSecondary = Color(0xFFA78BFA);
  static const Color darkAccent = Color(0xFF2DD4BF);
  static const Color darkCodeBlockBg = Color(0xFF111128); // 代码块背景（比base略亮，有层次）

  // 根据主题亮度自动选择颜色
  static Color textPrimaryFor(bool isDark) => isDark ? darkPrimaryText : textPrimary;
  static Color textSecondaryFor(bool isDark) => isDark ? darkSecondaryText : textSecondary;
  static Color textMutedFor(bool isDark) => isDark ? darkTextMuted : textMuted;
  static Color surfaceVariantFor(bool isDark) => isDark ? darkElevated : surfaceVariant;
  static Color surfaceFor(bool isDark) => isDark ? darkSurface : surface;
  static Color borderFor(bool isDark) => isDark ? darkBorderDefault : pixelBorder;
  static Color borderSubtleFor(bool isDark) => isDark ? darkBorderSubtle : pixelBorder;
  static Color primaryFor(bool isDark) => isDark ? darkPrimary : primary;
  static Color bgFor(bool isDark) => isDark ? darkBase : background;
  static Color dividerFor(bool isDark) => isDark ? darkDivider : lightDivider;

  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusLarge = 24.0;
  static const double radiusCode = 12.0;
  static const double radiusCard = 16.0;

  // ── Markdown typography ──
  static const String mdFontFamily = 'monospace';
  static const double mdH1FontSize = 22.0;
  static const double mdH2FontSize = 18.0;
  static const double mdH3FontSize = 16.0;
  static const double mdH4FontSize = 14.0;
  static const double mdBodyFontSize = 14.0;
  static const double mdHeadingLineHeight = 1.3;
  static const double mdLineHeight = 1.5;
  static Color mdH1ColorFor(bool isDark) => isDark ? darkPrimaryText : primaryText;
  static Color mdH2ColorFor(bool isDark) => isDark ? Color(0xFFE0E0EE) : Color(0xFF2D2D3A);
  static Color mdH3ColorFor(bool isDark) => isDark ? Color(0xFFC8C8DA) : Color(0xFF4A4A5A);
  static Color mdQuoteBgFor(bool isDark) => isDark ? const Color(0x14FFFFFF) : const Color(0x08000000);
  static Color mdQuoteBorderFor(bool isDark) => isDark ? const Color(0x40FFFFFF) : const Color(0x40000000);
  static Color mdCodeBgFor(bool isDark) => isDark ? darkCodeBlockBg : codeBlockBg;
  static Color mdCodeBorderFor(bool isDark) => isDark ? darkBorderSubtle : pixelBorder;
  static Color mdHrFor(bool isDark) => isDark ? const Color(0x20FFFFFF) : const Color(0x20000000);
  static Color mdTableBorderFor(bool isDark) => isDark ? const Color(0x24FFFFFF) : const Color(0x24000000);
  static Color mdTableHeadBgFor(bool isDark) => isDark ? const Color(0x10FFFFFF) : const Color(0x08000000);
  static Color mdListBulletFor(bool isDark) => isDark ? Color(0xFFA0A0B8) : Color(0xFF6B7280);
  static const double mdLetterSpacing = 0.2;
  static const double mdCodeFontSize = 13.0;
  static const double mdCodeLineHeight = 1.5;
  static const double mdTableBorderWidth = 0.5;
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 20, offset: Offset(0, 4)),
  ];
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF4F6EF7), Color(0xFF764ba2)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  static const LinearGradient darkPrimaryGradient = LinearGradient(
    colors: [Color(0xFF9B8AFA), Color(0xFF8B5CF6)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  static const LinearGradient lightGradient = LinearGradient(
    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const BorderRadius userBubbleRadius = BorderRadius.only(
    topLeft: Radius.circular(18),
    topRight: Radius.circular(18),
    bottomLeft: Radius.circular(18),
    bottomRight: Radius.circular(4),
  );
  static const BorderRadius assistantBubbleRadius = BorderRadius.only(
    topLeft: Radius.circular(18),
    topRight: Radius.circular(18),
    bottomLeft: Radius.circular(4),
    bottomRight: Radius.circular(18),
  );
  static ThemeData get lightTheme => ThemeData(
    brightness: Brightness.light,
    primaryColor: primary,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.light(
      primary: primary,
      secondary: primaryDark,
      surface: surface,
      surfaceContainerLow: surface,
      surfaceContainer: surfaceVariant,
      surfaceContainerHigh: Color(0xFFE8E8E8),
      surfaceContainerHighest: Color(0xFFDEDEDE),
      outline: pixelBorder,
    ),
    appBarTheme: const AppBarTheme(backgroundColor: background, elevation: 0, surfaceTintColor: Colors.transparent),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusCard),
        side: const BorderSide(color: pixelBorder, width: 0.5),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: pixelBorder,
      thickness: 0.5,
    ),
  );

  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    primaryColor: darkPrimary,
    scaffoldBackgroundColor: darkBase,
    colorScheme: const ColorScheme.dark(
      primary: darkPrimary,
      secondary: darkSecondary,
      surface: darkSurface,
      surfaceContainerLow: darkBase,
      surfaceContainer: darkSurface,
      surfaceContainerHigh: darkElevated,
      surfaceContainerHighest: darkHighElevated,
      outline: darkBorderDefault,
      outlineVariant: darkBorderSubtle,
    ),
    appBarTheme: const AppBarTheme(backgroundColor: darkBase, elevation: 0, surfaceTintColor: Colors.transparent),
    cardTheme: CardThemeData(
      elevation: 0,
      color: darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusCard),
        side: const BorderSide(color: darkBorderSubtle, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkHighElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: darkBorderDefault, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: darkPrimary, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: darkBorderDefault, width: 1),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: darkBorderSubtle,
      thickness: 0.5,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: darkPrimaryText),
      bodyMedium: TextStyle(color: darkSecondaryText),
      bodySmall: TextStyle(color: darkTextMuted),
    ),
    iconTheme: const IconThemeData(color: darkSecondaryText),
  );
}

class PixelNavBar extends StatefulWidget {

  const PixelNavBar({
    required this.currentIndex, required this.onTap, super.key,
    this.showSettings = true,
    this.showMap = true,
    this.labels = defaultLabels,
  });
  final int currentIndex;
  final Function(int) onTap;
  final bool showSettings;
  final bool showMap;
  final List<String> labels;

  static const defaultLabels = ['对话', '笔记', '地图', '创作', '设置'];

  @override
  State<PixelNavBar> createState() => _PixelNavBarState();
}

class _PixelNavBarState extends State<PixelNavBar> with TickerProviderStateMixin {
  final Map<int, AnimationController> _controllers = {};
  final Map<int, Animation<double>> _bounceAnimations = {};
  int? _pressedIndex;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < widget.labels.length; i++) {
      _controllers[i] = AnimationController(
        duration: const Duration(milliseconds: 400),
        vsync: this,
      );
      _bounceAnimations[i] = Tween<double>(begin: 1.0, end: 1.2).animate(
        CurvedAnimation(parent: _controllers[i]!, curve: Curves.elasticOut),
      );
    }
  }

  @override
  void didUpdateWidget(PixelNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _controllers[widget.currentIndex]?.forward(from: 0);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = ResponsiveHelper.navIconSize(context);
    final hPadding = ResponsiveHelper.navPaddingHorizontal(context);
    final vPadding = ResponsiveHelper.navPaddingVertical(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? PixelTheme.darkSurface : PixelTheme.cardBackground,
        border: isDark ? const Border(
          top: BorderSide(color: PixelTheme.darkBorderSubtle, width: 1),
        ) : null,
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.chat_bubble_outline, widget.labels[0], iconSize, isDark),
              if (widget.showMap) _buildNavItem(1, Icons.map_outlined, widget.labels[1], iconSize, isDark),
              _buildNavItem(2, Icons.auto_awesome_outlined, widget.labels[2], iconSize, isDark),
              if (widget.showSettings) _buildNavItem(3, Icons.settings_outlined, widget.labels[3], iconSize, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, double iconSize, bool isDark) {
    final isSelected = widget.currentIndex == index;
    final isPressed = _pressedIndex == index;
    final hPadding = ResponsiveHelper.navItemPaddingHorizontal(context);
    final vPadding = ResponsiveHelper.navItemPaddingVertical(context);
    final fontSize = ResponsiveHelper.navLabelSize(context);

    final bounceAnimation = _bounceAnimations[index]!;
    final highlightColor = isDark ? PixelTheme.darkPrimary : PixelTheme.primary;
    final defaultColor = isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted;
    final iconColor = (isSelected || isPressed) ? highlightColor : defaultColor;

    final itemCount = 3 + (widget.showMap ? 1 : 0) + (widget.showSettings ? 1 : 0);
    final maxItemWidth = (MediaQuery.of(context).size.width - hPadding * 2) / itemCount - 8;

    return GestureDetector(
      onTap: () {
        if (widget.currentIndex != index) {
          _controllers[index]?.forward(from: 0);
        }
        widget.onTap(index);
      },
      onTapDown: (_) => setState(() => _pressedIndex = index),
      onTapUp: (_) => setState(() => _pressedIndex = null),
      onTapCancel: () => setState(() => _pressedIndex = null),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: maxItemWidth,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: bounceAnimation,
                builder: (context, child) {
                  final scale = isSelected ? bounceAnimation.value : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        icon,
                        key: ValueKey(isSelected),
                        color: iconColor,
                        size: iconSize,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: fontSize,
                  color: iconColor,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class PixelCard extends StatelessWidget {

  const PixelCard({required this.child, super.key, this.padding, this.margin, this.onTap, this.isDark = false});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? PixelTheme.darkSurface
            : (isDarkMode ? PixelTheme.darkSurface : PixelTheme.cardBackground),
        borderRadius: BorderRadius.circular(PixelTheme.radiusCard),
        border: isDark ? Border.all(color: PixelTheme.darkBorderSubtle, width: 1) : null,
        boxShadow: isDark ? null : PixelTheme.cardShadow,
      ),
      child: onTap != null ? GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: child) : child,
    );
  }
}

class GradientButton extends StatelessWidget {

  const GradientButton({required this.onPressed, required this.child, super.key, this.isLoading = false});
  final VoidCallback? onPressed;
  final Widget child;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          gradient: isDark ? PixelTheme.darkPrimaryGradient : PixelTheme.primaryGradient,
          borderRadius: BorderRadius.circular(PixelTheme.radiusSmall),
          boxShadow: isDark ? null : [
            BoxShadow(color: PixelTheme.brandBlue.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: isLoading
          ? const SizedBox(width: 24, height: 24, child: CometLoader())
          : child,
      ),
    );
  }
}

class CometLoader extends StatefulWidget {
  const CometLoader({super.key});

  @override
  State<CometLoader> createState() => _CometLoaderState();
}

class _CometLoaderState extends State<CometLoader> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this)..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: CometPainter(progress: _controller.value),
          size: const Size(24, 24),
        );
      },
    );
  }
}

class CometPainter extends CustomPainter {

  CometPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radiusX = size.width / 2 - 2;
    final radiusY = size.height / 2 - 1;

    final angle = progress * 2 * math.pi;
    final x = centerX + radiusX * math.cos(angle);
    final y = centerY + radiusY * math.sin(angle);

    final trailPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const trailLength = 1.2;
    for (var i = 0; i < 20; i++) {
      final t = i / 20;
      final trailAngle = angle - t * trailLength;
      final tx = centerX + radiusX * math.cos(trailAngle);
      final ty = centerY + radiusY * math.sin(trailAngle);
      trailPaint.color = Colors.white.withValues(alpha: (1 - t) * 0.8);
      canvas.drawCircle(Offset(tx, ty), 1.5 - t * 0.8, trailPaint);
    }

    final cometPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), 3, cometPaint);

    final glowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(x, y), 4, glowPaint);
  }

  @override
  bool shouldRepaint(covariant CometPainter oldDelegate) => oldDelegate.progress != progress;
}

class ModernCard extends StatelessWidget {

  const ModernCard({
    required this.child, super.key,
    this.padding,
    this.margin,
    this.onTap,
    this.isDark = false,
  });
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final useDark = isDark || isDarkMode;
    return Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: useDark ? PixelTheme.darkSurface : PixelTheme.cardBackground,
        borderRadius: BorderRadius.circular(PixelTheme.radiusCard),
        border: useDark ? Border.all(color: PixelTheme.darkBorderSubtle, width: 1) : null,
        boxShadow: useDark ? null : PixelTheme.cardShadow,
      ),
      child: onTap != null
          ? GestureDetector(onTap: onTap, child: child)
          : child,
    );
  }
}

class GlassContainer extends StatelessWidget {

  const GlassContainer({
    required this.child, super.key,
    this.padding,
    this.margin,
    this.borderRadius = 16,
  });
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? PixelTheme.darkSurface
            : PixelTheme.cardBackground,
        borderRadius: BorderRadius.circular(borderRadius),
        border: isDark
            ? Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1)
            : null,
        boxShadow: isDark ? null : PixelTheme.cardShadow,
      ),
      child: child,
    );
  }
}
