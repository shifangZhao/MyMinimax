import 'package:flutter/material.dart';
import '../../app/theme.dart';

void showSnackBar(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: isError ? PixelTheme.error : PixelTheme.textPrimary,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PixelTheme.radiusSm)),
  ));
}
