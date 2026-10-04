/// Shared display formatting: numbers without float noise or truncation,
/// and the month / weekday names every screen used to redeclare.
///
/// Pure Dart (no Flutter imports) so it is trivially unit-testable and can
/// be used from the engine as well as any widget or painter. Lives outside
/// `ui/` so `engine/` never imports from the UI layer; `ui/format.dart`
/// re-exports it for widget code.
library;

import 'dart:math' as math;

/// Short month names, indexed by `DateTime.month - 1`.
const List<String> monthsShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Full month names, indexed by `DateTime.month - 1`.
const List<String> monthsLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Short weekday names, indexed by `DateTime.weekday - 1` (Monday first).
const List<String> weekdaysShort = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// Full weekday names, indexed by `DateTime.weekday - 1` (Monday first).
const List<String> weekdaysLong = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// "Jun 2".
String formatMonthDay(DateTime d) => '${monthsShort[d.month - 1]} ${d.day}';

final _trailingZeros = RegExp(r'0+$');

/// Strips trailing zeros (and a dangling '.') from a fixed-point string:
/// "1.500" → "1.5", "2.000" → "2". A negative zero reads as "0".
String stripTrailingZeros(String fixed) {
  var s = fixed;
  if (s.contains('.') && !s.contains('e')) {
    s = s.replaceFirst(_trailingZeros, '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  if (s == '-0') return '0';
  return s;
}

/// The fewest decimals (at most [maxDecimals]) that print [v] exactly —
/// i.e. the precision a typed value was entered with. Float noise
/// (0.1 + 0.2) hits the cap. 0 for non-finite values.
int decimalsOf(double v, {int maxDecimals = 6}) {
  if (!v.isFinite) return 0;
  for (var d = 0; d < maxDecimals; d++) {
    if (double.parse(v.toStringAsFixed(d)) == v) return d;
  }
  return maxDecimals;
}

/// A lab value as it was typed: 120 → "120", 38.5 → "38.5",
/// 0.1 + 0.2 → "0.3". Non-finite reads as "—".
String formatLabValue(double v, {int maxDecimals = 6}) {
  if (!v.isFinite) return '—';
  return stripTrailingZeros(
    v.toStringAsFixed(decimalsOf(v, maxDecimals: maxDecimals)),
  );
}

/// [current] − [previous], rounded to the larger precision of the two
/// values, so 37.9 − 32.1 is 5.8 rather than 5.799999999999997.
double labDelta(double current, double previous) {
  final raw = current - previous;
  if (!raw.isFinite) return raw;
  final decimals = math.max(decimalsOf(current), decimalsOf(previous));
  return double.parse(raw.toStringAsFixed(decimals));
}

/// "↑ 5.8" / "↓ 5.8" for the change from [previous] to [current]; empty
/// when there is no visible change (or a value isn't finite). Arrows only —
/// direction isn't universally good or bad across markers.
String formatLabDelta(double current, double previous) {
  final d = labDelta(current, previous);
  if (!d.isFinite || d == 0) return '';
  return '${d > 0 ? '↑' : '↓'} ${formatLabValue(d.abs())}';
}

/// A dose amount without float noise or truncation: 250 → "250",
/// 0.125 → "0.125", 1/3 → "0.333". Up to three decimals; amounts below 1
/// keep three significant digits (0.0625 → "0.0625"), capped at six
/// decimals. Non-finite reads as "—".
String formatDose(double v) {
  if (!v.isFinite) return '—';
  final a = v.abs();
  var decimals = 3;
  if (a > 0 && a < 1) {
    // Zeros between the point and the first significant digit.
    final leadingZeros = (-math.log(a) / math.ln10).ceil() - 1;
    decimals = math.min(6, 3 + math.max(0, leadingZeros));
  }
  return stripTrailingZeros(v.toStringAsFixed(decimals));
}
