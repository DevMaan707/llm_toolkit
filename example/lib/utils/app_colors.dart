import 'package:flutter/material.dart';

class AppColors {
  // Custom shade25 equivalent colors
  static Color shade25(MaterialColor color) {
    // Create a lighter version of shade50
    return Color.lerp(Colors.white, color.shade50, 0.5) ?? color.shade50;
  }

  // Pre-defined light colors for common use
  static const Color blueLight = Color(0xFFF0F7FF);
  static const Color greenLight = Color(0xFFF0FDF4);
  static const Color greyLight = Color(0xFFFAFAFA);
  static const Color orangeLight = Color(0xFFFFF7ED);
  static const Color purpleLight = Color(0xFFFAF5FF);
}
