import 'package:flutter/material.dart';
import '../../../../app/theme.dart';
import '../../domain/browser_tab.dart';

class BrowserTabBar extends StatelessWidget {

  const BrowserTabBar({
    required this.tabs, required this.activeIndex, required this.onTabSelected, required this.onTabClosed, super.key,
  });
  final List<BrowserTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onTabSelected;
  final ValueChanged<int> onTabClosed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: isDark ? PixelTheme.darkBase : PixelTheme.background,
        border: Border(bottom: BorderSide(color: isDark ? PixelTheme.darkBorderSubtle : PixelTheme.border, width: 0.5)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final isActive = index == activeIndex;
          return GestureDetector(
            onTap: () => onTabSelected(index),
            child: Container(
              width: 130,
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? (isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (tab.isLoading)
                    const SizedBox(
                      width: 10, height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: PixelTheme.brandBlue),
                    )
                  else
                    Icon(Icons.language, size: 12, color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tab.title.isNotEmpty ? tab.title : '新标签页',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                        color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText,
                      ),
                    ),
                  ),
                  if (tabs.length > 1)
                    GestureDetector(
                      onTap: () => onTabClosed(index),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(Icons.close, size: 14, color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
