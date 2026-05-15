import 'package:flutter/material.dart';
import '../../app/theme.dart';

class PixelAppBar extends StatelessWidget implements PreferredSizeWidget {

  const PixelAppBar({
    required this.title, super.key,
    this.actions,
    this.leading,
  });
  final String title;
  final List<Widget>? actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? PixelTheme.darkBase : PixelTheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark ? PixelTheme.darkBorderSubtle : Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              if (leading != null) leading!,
              if (leading == null && Navigator.canPop(context))
                IconButton(
                  icon: Icon(Icons.arrow_back, color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              Expanded(
                child: Center(
                  child: title.isNotEmpty
                      ? Text(
                          title,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              if (actions != null) ...actions!,
            ],
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}
