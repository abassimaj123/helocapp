import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';

class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFF087C7F); // teal (matches app icon, WCAG AA 5.0:1 white text)
  static const Color accent = Color(0xFFF59E0B);
  static const Color secondary = accent;
  static const Color accentGood = Color(0xFF34D399);

  static const Color background = Color(0xFFF8FAFC);
  static const Color success = Color(0xFF34C759);
  static const Color successDark = Color(0xFF15803D); // green.shade700 equiv
  static const Color warning = Color(0xFFFFA500);
  static const Color error = Color(0xFFDC2626); // red 600
  static const Color errorDark = Color(0xFFB91C1C); // red.shade700 equiv
  static const Color infoBlue = Color(0xFF1D4ED8); // blue.shade700 equiv
  static const Color infoBlueDark = Color(0xFF1E3A8A); // blue.shade800 equiv
  static const Color infoBlueLight = Color(0xFF93C5FD); // blue.shade200 equiv
  static const Color labelGray = Color(0xFF64748B);
  static const Color divider = Color(0xFFE2E8F0);

  static ThemeData get light =>
      CalcwiseThemeFactory.buildLight(primary: primary, accent: accent);
  static ThemeData get dark =>
      CalcwiseThemeFactory.buildDark(primary: primary, accent: accent);

  static LinearGradient get primaryGradient => LinearGradient(
        colors: [primary, Color.lerp(primary, Colors.black, 0.15)!],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}
