import '../models.dart';
import '../data.dart';

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

/// All compounds the user is currently dosing (within their PK-relevance
/// window), sorted by last-used desc. Walks the union of:
///   - userCompounds (customs + user-added presets)
///   - BASE_LIBRARY entries referenced by recent injection snapshots
/// A custom shadows a built-in with the same (base, ester).
List<CompoundDefinition> protocolCompounds({
  required List<CompoundDefinition> userCompounds,
  required List<Injection> injections,
  DateTime? now,
}) {
  final n = now ?? DateTime.now();

  // Key by "base|ester" so customs and built-ins collapse if they collide.
  final candidates = <String, CompoundDefinition>{};
  for (final c in userCompounds) {
    candidates['${c.base}|${c.ester}'] = c;
  }
  for (final inj in injections) {
    final key = '${inj.snapshot.base}|${inj.snapshot.ester}';
    candidates.putIfAbsent(key, () => inj.snapshot);
  }

  final inProtocol = candidates.values
      .where((c) => isInProtocol(compound: c, injections: injections, now: n))
      .toList();

  inProtocol.sort((a, b) {
    final la = lastInjectionFor(base: a.base, ester: a.ester, injections: injections);
    final lb = lastInjectionFor(base: b.base, ester: b.ester, injections: injections);
    if (la == null && lb == null) return 0;
    if (la == null) return 1;
    if (lb == null) return -1;
    return lb.compareTo(la);
  });

  return inProtocol;
}

/// Full catalogue: BASE_LIBRARY entries (id set to the map key for display)
/// merged with user customs. A custom with the same (base, ester) as a
/// built-in supersedes the built-in. Sorted by type (steroid, oral, peptide,
/// ancillary) then base name ascending.
List<CompoundDefinition> cataloguedCompounds({
  required List<CompoundDefinition> userCompounds,
}) {
  const typeOrder = {
    CompoundType.steroid: 0,
    CompoundType.oral: 1,
    CompoundType.peptide: 2,
    CompoundType.ancillary: 3,
  };

  final merged = <String, CompoundDefinition>{};
  for (final entry in BASE_LIBRARY.entries) {
    final c = entry.value.copyWith(id: entry.key);
    merged['${c.base}|${c.ester}'] = c;
  }
  for (final c in userCompounds) {
    merged['${c.base}|${c.ester}'] = c;
  }

  final list = merged.values.toList();
  list.sort((a, b) {
    final ta = typeOrder[a.type] ?? 99;
    final tb = typeOrder[b.type] ?? 99;
    if (ta != tb) return ta.compareTo(tb);
    return a.base.toLowerCase().compareTo(b.base.toLowerCase());
  });
  return list;
}
