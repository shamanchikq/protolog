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

/// True when the most-recent injection of `compound` (matched by base+ester)
/// is within its PK-relevance window. Window = halfLife * 8 days; falls back
/// to 7 days when halfLife <= 0 (event-only compounds).
bool isInProtocol({
  required CompoundDefinition compound,
  required List<Injection> injections,
  DateTime? now,
}) {
  final last = lastInjectionFor(
    base: compound.base,
    ester: compound.ester,
    injections: injections,
  );
  if (last == null) return false;
  final n = now ?? DateTime.now();
  final windowDays = compound.halfLife > 0 ? compound.halfLife * 8 : 7.0;
  final ageDays = n.difference(last).inSeconds / 86400.0;
  return ageDays <= windowDays;
}
