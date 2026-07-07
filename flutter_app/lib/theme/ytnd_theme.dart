import 'package:flutter/material.dart';

class YtndTheme {
  YtndTheme._();

  static const Color electricCyan = Color(0xFF00D8FF);
  static const Color signalGreen = Color(0xFF55F0A7);
  static const Color warmAmber = Color(0xFFFFB84D);
  static const Color night = Color(0xFF08111F);
  static const Color ink = Color(0xFF101827);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: electricCyan,
      brightness: Brightness.dark,
    ).copyWith(
      primary: electricCyan,
      secondary: signalGreen,
      tertiary: warmAmber,
      surface: const Color(0xFF111A2C),
      surfaceContainerHighest: const Color(0xFF1A263A),
      error: const Color(0xFFFF6B7A),
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: night,
      appBarTheme: const AppBarTheme(
        backgroundColor: night,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: electricCyan,
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFF007E9A),
      secondary: const Color(0xFF047A52),
      tertiary: const Color(0xFF9A6400),
      surface: const Color(0xFFF7FAFD),
      surfaceContainerHighest: const Color(0xFFE8F0F7),
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFFF3F7FB),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF3F7FB),
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

