import '../models.dart';

/// Most-recent injection date for (base, ester), or null when none.
DateTime? lastInjectionFor({
  required String base,
  required String ester,
  required List<Injection> injections,
}) {
  DateTime? best;
  for (final inj in injections) {
    if (inj.snapshot.base != base) continue;
    if (inj.snapshot.ester != ester) continue;
    if (best == null || inj.date.isAfter(best)) {
      best = inj.date;
    }
  }
  return best;
}

/// "4h ago" when <24h, "Nd ago" otherwise, "—" for null. Always integer.
String formatUsedAgo(DateTime? when, {DateTime? now}) {
  if (when == null) return '—';
  final n = now ?? DateTime.now();
  final diff = n.difference(when);
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return '${h}h ago';
  }
  final d = diff.inDays;
  return '${d}d ago';
}
