import 'format.dart';

/// [date] in one of the few patterns the app uses: 'yyyy-MM-dd'
/// ("2026-06-02"), 'MMM d' ("Jun 2") or 'EEE ha' ("Tue 3PM"). Any other
/// pattern falls back to `DateTime.toString()`.
String formatDate(DateTime date, String format) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');

  if (format == 'yyyy-MM-dd') {
    return "${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}";
  }
  if (format == 'EEE ha') {
    final dayName = weekdaysShort[date.weekday - 1];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    return "$dayName $hour$ampm";
  }
  if (format == 'MMM d') return formatMonthDay(date);
  return date.toString();
}

/// Parses user-typed numbers accepting both '.' and ',' as the decimal
/// separator (EU keyboards emit commas on decimal keypads). Null if invalid
/// or non-finite ("Infinity", "NaN", "1e999") — those pass `> 0` checks but
/// make `jsonEncode` throw on save and break the PK math.
///
/// Separator rule (B13) — there is no thousands separator:
/// - '.' is always the decimal point ("1.500" → 1.5); prefills and Dart's own
///   `toString` emit it.
/// - ',' is a decimal comma ("3,5" → 3.5, "0,250" → 0.25, "12,5" → 12.5)
///   unless it reads as a thousands group: a single comma followed by exactly
///   three digits after a non-zero integer part ("5,000", "1,500", "12,345")
///   is ambiguous and rejected, so 5,000 IU can't silently become 5 IU.
///   "0,250" stays valid because a thousands group never follows a lone 0.
/// - Mixed separators ("1.000,5", "1,000.5") and more than one separator are
///   rejected.
double? parseFlexibleDouble(String text) {
  final s = text.trim();
  if (s.contains(',')) {
    final m = _commaThousandsGroup.firstMatch(s);
    if (m != null && !_allZeros.hasMatch(m.group(1)!)) return null;
  }
  final v = double.tryParse(s.replaceAll(',', '.'));
  return v != null && v.isFinite ? v : null;
}

final _commaThousandsGroup = RegExp(r'^[+-]?(\d+),\d{3}$');
final _allZeros = RegExp(r'^0+$');
