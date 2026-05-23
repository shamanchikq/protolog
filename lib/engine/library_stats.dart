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
