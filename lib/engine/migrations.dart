import '../models.dart';
import 'library_stats.dart';

/// Pure fix-ups for stored (or restored) records, run at load and on every
/// backup merge. Idempotent: data that's already current comes back
/// unchanged and unflagged, so the caller persists only what moved.

/// Library base names whose spelling was corrected, old → new (G7). The
/// BASE_LIBRARY key/id changed with them.
const Map<String, String> kRenamedBases = {'Anastrazole': 'Anastrozole'};

/// The id compound records and logs used before B7: every library entry
/// shared it.
const String kLegacyTempId = 'temp';

/// [migrateRecords]'s output; a flag is set only when that collection
/// actually changed (and should be saved).
class MigrationResult {
  final List<Injection> injections;
  final List<CompoundDefinition> compounds;
  final List<Reminder> reminders;
  final bool injectionsChanged;
  final bool compoundsChanged;
  final bool remindersChanged;

  const MigrationResult({
    required this.injections,
    required this.compounds,
    required this.reminders,
    this.injectionsChanged = false,
    this.compoundsChanged = false,
    this.remindersChanged = false,
  });

  bool get changed => injectionsChanged || compoundsChanged || remindersChanged;
}

/// Brings stored records up to date, in order:
///
/// 1. **G7 renames** — a base in [kRenamedBases] is renamed in user
///    compounds, injection snapshots and reminders; an id equal to the old
///    library id ('Anastrazole') follows (compound ids, snapshot ids,
///    `compoundId`s).
/// 2. **Legacy 'temp' compound ids** — a stored library override still
///    under [kLegacyTempId] takes its library id ('Testosterone Cypionate').
/// 3. **B6 duplicates** — [dedupeUserCompounds] collapses user compounds
///    sharing base+ester (the later entry wins) and relinks injections.
/// 4. **'temp' links** — an injection whose `compoundId` is still
///    [kLegacyTempId] is linked by base+ester to the user compound, else the
///    library entry, with that key; left as is when neither exists.
///
/// Lists are always fresh and growable; records that didn't change are
/// returned as the same objects.
MigrationResult migrateRecords({
  required List<Injection> injections,
  required List<CompoundDefinition> compounds,
  required List<Reminder> reminders,
}) {
  // 1. Renamed bases.
  var comps = [for (final c in compounds) _renameCompound(c)];
  var injs = [
    for (final i in injections)
      _relink(i,
          compoundId: _renameId(i.compoundId), snapshot: _renameCompound(i.snapshot)),
  ];
  final rems = [
    for (final r in reminders)
      kRenamedBases.containsKey(r.compoundBase)
          ? r.copyWith(compoundBase: kRenamedBases[r.compoundBase])
          : r,
  ];

  // 2. Library overrides still under the shared placeholder id.
  comps = [
    for (final c in comps)
      c.id == kLegacyTempId ? c.copyWith(id: defaultDefFor(c)?.id ?? c.id) : c,
  ];

  // 3. One user compound per base+ester; logs follow the kept one.
  final deduped = dedupeUserCompounds(comps, injections: injs);
  comps = deduped.compounds;
  injs = deduped.injections;

  // 4. Logs still linked to the placeholder.
  final idByKey = {for (final c in comps) keyOf(c): c.id};
  injs = [
    for (final i in injs)
      i.compoundId == kLegacyTempId
          ? _relink(i,
              compoundId:
                  idByKey[keyOf(i.snapshot)] ?? defaultDefFor(i.snapshot)?.id ?? i.compoundId)
          : i,
  ];

  return MigrationResult(
    injections: injs,
    compounds: comps,
    reminders: rems,
    injectionsChanged: _differs(injections, injs),
    compoundsChanged: _differs(compounds, comps),
    remindersChanged: _differs(reminders, rems),
  );
}

String _renameId(String id) => kRenamedBases[id] ?? id;

CompoundDefinition _renameCompound(CompoundDefinition c) {
  final base = kRenamedBases[c.base];
  final id = _renameId(c.id);
  if (base == null && id == c.id) return c;
  return c.copyWith(base: base, id: id);
}

/// [i] with a new link/snapshot; [i] itself when neither changed.
Injection _relink(Injection i, {String? compoundId, CompoundDefinition? snapshot}) {
  final id = compoundId ?? i.compoundId;
  final snap = snapshot ?? i.snapshot;
  if (id == i.compoundId && identical(snap, i.snapshot)) return i;
  return Injection(
    id: i.id,
    compoundId: id,
    date: i.date,
    dosage: i.dosage,
    snapshot: snap,
    site: i.site,
    notes: i.notes,
  );
}

bool _differs<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return true;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return true;
  }
  return false;
}
