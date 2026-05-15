import 'package:flutter/material.dart';
import '../../app/theme.dart';

class GenerateButton extends StatelessWidget {

  const GenerateButton({
    required this.label, required this.icon, super.key,
    this.onPressed,
    this.isLoading = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: GradientButton(
        onPressed: isLoading ? null : onPressed,
        isLoading: isLoading,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(
              isLoading ? '生成中...' : label,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
