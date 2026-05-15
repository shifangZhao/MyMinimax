import 'package:flutter/material.dart';
import '../../app/theme.dart';

class PageHeader extends StatelessWidget {

  const PageHeader({
    required this.icon, required this.title, super.key,
    this.showDivider = false,
  });
  final IconData icon;
  final String title;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final dividerColor = PixelTheme.dividerFor(isDark);

    return Column(
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            const SizedBox(width: 40),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: textColor),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 40),
          ]),
        ),
        if (showDivider)
          Divider(height: 0.5, thickness: 0.5, color: dividerColor),
      ],
    );
  }
}
