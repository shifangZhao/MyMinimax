import 'package:flutter/material.dart';
import '../../../../app/theme.dart';

class BrowserToolbar extends StatelessWidget {

  const BrowserToolbar({
    required this.url, required this.isLoading, required this.tabCount, required this.canGoBack, required this.canGoForward, required this.desktopMode, required this.darkMode, required this.onUrlSubmit, required this.onBack, required this.onForward, required this.onReload, required this.onHome, required this.onNewTab, required this.onToggleDesktop, required this.onToggleDarkMode, super.key,
    this.onFindInPage,
  });
  final String url;
  final bool isLoading;
  final int tabCount;
  final bool canGoBack;
  final bool canGoForward;
  final bool desktopMode;
  final bool darkMode;
  final ValueChanged<String> onUrlSubmit;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final VoidCallback onHome;
  final VoidCallback onNewTab;
  final VoidCallback onToggleDesktop;
  final VoidCallback onToggleDarkMode;
  final VoidCallback? onFindInPage;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText;
    final iconColor = isDark ? PixelTheme.darkSecondaryText : PixelTheme.secondaryText;
    final bgColor = isDark ? PixelTheme.darkSurface : PixelTheme.cardBackground;
    final isHttps = url.startsWith('https://');

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: isDark ? PixelTheme.darkBorderSubtle : PixelTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          _NavButton(icon: Icons.arrow_back_ios_new, enabled: canGoBack, onTap: onBack, iconColor: iconColor),
          _NavButton(icon: Icons.arrow_forward_ios, enabled: canGoForward, onTap: onForward, iconColor: iconColor),
          const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              onTap: () => _showUrlDialog(context, isDark),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isDark ? PixelTheme.darkElevated : PixelTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(
                      isLoading ? Icons.refresh : (isHttps ? Icons.lock : Icons.language),
                      size: 14,
                      color: isHttps ? PixelTheme.success : iconColor,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        url.isEmpty ? '输入网址或搜索' : url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: url.isEmpty ? iconColor : textColor),
                      ),
                    ),
                    if (isLoading)
                      const SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: PixelTheme.brandBlue),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          _NavButton(icon: Icons.refresh, enabled: true, onTap: onReload, iconColor: iconColor),
          _NavButton(icon: Icons.home_outlined, enabled: true, onTap: onHome, iconColor: iconColor),
          _NavButton(
            icon: Icons.desktop_windows,
            enabled: true,
            onTap: onToggleDesktop,
            iconColor: desktopMode ? PixelTheme.brandBlue : iconColor,
          ),
          _NavButton(
            icon: Icons.dark_mode,
            enabled: true,
            onTap: onToggleDarkMode,
            iconColor: darkMode ? PixelTheme.warning : iconColor,
          ),
          if (onFindInPage != null)
            _NavButton(icon: Icons.find_in_page, enabled: true, onTap: onFindInPage!, iconColor: iconColor),
          _NavButton(icon: Icons.add, enabled: true, onTap: onNewTab, iconColor: iconColor),
        ],
      ),
    );
  }

  void _showUrlDialog(BuildContext context, bool isDark) {
    final controller = TextEditingController(text: url);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? PixelTheme.darkSurface : PixelTheme.surface,
        title: Text('输入网址', style: TextStyle(color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.primaryText),
          decoration: InputDecoration(
            hintText: 'https://...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onSubmitted: (v) {
            Navigator.pop(ctx);
            onUrlSubmit(v);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onUrlSubmit(controller.text);
            },
            child: const Text('打开'),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.enabled, required this.onTap, required this.iconColor});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Icon(icon, size: 18, color: enabled ? iconColor : iconColor.withValues(alpha: 0.3)),
      ),
    );
  }
}
