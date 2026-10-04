import 'dart:math' as math;

import '../models.dart';
import '../data.dart';
import 'calendar.dart';
import 'compute_engine.dart';

/// Date of the last dose of (base, ester) actually taken — at or before
/// [now] (default: the real clock) — or null when none. Planned
/// (future-dated) doses are not "last used".
DateTime? lastInjectionFor({
  required String base,
  required String ester,
  required List<Injection> injections,
  DateTime? now,
}) =>
    _latestDoseFor(base, ester, injections, notAfter: now ?? DateTime.now());

/// Latest dose date of (base, ester), or null; ignores doses after
/// [notAfter] when given.
DateTime? _latestDoseFor(
  String base,
  String ester,
  List<Injection> injections, {
  DateTime? notAfter,
}) {
  DateTime? best;
  for (final inj in injections) {
    if (inj.snapshot.base != base) continue;
    if (inj.snapshot.ester != ester) continue;
    if (notAfter != null && inj.date.isAfter(notAfter)) continue;
    if (best == null || inj.date.isAfter(best)) {
      best = inj.date;
    }
  }
  return best;
}

/// "4h ago" when <24h, "Nd ago" otherwise, "—" for null. Always integer.
/// A future date (a planned dose) reads "in 5h" / "in 2d" — at least
/// "in 1h" — never a negative age.
///
/// Days are counted on the wall clock ([_wallClockDaysBetween]), not as
/// 24 h blocks, so a 23 h or 25 h DST day doesn't make "Nd ago" off by one.
String formatUsedAgo(DateTime? when, {DateTime? now}) {
  if (when == null) return '—';
  final n = now ?? DateTime.now();
  if (when.isAfter(n)) {
    final ahead = when.difference(n);
    if (ahead.inHours < 24) return 'in ${ahead.inHours < 1 ? 1 : ahead.inHours}h';
    return 'in ${math.max(1, _wallClockDaysBetween(n, when))}d';
  }
  final diff = n.difference(when);
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return '${h}h ago';
  }
  // ≥ 24 h elapsed is at least a day, even when a 25 h fall-back day keeps
  // the wall clock short of a full one.
  return '${math.max(1, _wallClockDaysBetween(when, n))}d ago';
}

/// Whole days from [from] to a later [to] as the wall clock counts them:
/// the calendar days between their dates ([calendarDaysBetween]), less one
/// when [to]'s time of day hasn't yet reached [from]'s. DST-safe.
int _wallClockDaysBetween(DateTime from, DateTime to) {
  final days = calendarDaysBetween(from, to);
  return _timeOfDayMicros(to) < _timeOfDayMicros(from) ? days - 1 : days;
}

int _timeOfDayMicros(DateTime d) =>
    (((d.hour * 60 + d.minute) * 60 + d.second) * 1000 + d.millisecond) * 1000 +
    d.microsecond;

/// True when the most-recent injection of `compound` (matched by base+ester)
/// is within its PK-relevance window — the shared [relevanceWindowDays] rule
/// (effective half-life × 8; blends use their longest component). Falls back
/// to 7 days when the half-life is unusable (≤ 0 / non-finite), so a logged
/// compound still lists even though it has no modelled contribution. A
/// planned (future-dated) dose counts: the compound is part of the protocol.
bool isInProtocol({
  required CompoundDefinition compound,
  required List<Injection> injections,
  DateTime? now,
}) {
  final last = _latestDoseFor(compound.base, compound.ester, injections);
  if (last == null) return false;
  final n = now ?? DateTime.now();
  final pkWindow = relevanceWindowDays(compound);
  final windowDays = pkWindow > 0 ? pkWindow : 7.0;
  final ageDays = n.difference(last).inSeconds / 86400.0;
  return ageDays <= windowDays;
}

/// All compounds the user is currently dosing (within their PK-relevance
/// window, see [isInProtocol]), sorted by last real use desc
/// ([lastInjectionFor] at [now]; planned-only compounds last). Walks the
/// union of:
///   - userCompounds (customs + user-added presets)
///   - BASE_LIBRARY entries referenced by recent injection snapshots
/// A custom shadows a built-in with the same (base, ester).
List<CompoundDefinition> protocolCompounds({
  required List<CompoundDefinition> userCompounds,
  required List<Injection> injections,
  DateTime? now,
}) {
  final n = now ?? DateTime.now();

  // Keyed by compoundKey so customs and built-ins collapse if they collide;
  // duplicate user entries resolve exactly as dedupeUserCompounds does.
  final candidates = <String, CompoundDefinition>{};
  for (final c in dedupeUserCompounds(userCompounds).compounds) {
    candidates[keyOf(c)] = c;
  }
  for (final inj in injections) {
    candidates.putIfAbsent(keyOf(inj.snapshot), () => inj.snapshot);
  }

  final inProtocol = candidates.values
      .where((c) => isInProtocol(compound: c, injections: injections, now: n))
      .toList();

  inProtocol.sort((a, b) {
    final la = lastInjectionFor(base: a.base, ester: a.ester, injections: injections, now: n);
    final lb = lastInjectionFor(base: b.base, ester: b.ester, injections: injections, now: n);
    if (la == null && lb == null) return keyOf(a).compareTo(keyOf(b));
    if (la == null) return 1;
    if (lb == null) return -1;
    final byDate = lb.compareTo(la);
    return byDate != 0 ? byDate : keyOf(a).compareTo(keyOf(b));
  });

  return inProtocol;
}

/// Full catalogue: BASE_LIBRARY entries (id set to the map key for display)
/// merged with user customs. A custom with the same (base, ester) as a
/// built-in supersedes the built-in; duplicate user entries for one
/// (base, ester) resolve to the same single entry [dedupeUserCompounds]
/// keeps. Sorted by type (steroid, oral, peptide, ancillary), then base name,
/// ester and id — a total order, so the result never depends on the order of
/// [userCompounds] (Dart's sort is not stable).
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
    merged[keyOf(c)] = c;
  }
  for (final c in dedupeUserCompounds(userCompounds).compounds) {
    merged[keyOf(c)] = c;
  }

  final list = merged.values.toList();
  list.sort((a, b) {
    final ta = typeOrder[a.type] ?? 99;
    final tb = typeOrder[b.type] ?? 99;
    if (ta != tb) return ta.compareTo(tb);
    final byBase = a.base.toLowerCase().compareTo(b.base.toLowerCase());
    if (byBase != 0) return byBase;
    final byEster = a.ester.toLowerCase().compareTo(b.ester.toLowerCase());
    if (byEster != 0) return byEster;
    final byKey = keyOf(a).compareTo(keyOf(b));
    return byKey != 0 ? byKey : a.id.compareTo(b.id);
  });
  return list;
}

/// Canonical identity of a compound: its exact `base|ester`. At most one
/// user compound should exist per key (B6).
///
/// Exact and case-sensitive on purpose: it is the same matching the wizard,
/// injection snapshots, stats ([lastInjectionFor] etc.) and rewriteSnapshots
/// use, so two entries sharing a key are always ones the rest of the app
/// already treats as one compound. The editor and importer store trimmed
/// names and the literal 'None' for "no ester", so stored data is canonical.
String compoundKey(String base, String ester) => '$base|$ester';

/// [compoundKey] of [c].
String keyOf(CompoundDefinition c) => compoundKey(c.base, c.ester);

/// Collapses [compounds] (the stored userCompounds) to one entry per
/// [compoundKey] (B6: the wizard adopting a built-in under a timestamp id +
/// a backup merge that upserts by id can leave two entries for one compound;
/// the Library then edited one while the wizard snapshotted the other).
///
/// **Winner:** the *later* entry in list order. That is the entry the
/// Library has always shown and edited (later entries shadow earlier ones in
/// [cataloguedCompounds]), and after a backup merge it is the incoming one —
/// matching the merge's own "incoming wins" upsert. So deduping changes
/// nothing the Library displays; it only makes the wizard (which matched the
/// first) use those same settings for future logs. If the winner has no
/// `concentration`, the latest non-null one among its dropped duplicates is
/// carried over so a vial strength typed in the wizard isn't lost.
///
/// The kept entry sits where its key first appeared; unrelated entries keep
/// their order. Exact duplicates (same id) collapse silently.
///
/// Returns:
/// - `compounds`: the deduped list.
/// - `idRemap`: dropped id → kept id, for ids that no kept entry still uses.
///   A dropped id that remains the id of another kept compound (legacy shared
///   ids such as 'temp') is ambiguous and left out.
/// - `injections`: [injections] with `compoundId` relinked to the kept id —
///   via `idRemap`, or, for ambiguous ids, when the injection's snapshot has
///   the dropped entry's key. Unchanged injections are returned as-is
///   (identical); snapshots are never touched (they stay frozen).
({
  List<CompoundDefinition> compounds,
  Map<String, String> idRemap,
  List<Injection> injections,
}) dedupeUserCompounds(
  List<CompoundDefinition> compounds, {
  List<Injection> injections = const [],
}) {
  // Group by key, remembering first-appearance order.
  final groups = <String, List<CompoundDefinition>>{};
  for (final c in compounds) {
    groups.putIfAbsent(keyOf(c), () => []).add(c);
  }
  if (groups.length == compounds.length) {
    return (
      compounds: List<CompoundDefinition>.of(compounds),
      idRemap: <String, String>{},
      injections: List<Injection>.of(injections),
    );
  }

  final kept = <CompoundDefinition>[];
  // key → ids dropped from that key's group (excluding the winner's own id).
  final droppedByKey = <String, Set<String>>{};
  final winnerIdByKey = <String, String>{};
  for (final entry in groups.entries) {
    final group = entry.value;
    var winner = group.last;
    if (winner.concentration == null) {
      for (final c in group.reversed.skip(1)) {
        if (c.concentration != null) {
          winner = winner.copyWith(concentration: c.concentration);
          break;
        }
      }
    }
    kept.add(winner);
    winnerIdByKey[entry.key] = winner.id;
    final dropped = {for (final c in group) c.id}..remove(winner.id);
    if (dropped.isNotEmpty) droppedByKey[entry.key] = dropped;
  }

  final keptIds = {for (final c in kept) c.id};
  final targets = <String, Set<String>>{}; // dropped id → kept ids it maps to
  droppedByKey.forEach((key, ids) {
    for (final id in ids) {
      targets.putIfAbsent(id, () => {}).add(winnerIdByKey[key]!);
    }
  });
  final idRemap = <String, String>{
    for (final e in targets.entries)
      if (!keptIds.contains(e.key) && e.value.length == 1) e.key: e.value.single,
  };

  final relinked = <Injection>[];
  for (final inj in injections) {
    final key = keyOf(inj.snapshot);
    String? target = idRemap[inj.compoundId];
    if (target == null && (droppedByKey[key]?.contains(inj.compoundId) ?? false)) {
      target = winnerIdByKey[key];
    }
    relinked.add(target == null || target == inj.compoundId
        ? inj
        : Injection(
            id: inj.id,
            compoundId: target,
            date: inj.date,
            dosage: inj.dosage,
            snapshot: inj.snapshot,
            site: inj.site,
            notes: inj.notes,
          ));
  }

  return (compounds: kept, idRemap: idRemap, injections: relinked);
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

/// Display label for a compound row / hero. A built-in (or a user copy of
/// one — the wizard adopts built-ins under a timestamp id, and Library edits
/// store a shadowing override) is labelled by its BASE_LIBRARY map key,
/// matched by base+ester rather than id, so "Sustanon 250" / "MT2" keep their
/// names after the first log. True customs (and anything without a library
/// counterpart) join base + ester.
String displayName(CompoundDefinition c) {
  if (!c.isCustom) {
    final key = _libraryKeyFor(c.base, c.ester);
    if (key != null) return key;
  }
  final ester = c.ester.trim();
  if (ester.isEmpty || ester.toLowerCase() == 'none') return c.base;
  return '${c.base} $ester';
}

/// Meta line shown under the display name on Library rows.
/// Examples: "Steroid · t½ 5.0d", "Steroid · 4-ester", "Peptide · window",
/// "Peptide · event".
String metaLineFor(CompoundDefinition c) {
  final typeLabel = _typeLabel(c.type);
  // Blends are recognised by ester, exactly as the PK engine models them —
  // never by id, which changes when the wizard adopts a built-in.
  final blend = blendComponentsFor(c.ester);
  if (blend != null) return '$typeLabel · ${blend.length}-ester';
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

/// BASE_LIBRARY map key of the built-in with this exact (base, ester), or
/// null when there is none.
String? _libraryKeyFor(String base, String ester) {
  for (final entry in BASE_LIBRARY.entries) {
    if (entry.value.base == base && entry.value.ester == ester) return entry.key;
  }
  return null;
}

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

/// Live display-color candidates for compounds whose base is [base], read from
/// the current catalogue — never from injection snapshots. This is what lets a
/// library color edit recolor *all* logs (past and future) immediately.
///
/// - `userSet`: the colorValue of a matching compound whose color the user
///   changed from its built-in default (custom compounds always qualify). It
///   should win over the static redesign palette.
/// - `any`: any matching compound's colorValue, used as a last-resort fallback
///   when there is no palette entry for the base.
///
/// Both are null when no catalogued compound has that base.
({int? userSet, int? any}) colorCandidatesForBase(
  String base, {
  required List<CompoundDefinition> userCompounds,
}) {
  final key = base.toLowerCase().trim();
  int? userSet;
  int? any;
  for (final c in cataloguedCompounds(userCompounds: userCompounds)) {
    if (c.base.toLowerCase().trim() != key) continue;
    any ??= c.colorValue;
    final def = defaultDefFor(c);
    if (def == null || def.colorValue != c.colorValue) {
      userSet = c.colorValue; // explicit user color (custom or edited built-in)
      break;
    }
  }
  return (userSet: userSet, any: any);
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
