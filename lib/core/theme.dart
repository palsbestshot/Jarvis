import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Jarvis theme tokens.
///
/// Two palettes live in this class, selected at runtime by `kIsWeb`:
///   * Android / native (Pallav's APK) — the original warm-dark palette
///     (bg #0A0906, text #F5F0E8). Byte-identical to pre-refactor behaviour.
///   * Flutter Web (Rakhi's PWA) — a soft PINK LIGHT palette that pairs
///     with her #D47BA0 accent. Airy, readable on an iPhone in daylight,
///     and deliberately un-Pallav-like so she has her own space.
///
/// Every colour token is exposed as a static getter (not `static const`)
/// so the branch can be decided at runtime without a rebuild. A handful
/// of text-style and icon-colour getters replace what used to be `const`
/// TextStyles — the trade-off is that widgets can no longer be declared
/// `const` when they reference these tokens. Analyzer warnings about
/// `prefer_const_constructors` in places that use JarvisTheme.X are
/// expected and fine.
class JarvisTheme {
  // ── Android (Pallav) — original dark palette ───────────────────────────
  static const Color _pallavBackground = Color(0xFF0A0906);
  static const Color _pallavSurface = Color(0xFF111009);
  static const Color _pallavSurface2 = Color(0xFF181512);
  // Slightly lighter than surface2 — used for Pallav widget internals
  // (mic bg, ring inner), input pill, filter-pill rest state.
  static const Color _pallavSurface3 = Color(0xFF221D17);
  static const Color _pallavTextPrimary = Color(0xFFF5F0E8);
  static const Color _pallavTextSecondary = Color(0xFFA89880);
  static const Color _pallavTextMuted = Color(0xFF6B5C4A);
  static const Color _pallavConfirmText = Color(0xFFFFF5E1);

  // ── Web (Rakhi) — pink light palette ───────────────────────────────────
  // Backgrounds are almost-white with a faint pink wash so large areas
  // don't glare on iPhone. Text is a deep warm plum rather than pure
  // black — softer on her eyes, matches the pink accent family.
  static const Color _rakhiBackground = Color(0xFFFFF5F8); // very pale pink
  static const Color _rakhiSurface = Color(0xFFFFFFFF); // card / sheet
  static const Color _rakhiSurface2 = Color(0xFFFDE8EF); // slightly pinker
  static const Color _rakhiTextPrimary = Color(0xFF2A1A1F); // deep plum
  static const Color _rakhiTextSecondary = Color(0xFF8A6A78); // muted mauve
  static const Color _rakhiTextMuted = Color(0xFFB89CA9); // dusky pink
  static const Color _rakhiConfirmText = Color(0xFF6D2D4C); // deep rose

  // ── Public tokens — branch on platform at read time ────────────────────
  static Color get background =>
      kIsWeb ? _rakhiBackground : _pallavBackground;
  static Color get surface => kIsWeb ? _rakhiSurface : _pallavSurface;
  static Color get surface2 => kIsWeb ? _rakhiSurface2 : _pallavSurface2;
  // surface3 for filter-pill rest state / widget internals; Rakhi side uses
  // a slightly deeper pink than surface2 for the same role.
  static Color get surface3 => kIsWeb ? rakhiSurface3 : _pallavSurface3;
  static Color get textPrimary =>
      kIsWeb ? _rakhiTextPrimary : _pallavTextPrimary;
  static Color get textSecondary =>
      kIsWeb ? _rakhiTextSecondary : _pallavTextSecondary;
  static Color get textMuted => kIsWeb ? _rakhiTextMuted : _pallavTextMuted;
  static Color get confirmText =>
      kIsWeb ? _rakhiConfirmText : _pallavConfirmText;

  // User accents are per-person (not per-platform).
  static const Color pallavAccent = Color(0xFFE8A045);
  static const Color rakhiAccent = Color(0xFFD47BA0);
  // Soft accent washes for pill backgrounds / active-row fills.
  static const Color pallavAccentSoft = Color(0x24E8A045); // ~0.14 alpha
  static const Color pallavAccentBorder = Color(0x66E8A045);
  static const Color rakhiAccentDeep = Color(0xFF6D2D4C);
  static const Color rakhiBg = Color(0xFFFFF5F8);
  static const Color rakhiSurface = Color(0xFFFFFFFF);
  static const Color rakhiSurface2 = Color(0xFFF9D6E2);
  static const Color rakhiSurface3 = Color(0xFFF4C4D4);
  static const Color rakhiTextPrimary = Color(0xFF3A1A2A);
  static const Color rakhiTextSecondary = Color(0xFF8A5670);
  static const Color rakhiTextMuted = Color(0xFFB78CA0);
  static const Color rakhiAccentSoft = Color(0x24D47BA0);

  // ── Typography — getters so the colour follows the palette ─────────────
  //
  // Web font sizes are scaled up ~25% because iPhone Safari renders the
  // PWA on a ~375pt viewport but the app was originally sized for a
  // ~410dp Android phone, plus Rakhi asked for bigger, easier-to-read
  // text. Android sizes unchanged.
  static const double _webFontScale = 1.25;
  static double _s(double base) =>
      kIsWeb ? (base * _webFontScale).roundToDouble() : base;

  static TextStyle get displayLarge => TextStyle(
        fontFamily: 'InstrumentSerif',
        fontSize: _s(32),
        fontWeight: FontWeight.w400,
        color: textPrimary,
      );

  static TextStyle get displayMedium => TextStyle(
        fontFamily: 'InstrumentSerif',
        fontSize: _s(24),
        fontWeight: FontWeight.w400,
        color: textPrimary,
      );

  static TextStyle get headingLarge => TextStyle(
        fontFamily: 'DMSans',
        fontSize: _s(20),
        fontWeight: FontWeight.w600,
        color: textPrimary,
      );

  static TextStyle get headingMedium => TextStyle(
        fontFamily: 'DMSans',
        fontSize: _s(17),
        fontWeight: FontWeight.w600,
        color: textPrimary,
      );

  static TextStyle get bodyLarge => TextStyle(
        fontFamily: 'DMSans',
        fontSize: _s(16),
        fontWeight: FontWeight.w400,
        color: textPrimary,
      );

  static TextStyle get bodyMedium => TextStyle(
        fontFamily: 'DMSans',
        fontSize: _s(14),
        fontWeight: FontWeight.w400,
        color: textPrimary,
      );

  static TextStyle get bodySmall => TextStyle(
        fontFamily: 'DMSans',
        fontSize: _s(12),
        fontWeight: FontWeight.w400,
        color: textPrimary,
      );

  static TextStyle get labelMedium => TextStyle(
        fontFamily: 'DMSans',
        fontSize: _s(13),
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: textPrimary,
      );

  // ── Spacing + radius (unchanged; just const primitives) ────────────────
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  static const double small = 8;
  static const double medium = 16;
  static const double large = 24;
  static const double pill = 50;

  // ── TextTheme + ThemeData ──────────────────────────────────────────────
  static TextTheme get textTheme => TextTheme(
        displayLarge: displayLarge,
        displayMedium: displayMedium,
        headlineLarge: headingLarge,
        headlineMedium: headingMedium,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelMedium: labelMedium,
      );

  /// Root-level text scale multiplier. Applied via MediaQuery.textScaler
  /// at the MaterialApp root so even Material widgets that use their
  /// own default fontSizes (Button, TextField label, Snackbar, etc.)
  /// grow on web without us having to override each one. Also the
  /// knob to tune should Rakhi still find text too small.
  static double get rootTextScale => kIsWeb ? 1.15 : 1.0;

  static ThemeData get themeData {
    if (kIsWeb) {
      // Rakhi's pink-light web theme. Uses rakhiAccent as primary so
      // Material controls (FAB, switches, progress rings, outlined
      // button borders, selection handles) pick up the pink tone
      // without needing per-widget overrides.
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.light(
          primary: rakhiAccent,
          onPrimary: Colors.white,
          secondary: _rakhiTextSecondary,
          onSecondary: Colors.white,
          surface: surface,
          onSurface: textPrimary,
          error: const Color(0xFFB3261E),
          onError: Colors.white,
        ),
        textTheme: textTheme,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: textPrimary),
          titleTextStyle: headingMedium,
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: surface,
          selectedItemColor: rakhiAccent,
          unselectedItemColor: textMuted,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(medium)),
            side: BorderSide(color: _rakhiSurface2, width: 1),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: rakhiAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(medium),
            ),
            padding: const EdgeInsets.symmetric(horizontal: md, vertical: sm),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(medium),
            borderSide: BorderSide(color: _rakhiSurface2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(medium),
            borderSide: BorderSide(color: _rakhiSurface2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(medium),
            borderSide: BorderSide(color: rakhiAccent, width: 1.5),
          ),
          contentPadding: const EdgeInsets.all(md),
          hintStyle: bodyMedium.copyWith(color: textMuted),
        ),
        dividerTheme: DividerThemeData(
          color: _rakhiSurface2,
          thickness: 1,
          space: 1,
        ),
        iconTheme: IconThemeData(color: textSecondary),
      );
    }

    // Pallav's Android — unchanged dark theme.
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.dark(
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
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
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
          padding: const EdgeInsets.symmetric(horizontal: md, vertical: sm),
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
}
