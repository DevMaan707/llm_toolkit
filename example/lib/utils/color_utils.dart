import 'package:flutter/material.dart';

class ColorUtils {
  /// Creates a lighter shade similar to MaterialColor.shade100
  static Color shade100(Color color) {
    return Color.lerp(Colors.white, color, 0.12) ?? color;
  }

  /// Creates a shade similar to MaterialColor.shade300
  static Color shade300(Color color) {
    return Color.lerp(Colors.white, color, 0.4) ?? color;
  }

  /// Creates a shade similar to MaterialColor.shade700
  static Color shade700(Color color) {
    return Color.lerp(Colors.black, color, 0.12) ?? color;
  }

  /// Creates a very light shade similar to MaterialColor.shade25 (custom)
  static Color shade25(Color color) {
    return Color.lerp(Colors.white, color, 0.05) ?? color;
  }

  /// Predefined color palettes for common use cases
  static const Map<String, MaterialColor> formatColors = {
    'GGUF': Colors.green,
    'TFLite': Colors.blue,
    'ONNX': Colors.orange,
    'PyTorch': Colors.red,
  };

  /// Get a MaterialColor for a format
  static MaterialColor getFormatColor(String format) {
    return formatColors[format] ?? Colors.grey;
  }
}
