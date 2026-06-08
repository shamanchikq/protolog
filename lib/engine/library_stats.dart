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

/// Last `limit` injections of (base, ester), most recent first.
List<Injection> recentInjectionsFor({
  required String base,
  required String ester,
  required List<Injection> injections,
  int limit = 5,
}) {
  final matching = injections
      .where((i) => i.snapshot.base == base && i.snapshot.ester == ester)
      .toList();
  matching.sort((a, b) => b.date.compareTo(a.date));
  if (matching.length <= limit) return matching;
  return matching.sublist(0, limit);
}

/// Total injection count for (base, ester).
int injectionCountFor({
  required String base,
  required String ester,
  required List<Injection> injections,
}) {
  var n = 0;
  for (final inj in injections) {
    if (inj.snapshot.base == base && inj.snapshot.ester == ester) n++;
  }
  return n;
}

/// Display label for a compound row / hero. Uses the BASE_LIBRARY map key
/// when the compound's id matches; otherwise joins base + ester.
String displayName(CompoundDefinition c) {
  if (BASE_LIBRARY.containsKey(c.id)) return c.id;
  final ester = c.ester.trim();
  if (ester.isEmpty || ester.toLowerCase() == 'none') return c.base;
  return '${c.base} $ester';
}

/// Meta line shown under the display name on Library rows.
/// Examples: "Steroid · t½ 5.0d", "Steroid · 4-ester", "Peptide · window",
/// "Peptide · event".
String metaLineFor(CompoundDefinition c) {
  final typeLabel = _typeLabel(c.type);
  // blends: ester field contains "(Mix)" — count via known blend ids.
  if (c.id == 'Sustanon 250') return '$typeLabel · 4-ester';
  if (c.id == 'Tri-Tren') return '$typeLabel · 3-ester';
  if (c.graphType == GraphType.event) return '$typeLabel · event';
  if (c.graphType == GraphType.activeWindow) return '$typeLabel · window';
  // default: half-life
  return '$typeLabel · t½ ${c.halfLife.toStringAsFixed(1)}d';
}

String _typeLabel(CompoundType t) {
  switch (t) {
    case CompoundType.steroid:
      return 'Steroid';
    case CompoundType.oral:
      return 'Oral';
    case CompoundType.peptide:
      return 'Peptide';
    case CompoundType.ancillary:
      return 'Ancillary';
  }
}

/// True when `c` is a built-in (library) compound rather than a user-created
/// custom. Built-ins keep `isCustom == false` even after the user edits their
/// PK params (the edit is stored as a shadowing override in userCompounds).
bool isBuiltIn(CompoundDefinition c) => !c.isCustom;

/// The BASE_LIBRARY default for `c`, matched by base+ester, with its `id`
/// resolved to the library map key. Null when `c` has no library counterpart
/// (a true custom compound).
CompoundDefinition? defaultDefFor(CompoundDefinition c) {
  for (final entry in BASE_LIBRARY.entries) {
    final v = entry.value;
    if (v.base == c.base && v.ester == c.ester) {
      return v.copyWith(id: entry.key);
    }
  }
  return null;
}

/// True when `c` is a built-in whose editable params (half-life, time-to-peak,
/// yield, unit, lane color, graph type) differ from its BASE_LIBRARY default.
/// Seeds that still equal the default — and true customs — return false.
bool isEditedFromDefault(CompoundDefinition c) {
  if (c.isCustom) return false;
  final def = defaultDefFor(c);
  if (def == null) return false;
  return c.halfLife != def.halfLife ||
      c.timeToPeak != def.timeToPeak ||
      c.ratio != def.ratio ||
      c.unit != def.unit ||
      c.colorValue != def.colorValue ||
      c.graphType != def.graphType;
}

/// True for compound types that are injected (steroids, peptides). Orals and
/// ancillaries are taken by mouth, so they're "administered" rather than
/// "injected" in UI copy.
bool isInjectableType(CompoundType t) =>
    t == CompoundType.steroid || t == CompoundType.peptide;

/// Noun for the act of taking a dose: "injection" for injectables (steroids,
/// peptides), "administration" for orals/ancillaries.
String doseActionNoun(CompoundType t) =>
    isInjectableType(t) ? 'injection' : 'administration';
