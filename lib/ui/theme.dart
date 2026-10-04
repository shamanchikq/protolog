import 'package:flutter/material.dart';

/// "Lab Sheet" design tokens. Dark theme only for v1.
class AppTheme {
  AppTheme._();

  static const bg = Color(0xFF0B0C0E);
  static const surface = Color(0xFF13151A);
  static const surface2 = Color(0xFF191C22);
  static const paper = Color(0xFFF2E8D2);
  static const paperInk = Color(0xFF1A1612);
  static const border = Color(0xFF23272F);
  static const borderSoft = Color(0xFF1B1E25);
  static const fg = Color(0xFFECECEC);
  static const fgMute = Color(0xFF9AA0A8);

  /// Decorative dim: borders, dividers, chevrons, disabled controls. Too
  /// faint for text (~2.8–3.2:1 on the dark surfaces) — use [fgDimText].
  static const fgDim = Color(0xFF5C626C);

  /// The dimmest readable text: ≥ 4.5:1 (WCAG AA) on [bg], [surface] and
  /// [surface2] — microlabels, hints, chart ticks, empty states (C3).
  static const fgDimText = Color(0xFF80868F);
  static const accent = Color(0xFF7DD3D0);
  static const accentDeep = Color(0xFF3A6F6D);
  static const warm = Color(0xFFE0B870);
  static const warn = Color(0xFFD27A6B);

  /// Secondary ink on [paper] (≈ [paperInk] at 65 %), ≥ 4.5:1 — small labels
  /// and units on the LoadHero (C3).
  static const paperInkMute = Color(0xFF665F55);

  /// [warn] darkened (same hue) to ≥ 4.5:1 on [paper], for the LoadHero's
  /// falling-trend arrow (C3).
  static const warnOnPaper = Color(0xFFAC4634);

  // Per-compound redesign colors. Keyed by base name (case-insensitive lookup).
  // Returns null when the base name isn't in the override list — callers
  // should fall back to the compound's own colorValue.
  static const _baseColorOverrides = <String, Color>{
    'testosterone': Color(0xFF5DC59C),
    'sustanon': Color(0xFF5DC59C),
    'masteron': Color(0xFFE0B870),
    'drostanolone': Color(0xFFE0B870),
    'primobolan': Color(0xFF5FA8E0),
    'methenolone': Color(0xFF5FA8E0),
    'trenbolone': Color(0xFFD27A6B),
    'nandrolone': Color(0xFF87BFE0),
    'boldenone': Color(0xFFB5A8E0),
    'dhb': Color(0xFF87BFE0),
    'oxandrolone': Color(0xFFC9B062),
    'anavar': Color(0xFFC9B062),
    'oxymetholone': Color(0xFFC9B062),
    'anadrol': Color(0xFFC9B062),
    'stanozolol': Color(0xFFC9B062),
    'winstrol': Color(0xFFC9B062),
    'dianabol': Color(0xFFC9B062),
    'methandrostenolone': Color(0xFFC9B062),
    'hcg': Color(0xFF8FC5A8),
    'semaglutide': Color(0xFF7DD3D0),
    'tirzepatide': Color(0xFF7DD3D0),
    'bpc-157': Color(0xFF8FC5A8),
    'bpc157': Color(0xFF8FC5A8),
    'ipamorelin': Color(0xFFD27A6B),
    'cjc-1295': Color(0xFFB5A8E0),
    'anastrozole': Color(0xFFD27A6B),
    'arimidex': Color(0xFFD27A6B),
    'exemestane': Color(0xFFD27A6B),
    'aromasin': Color(0xFFD27A6B),
  };

  /// The app's MaterialApp theme. Every ColorScheme slot pickers reach for
  /// is filled — ColorScheme.dark() defaults secondary/containers to
  /// Material teal (#03DAC6), which leaked an "emerald" look into date/time
  /// pickers.
  static final ThemeData materialTheme = ThemeData.dark().copyWith(
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      onPrimary: bg,
      secondary: accent,
      onSecondary: bg,
      primaryContainer: accentDeep,
      onPrimaryContainer: fg,
      secondaryContainer: surface2,
      onSecondaryContainer: fg,
      surface: surface,
      onSurface: fg,
      onSurfaceVariant: fgMute,
      outline: border,
    ),
    datePickerTheme: const DatePickerThemeData(
      backgroundColor: surface2,
      headerBackgroundColor: surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border, width: 1),
      ),
    ),
    timePickerTheme: const TimePickerThemeData(
      backgroundColor: surface2,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border, width: 1),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: surface2,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border, width: 1),
      ),
    ),
    cardTheme: const CardThemeData(
      color: surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
  );

  static final _whitespace = RegExp(r'\s+');

  /// Look up the redesign color for a compound base name; returns null
  /// when no override is defined.
  static Color? compoundColor(String base) {
    final key = base.toLowerCase().trim();
    if (_baseColorOverrides.containsKey(key)) return _baseColorOverrides[key];
    // Try first word (e.g. "Sustanon 250" → "sustanon")
    final firstWord = key.split(_whitespace).first;
    return _baseColorOverrides[firstWord];
  }

  static TextStyle sans({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
  }) => TextStyle(
        fontFamily: 'Inter',
        fontSize: size,
        fontWeight: weight,
        color: color ?? fg,
        letterSpacing: letterSpacing,
        height: height,
      );

  static TextStyle serif({
    double size = 48,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double? letterSpacing,
    double? height,
  }) => TextStyle(
        fontFamily: 'Fraunces',
        fontSize: size,
        fontWeight: weight,
        color: color ?? fg,
        letterSpacing: letterSpacing,
        height: height,
      );

  static TextStyle mono({
    double size = 11,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
  }) => TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: size,
        fontWeight: weight,
        color: color ?? fg,
        letterSpacing: letterSpacing,
      );
}
