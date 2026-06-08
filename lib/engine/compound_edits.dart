import '../models.dart';

/// Returns a copy of [injections] where every injection whose snapshot matches
/// (base, ester) has its snapshot's curve-affecting PK fields replaced with the
/// supplied values.
///
/// Only the fields that change a computed curve/lane are rewritten:
/// half-life, time-to-peak, yield (ratio), and graph type. Dosage, unit, color,
/// identity (base/ester/type), site, notes — and every non-matching injection —
/// are left exactly as logged. Non-matching injections are returned by identity
/// (same instance), so unchanged history is never reallocated.
///
/// Used by the "apply edit to past logs?" flow when a user edits a compound's
/// pharmacokinetics and opts to recompute historical injections.
List<Injection> rewriteSnapshots({
  required List<Injection> injections,
  required String base,
  required String ester,
  required double halfLife,
  required double timeToPeak,
  required double ratio,
  required GraphType graphType,
}) {
  return injections.map((inj) {
    final s = inj.snapshot;
    if (s.base != base || s.ester != ester) return inj;
    return Injection(
      id: inj.id,
      compoundId: inj.compoundId,
      date: inj.date,
      dosage: inj.dosage,
      snapshot: s.copyWith(
        halfLife: halfLife,
        timeToPeak: timeToPeak,
        ratio: ratio,
        graphType: graphType,
      ),
      site: inj.site,
      notes: inj.notes,
    );
  }).toList();
}
