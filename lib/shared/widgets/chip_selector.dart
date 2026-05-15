import 'package:flutter/material.dart';
import '../../app/theme.dart';

class ChipOption<T> {

  const ChipOption({required this.value, required this.label, this.description});
  final T value;
  final String label;
  final String? description;
}

class ChipSelector<T> extends StatelessWidget {

  const ChipSelector({
    required this.options, required this.selected, required this.onChanged, super.key,
  });
  final List<ChipOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((option) {
        final isSelected = selected == option.value;
        return GestureDetector(
          onTap: () => onChanged(option.value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: isSelected ? PixelTheme.primaryGradient : null,
              color: isSelected ? null : PixelTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? Colors.transparent : PixelTheme.pixelBorder,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? Colors.white : PixelTheme.textSecondary,
                  ),
                ),
                if (option.description != null && option.description!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    option.description!,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? Colors.white70 : PixelTheme.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
