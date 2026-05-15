import 'package:flutter/material.dart';
import '../../app/theme.dart';

/// Top bar icon button (back, close, etc.).
/// On press: icon color highlights, no background fill/shadow.
class PixelTopBarButton extends StatefulWidget {

  const PixelTopBarButton({
    required this.icon, required this.onTap, required this.iconColor, super.key,
  });
  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  State<PixelTopBarButton> createState() => _PixelTopBarButtonState();
}

class _PixelTopBarButtonState extends State<PixelTopBarButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlightColor = isDark ? PixelTheme.darkPrimary : PixelTheme.primary;

    return InkWell(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      borderRadius: BorderRadius.circular(20),
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        child: Icon(
          widget.icon,
          size: 22,
          color: _isPressed ? highlightColor : widget.iconColor,
        ),
      ),
    );
  }
}

/// Menu item with icon + text.
/// On press: icon and text color highlight, no background fill/shadow.
class PixelMenuItem extends StatefulWidget {

  const PixelMenuItem({
    required this.icon, required this.label, required this.onTap, super.key,
    this.compact = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  State<PixelMenuItem> createState() => _PixelMenuItemState();
}

class _PixelMenuItemState extends State<PixelMenuItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultIconColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary;
    final defaultTextColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary;
    final highlightColor = isDark ? PixelTheme.darkPrimary : PixelTheme.primary;
    final horizontalPadding = widget.compact ? 8.0 : 16.0;
    final verticalPadding = widget.compact ? 10.0 : 12.0;

    return InkWell(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      borderRadius: BorderRadius.circular(12),
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        child: Row(
          children: [
            Icon(
              widget.icon,
              size: widget.compact ? 18 : 20,
              color: _isPressed ? highlightColor : defaultIconColor,
            ),
            SizedBox(width: widget.compact ? 8 : 12),
            Text(
              widget.label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: widget.compact ? 13 : 14,
                color: _isPressed ? highlightColor : defaultTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
