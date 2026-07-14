import '../models.dart';

/// Distinct marker names, ordered by most recent draw first — drives the
/// chip order on the bloodwork page and card.
List<String> distinctMarkers(List<BloodworkEntry> entries) {
  final latest = <String, DateTime>{};
  for (final e in entries) {
    final cur = latest[e.marker];
    if (cur == null || e.date.isAfter(cur)) latest[e.marker] = e.date;
  }
  final markers = latest.keys.toList()
    ..sort((a, b) => latest[b]!.compareTo(latest[a]!));
  return markers;
}

/// All draws of one marker, oldest first (chart order).
List<BloodworkEntry> historyFor(String marker, List<BloodworkEntry> entries) {
  final h = entries.where((e) => e.marker == marker).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return h;
}

/// Change vs the previous draw of the same marker, or null for the first.
double? deltaVsPrevious(BloodworkEntry entry, List<BloodworkEntry> entries) {
  BloodworkEntry? prev;
  for (final e in entries) {
    if (e.marker != entry.marker || e.id == entry.id) continue;
    if (e.date.isAfter(entry.date)) continue;
    if (prev == null || e.date.isAfter(prev.date)) prev = e;
  }
  if (prev == null) return null;
  return entry.value - prev.value;
}
