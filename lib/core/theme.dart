import 'package:flutter/material.dart';

class JarvisTheme {
  // Colors
  static const Color background = Color(0xFF0A0906);
  static const Color surface = Color(0xFF111009);
  static const Color surface2 = Color(0xFF181512);
  static const Color textPrimary = Color(0xFFF5F0E8);
  static const Color textSecondary = Color(0xFFA89880);
  static const Color textMuted = Color(0xFF6B5C4A);

  // User Accents
  static const Color pallavAccent = Color(0xFFE8A045);
  static const Color rakhiAccent = Color(0xFFD47BA0);

  // Confirmation/status text — readable on dark backgrounds
  static const Color confirmText = Color(0xFFFFF5E1);

  // Typography
  static const TextStyle displayLarge = TextStyle(
    fontFamily: 'InstrumentSerif',
    fontSize: 32,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  static const TextStyle displayMedium = TextStyle(
    fontFamily: 'InstrumentSerif',
    fontSize: 24,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  static const TextStyle headingLarge = TextStyle(
    fontFamily: 'DMSans',
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle headingMedium = TextStyle(
    fontFamily: 'DMSans',
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: 'DMSans',
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: 'DMSans',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: 'DMSans',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  static const TextStyle labelMedium = TextStyle(
    fontFamily: 'DMSans',
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    color: textPrimary,
  );

  // Spacing Scale
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  // Border Radius
  static const double small = 8;
  static const double medium = 16;
  static const double large = 24;
  static const double pill = 50;

  // Text Theme
  static TextTheme get textTheme => const TextTheme(
        displayLarge: displayLarge,
        displayMedium: displayMedium,
        headlineLarge: headingLarge,
        headlineMedium: headingMedium,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelMedium: labelMedium,
      );

  // Theme Data
  static ThemeData get themeData => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          background: background,
          surface: surface,
          primary: textPrimary,
          secondary: textSecondary,
          onBackground: textPrimary,
          onSurface: textPrimary,
        ),
        textTheme: textTheme,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: surface,
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(medium)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: surface2,
            foregroundColor: textPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(medium),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: md,
              vertical: sm,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(medium),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.all(md),
        ),
      );
}