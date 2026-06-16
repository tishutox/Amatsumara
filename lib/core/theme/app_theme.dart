import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    const circusRed = Color(0xFFEF372C);
    const circusBlue = Color(0xFF5860C3);

    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: circusRed,
        onPrimary: Colors.white,
        secondary: circusBlue,
        onSecondary: Colors.white,
        surface: Colors.white,
        onSurface: Color(0xFF231F20),
      ),
      scaffoldBackgroundColor: const Color(0xFFFFF9F9),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: Color(0xFFFFFFFF),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFF0E8E8)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
