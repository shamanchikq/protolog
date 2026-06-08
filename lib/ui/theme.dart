import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
  static const fgDim = Color(0xFF5C626C);
  static const accent = Color(0xFF7DD3D0);
  static const accentDeep = Color(0xFF3A6F6D);
  static const warm = Color(0xFFE0B870);
  static const warn = Color(0xFFD27A6B);

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

  /// Look up the redesign color for a compound base name; returns null
  /// when no override is defined.
  static Color? compoundColor(String base) {
    final key = base.toLowerCase().trim();
    if (_baseColorOverrides.containsKey(key)) return _baseColorOverrides[key];
    // Try first word (e.g. "Sustanon 250" → "sustanon")
    final firstWord = key.split(RegExp(r'\s+')).first;
    return _baseColorOverrides[firstWord];
  }

  static TextStyle sans({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
  }) => GoogleFonts.inter(
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
  }) => GoogleFonts.fraunces(
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
  }) => GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: weight,
        color: color ?? fg,
        letterSpacing: letterSpacing,
      );
}
