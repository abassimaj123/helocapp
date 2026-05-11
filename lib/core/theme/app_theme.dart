import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';

class AppTheme {
  AppTheme._();

  static const Color primary    = Color(0xFF00695C); // Teal 700
  static const Color accent     = Color(0xFFF59E0B);

  static const Color background = Color(0xFFF8FAFC);
  static const Color cardWhite  = Colors.white;
  static const Color success    = Color(0xFF34C759);
  static const Color warning    = Color(0xFFFFA500);
  static const Color labelGray  = Color(0xFF64748B);
  static const Color divider    = Color(0xFFE2E8F0);

  static ThemeData get theme => CalcwiseThemeFactory.buildLight(primary: primary, accent: accent);
  static ThemeData get dark  => CalcwiseThemeFactory.buildDark(primary: primary, accent: accent);

  static LinearGradient get primaryGradient => LinearGradient(
    colors: [primary, Color.lerp(primary, Colors.black, 0.15)!],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
