import 'package:flutter/material.dart';

abstract final class ClubColors {
  static const lime = Color(0xFFD4FF00);
  static const olive = Color(0xFF5E7000);
  static const lightBackground = Color(0xFFF8F9FA);
  static const darkBackground = Color(0xFF08090B);
  static const darkSurface = Color(0xFF151619);
  static const danger = Color(0xFFFF4D57);
}

abstract final class ClubTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final background = isDark
        ? ClubColors.darkBackground
        : ClubColors.lightBackground;
    final surface = isDark ? ClubColors.darkSurface : Colors.white;
    final foreground = isDark
        ? const Color(0xFFF4F5F6)
        : const Color(0xFF111318);
    final muted = isDark ? const Color(0xFF96989D) : const Color(0xFF777B83);
    final outline = isDark ? const Color(0xFF303237) : const Color(0xFFD9DCE1);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: ClubColors.lime,
        onPrimary: Colors.black,
        secondary: ClubColors.olive,
        onSecondary: Colors.white,
        error: ClubColors.danger,
        onError: Colors.white,
        surface: surface,
        onSurface: foreground,
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          height: 1,
          fontWeight: FontWeight.w900,
          color: foreground,
        ),
        headlineMedium: TextStyle(
          fontSize: 26,
          height: 1.04,
          fontWeight: FontWeight.w900,
          color: foreground,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
        bodyLarge: TextStyle(fontSize: 15, color: foreground),
        bodyMedium: TextStyle(fontSize: 13, color: foreground),
        bodySmall: TextStyle(fontSize: 11, color: muted),
        labelLarge: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 14,
        ),
        hintStyle: TextStyle(color: muted),
        labelStyle: TextStyle(color: muted, fontSize: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ClubColors.lime, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ClubColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ClubColors.danger, width: 1.5),
        ),
      ),
      dividerColor: outline,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        centerTitle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFF292B30)
            : const Color(0xFF202226),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }
}
