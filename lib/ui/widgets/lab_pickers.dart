import 'package:flutter/material.dart';
import '../theme.dart';

/// Wraps a Material date/time picker in the "Lab Sheet" theme — near-black
/// surfaces, mint accent, sharp corners. Use as the picker's builder:
/// `builder: (ctx, child) => labPickerTheme(child!)`.
Widget labPickerTheme(Widget child) {
  return Theme(
    data: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: AppTheme.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppTheme.accent,
        onPrimary: AppTheme.bg,
        surface: AppTheme.surface,
        onSurface: AppTheme.fg,
        surfaceContainerHighest: AppTheme.surface2,
        outline: AppTheme.border,
        secondary: AppTheme.accent,
        onSecondary: AppTheme.bg,
        error: AppTheme.warn,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(),
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppTheme.surface2,
        headerForegroundColor: AppTheme.fg,
        shape: RoundedRectangleBorder(),
        dividerColor: AppTheme.border,
        dayShape: WidgetStatePropertyAll(RoundedRectangleBorder()),
      ),
      timePickerTheme: const TimePickerThemeData(
        backgroundColor: AppTheme.surface,
        dialBackgroundColor: AppTheme.surface2,
        dialHandColor: AppTheme.accent,
        dialTextColor: AppTheme.fg,
        hourMinuteColor: AppTheme.surface2,
        hourMinuteTextColor: AppTheme.fg,
        dayPeriodColor: AppTheme.surface2,
        dayPeriodTextColor: AppTheme.fg,
        shape: RoundedRectangleBorder(),
        hourMinuteShape: RoundedRectangleBorder(),
        entryModeIconColor: AppTheme.fgMute,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.accent,
          textStyle: AppTheme.sans(size: 13, weight: FontWeight.w600),
        ),
      ),
    ),
    child: child,
  );
}
