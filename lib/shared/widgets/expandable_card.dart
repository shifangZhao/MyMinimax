import 'package:flutter/material.dart';
import '../../app/theme.dart';


class ExpandableCard extends StatefulWidget {

  const ExpandableCard({
    required this.header, required this.content, super.key,
    this.expanded = false,
    this.onToggle,
  });
  final Widget header;
  final Widget content;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  State<ExpandableCard> createState() => _ExpandableCardState();
}

class _ExpandableCardState extends State<ExpandableCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.expanded;
  }

  @override
  void didUpdateWidget(ExpandableCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != oldWidget.expanded) {
      _expanded = widget.expanded;
    }
  }

  void _toggle() {
    widget.onToggle?.call();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? PixelTheme.darkBorderSubtle : PixelTheme.pixelBorder;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isDark ? PixelTheme.darkSurface : PixelTheme.surface,
        borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
        border: Border.all(
          color: _expanded ? PixelTheme.primary.withValues(alpha: 0.5) : borderColor,
          width: _expanded ? 1.5 : 1,
        ),
        boxShadow: _expanded
            ? [BoxShadow(color: PixelTheme.primary.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4))]
            : null,
      ),
      child: Column(children: [
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: widget.header),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.keyboard_arrow_down, color: _expanded ? PixelTheme.primary : (isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary)),
              ),
            ]),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: ClipRect(child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: widget.content)),
          crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ]),
    );
  }
}
