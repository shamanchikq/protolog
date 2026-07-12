String formatDate(DateTime date, String format) {
  final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String twoDigits(int n) => n.toString().padLeft(2, '0');

  if (format == 'MM/dd HH:mm') {
    return "${twoDigits(date.day)}/${twoDigits(date.month)} ${twoDigits(date.hour)}:${twoDigits(date.minute)}";
  }
  if (format == 'yyyy-MM-dd') {
    return "${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}";
  }
  if (format == 'EEE ha') {
    final dayName = days[date.weekday - 1];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    return "$dayName $hour$ampm";
  }
  if (format == 'MMM d') {
    return "${months[date.month - 1]} ${date.day}";
  }
  return date.toString();
}

String capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1).toLowerCase();
}

/// Parses user-typed numbers accepting both '.' and ',' as the decimal
/// separator (EU keyboards emit commas on decimal keypads). Null if invalid.
double? parseFlexibleDouble(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));
