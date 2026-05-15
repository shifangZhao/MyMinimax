import 'package:flutter/material.dart';
import '../../app/theme.dart';

class ErrorCard extends StatelessWidget {

  const ErrorCard({required this.message, super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PixelTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(PixelTheme.radiusMd),
        border: Border.all(color: PixelTheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, color: PixelTheme.error, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(message, style: TextStyle(color: isDark ? Colors.white : PixelTheme.error, fontSize: 13))),
      ]),
    );
  }
}
