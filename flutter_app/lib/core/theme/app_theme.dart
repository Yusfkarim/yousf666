import 'package:flutter/material.dart';

import 'clay_widgets.dart';

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Vazirmatn',
      colorScheme: ColorScheme.fromSeed(
        seedColor: ClayColors.orange,
        brightness: brightness,
        primary: ClayColors.orange,
        secondary: ClayColors.green,
        surface: dark ? const Color(0xFF2B211B) : ClayColors.ivory,
      ),
      scaffoldBackgroundColor: dark ? const Color(0xFF211A15) : ClayColors.canvas,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF211A15) : ClayColors.canvas,
        foregroundColor: dark ? const Color(0xFFFFF4E7) : ClayColors.espresso,
        elevation: 0,
        centerTitle: true,
      ),
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: dark ? const Color(0xFFFFF4E7) : ClayColors.espresso,
        displayColor: dark ? const Color(0xFFFFF4E7) : ClayColors.espresso,
        fontFamily: 'Vazirmatn',
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        filled: false,
        hintStyle: TextStyle(color: dark ? const Color(0xFFB7A393) : ClayColors.taupe.withOpacity(.74)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? const Color(0xFF3A2B20) : ClayColors.espresso,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
    return base.copyWith(
      dividerColor: dark ? const Color(0xFF4A392C) : ClayColors.line,
      iconTheme: IconThemeData(color: dark ? const Color(0xFFE9DCCF) : ClayColors.taupe),
    );
  }
}
