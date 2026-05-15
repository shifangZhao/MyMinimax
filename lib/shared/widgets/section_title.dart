import 'package:flutter/material.dart';
import '../../app/theme.dart';

class SectionTitle extends StatelessWidget {

  const SectionTitle({required this.title, super.key, this.fontSize = 14});
  final String title;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      title,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary,
      ),
    );
  }
}
