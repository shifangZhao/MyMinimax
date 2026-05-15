import 'package:flutter/material.dart';
import '../../app/theme.dart';

class ModelDropdown extends StatelessWidget {

  const ModelDropdown({
    required this.label, required this.selectedModel, required this.models, required this.onChanged, super.key,
    this.modelDescriptions,
  });
  final String label;
  final String selectedModel;
  final List<String> models;
  final Map<String, String>? modelDescriptions;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final desc = modelDescriptions?[selectedModel];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)),
        const SizedBox(height: 8),
        PopupMenuButton<String>(
          offset: const Offset(0, 48),
          padding: EdgeInsets.zero,
          color: isDark ? PixelTheme.darkElevated : PixelTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          constraints: const BoxConstraints(minWidth: double.infinity),
          onSelected: onChanged,
          itemBuilder: (context) => models.map((m) => PopupMenuItem<String>(
            value: m,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              if (m == selectedModel)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(Icons.check, size: 18, color: isDark ? PixelTheme.darkPrimary : PixelTheme.primary),
                )
              else
                const SizedBox(width: 28),
              Expanded(child: Text(m, style: TextStyle(fontSize: 14, fontWeight: m == selectedModel ? FontWeight.w600 : FontWeight.normal, color: m == selectedModel ? (isDark ? PixelTheme.darkPrimary : PixelTheme.primary) : (isDark ? PixelTheme.darkPrimaryText : PixelTheme.textPrimary)))),
            ]),
          )).toList(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? PixelTheme.darkBorderDefault : PixelTheme.pixelBorder),
            ),
            child: Row(children: [
              Expanded(
                child: Text(selectedModel, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? PixelTheme.darkPrimary : PixelTheme.primary)),
              ),
              Icon(Icons.keyboard_arrow_down, size: 20, color: isDark ? PixelTheme.darkSecondaryText : PixelTheme.textSecondary),
            ]),
          ),
        ),
        if (desc != null) ...[
          const SizedBox(height: 4),
          Text(desc, style: TextStyle(fontSize: 11, color: isDark ? PixelTheme.darkTextMuted : PixelTheme.textMuted)),
        ],
      ],
    );
  }
}
