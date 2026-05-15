import 'package:flutter/material.dart';
import '../../app/theme.dart';

class SettingsWarningCard extends StatelessWidget {

  const SettingsWarningCard({required this.onNavigateToSettings, super.key});
  final VoidCallback onNavigateToSettings;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PixelTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
        border: Border.all(color: PixelTheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: PixelTheme.error, size: 24),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            '请先在设置中配置 API Key',
            style: TextStyle(color: isDark ? Colors.white : PixelTheme.error, fontWeight: FontWeight.w500),
          ),
        ),
        GradientButton(
          onPressed: onNavigateToSettings,
          child: const Text('去设置', style: TextStyle(color: Colors.white, fontSize: 13)),
        ),
      ]),
    );
  }
}
