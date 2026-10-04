import '../../../data.dart';
import '../../../models.dart';

// What the wizard's compound picker (step 1) lists. Pure functions over
// BASE_LIBRARY + the user's compounds.
//
// These are *not* `cataloguedCompounds` (engine/library_stats.dart), which
// the Library and the reminder editor use, and swapping them in would change
// what the picker shows:
// - order: here user compounds come first, then BASE_LIBRARY declaration
//   order; cataloguedCompounds sorts by type, then base name;
// - non-steroid rows: here a user copy of a library entry is hidden behind
//   the library row (and filed under the library's type); there the user
//   copy replaces it;
// - duplicates per base+ester: here the first user copy wins, there the last.

/// The compound type a step-1 filter key selects
/// ('steroid' | 'oral' | 'peptide' | 'ancillary'; anything else → steroid).
CompoundType typeForFilter(String filter) {
  switch (filter) {
    case 'steroid': return CompoundType.steroid;
    case 'oral': return CompoundType.oral;
    case 'peptide': return CompoundType.peptide;
    case 'ancillary': return CompoundType.ancillary;
    default: return CompoundType.steroid;
  }
}

/// Case-insensitive substring match of [query] on base or ester. A blank
/// query matches everything.
bool matchesCompoundSearch(CompoundDefinition c, String query) {
  if (query.trim().isEmpty) return true;
  final q = query.toLowerCase();
  return c.base.toLowerCase().contains(q) || c.ester.toLowerCase().contains(q);
}

/// Number of distinct steroid esters of [base] across the user's compounds
/// and BASE_LIBRARY. More than one makes the base row drill down.
int esterCountForBase(String base, List<CompoundDefinition> userCompounds) {
  final Set<String> esters = {};
  for (final c in userCompounds) {
    if (c.type == CompoundType.steroid && c.base == base) esters.add(c.ester);
  }
  BASE_LIBRARY.forEach((_, v) {
    if (v.type == CompoundType.steroid && v.base == base) esters.add(v.ester);
  });
  return esters.length;
}

/// The current user compound (first match) or BASE_LIBRARY entry for
/// (base, ester), or null.
CompoundDefinition? catalogCompoundFor(
  String base,
  String ester,
  List<CompoundDefinition> userCompounds,
) {
  for (final c in userCompounds) {
    if (c.base == base && c.ester == ester) return c;
  }
  for (final v in BASE_LIBRARY.values) {
    if (v.base == base && v.ester == ester) return v;
  }
  return null;
}

/// Up to 3 recently logged compounds of [type], one per base, newest first,
/// each re-resolved to its current catalog compound when there is one (else
/// the log's snapshot), with the date of that base's latest log.
List<({CompoundDefinition compound, DateTime lastDate})> recentCompounds({
  required CompoundType type,
  required List<Injection> injections,
  required List<CompoundDefinition> userCompounds,
}) {
  final Map<String, ({CompoundDefinition compound, DateTime lastDate})> map = {};
  // Sort injections newest first, dedupe by base.
  final sorted = [...injections]..sort((a, b) => b.date.compareTo(a.date));
  for (final inj in sorted) {
    final snap = inj.snapshot;
    if (snap.type != type) continue;
    if (map.containsKey(snap.base)) continue;
    final live = catalogCompoundFor(snap.base, snap.ester, userCompounds) ?? snap;
    map[snap.base] = (compound: live, lastDate: inj.date);
    if (map.length >= 3) break;
  }
  return map.values.toList();
}

/// The picker's library list for [type], filtered by [query]:
/// - steroids, not drilled in: one row per base (user compounds first, then
///   BASE_LIBRARY order);
/// - steroids drilled into [drillBase]: one row per ester of that base;
/// - other types: one row per base. BASE_LIBRARY is the source of truth for
///   categorization — a user compound whose (base, ester) matches a library
///   entry is just a personalized copy and is represented by the library row
///   under the library's type. User entries with no library row are truly
///   custom and listed under their own type.
List<CompoundDefinition> pickerCompounds({
  required CompoundType type,
  required String? drillBase,
  required String query,
  required List<CompoundDefinition> userCompounds,
}) {
  bool matches(CompoundDefinition c) => matchesCompoundSearch(c, query);
  if (type == CompoundType.steroid && drillBase == null) {
    final Map<String, CompoundDefinition> bases = {};
    for (final c in userCompounds) {
      if (c.type == CompoundType.steroid && !bases.containsKey(c.base)) {
        bases[c.base] = c;
      }
    }
    BASE_LIBRARY.forEach((_, v) {
      if (v.type == CompoundType.steroid && !bases.containsKey(v.base)) {
        bases[v.base] = v;
      }
    });
    return bases.values.where(matches).toList();
  }
  if (type == CompoundType.steroid && drillBase != null) {
    final Map<String, CompoundDefinition> esters = {};
    for (final c in userCompounds) {
      if (c.type == CompoundType.steroid && c.base == drillBase) {
        esters.putIfAbsent(c.ester, () => c);
      }
    }
    BASE_LIBRARY.forEach((_, v) {
      if (v.type == CompoundType.steroid && v.base == drillBase) {
        esters.putIfAbsent(v.ester, () => v);
      }
    });
    return esters.values.where(matches).toList();
  }
  final Map<String, CompoundDefinition> map = {};
  BASE_LIBRARY.forEach((_, v) {
    if (v.type == type && !map.containsKey(v.base)) {
      map[v.base] = v;
    }
  });
  for (final c in userCompounds) {
    final libMatch = BASE_LIBRARY.values.any((v) => v.base == c.base && v.ester == c.ester);
    if (libMatch) continue; // already represented by the library entry above
    if (c.type == type && !map.containsKey(c.base)) {
      map[c.base] = c;
    }
  }
  return map.values.where(matches).toList();
}
