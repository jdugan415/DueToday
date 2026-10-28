import 'package:flutter/material.dart';

import 'models/assignment.dart';

const Color _seed = Color(0xFF3949AB);

/// Course badge colors, assigned round-robin as courses are added.
const List<Color> courseColors = [
  Color(0xFF3949AB),
  Color(0xFF00897B),
  Color(0xFFD81B60),
  Color(0xFFF4511E),
  Color(0xFF8E24AA),
  Color(0xFF7CB342),
  Color(0xFF039BE5),
  Color(0xFF6D4C41),
];

Color courseColor(int index) => courseColors[index % courseColors.length];

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    cardTheme: const CardThemeData(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
    ),
  );
}

({Color background, Color foreground, String label}) priorityStyle(
  Priority priority,
  ColorScheme scheme,
) {
  return switch (priority) {
    Priority.high => (
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
        label: 'High',
      ),
    Priority.medium => (
        background: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
        label: 'Medium',
      ),
    Priority.low => (
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
        label: 'Low',
      ),
  };
}
