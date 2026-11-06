/// Brand colours + Material 3 theme (warm cream, leaf green, soft indigo).
library;

import 'package:flutter/material.dart';

class Brand {
  Brand._();
  static const green = Color(0xFF2E9E57); // leaf green (primary)
  static const greenSoft = Color(0xFFDDF3E4);
  static const indigo = Color(0xFF5B5FD6); // soft indigo (secondary)
  static const indigoSoft = Color(0xFFE6E7FB);
  static const cream = Color(0xFFFFF8EC); // background
  static const paper = Color(0xFFFFFDF7);
  static const ink = Color(0xFF1F2340); // text
  static const sun = Color(0xFFFFC94A);
  static const coral = Color(0xFFFF7A6B);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.green,
    primary: Brand.green,
    secondary: Brand.indigo,
    surface: Brand.paper,
    brightness: Brightness.light,
  );
  // Poppins has Latin + Devanagari; symbols like ₂ and → fall back to Roboto
  // (Android's system font).
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Poppins',
      fontFamilyFallback: const ['Roboto', 'sans-serif']);
  return base.copyWith(
    scaffoldBackgroundColor: Brand.cream,
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.cream,
      foregroundColor: Brand.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w600, color: Brand.ink),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Brand.greenSoft,
      labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w500)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
