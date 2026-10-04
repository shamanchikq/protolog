import '../data.dart';
import '../models.dart';
import 'calendar.dart';
import 'dose_math.dart';
import 'library_stats.dart';

/// Pure logic behind the add-injection wizard: which compound a log is
/// drafted against, what the details step pre-fills, and what Confirm turns
/// the draft into. The wizard (`ui/views/add_injection_wizard.dart`) owns the
/// UI state and only calls into these.

/// Default intramuscular site (steroids — and anything not sub-Q).
const String defaultIntramuscularSite = 'Vent. glute R';

/// Default subcutaneous site (peptides, incl. HCG).
const String defaultSubcutaneousSite = 'Abdominal R';

/// Peptides (incl. HCG) are injected sub-Q; everything else injected is IM.
bool isSubcutaneousType(CompoundType type) => type == CompoundType.peptide;

/// "Pill form" = taken by mouth (orals and every ancillary): no injection
/// site and no Direct/By-volume toggle.
bool isPillFormType(CompoundType type) =>
    type == CompoundType.oral || type == CompoundType.ancillary;

/// The site pre-selected when a compound has no prior log with a site.
String defaultSiteFor(CompoundType type) =>
    isSubcutaneousType(type) ? defaultSubcutaneousSite : defaultIntramuscularSite;

/// The user's stored copy of [compound] — the entry of [userCompounds] with
/// the same [compoundKey] — or null. Of duplicates (B6: a timestamp-id
/// adoption plus a backup merge could leave two) the *last* wins: the one the
/// Library shows and edits, and the one [dedupeUserCompounds] keeps.
CompoundDefinition? userCopyOf(
  CompoundDefinition compound,
  List<CompoundDefinition> userCompounds,
) {
  final key = keyOf(compound);
  for (final c in userCompounds.reversed) {
    if (keyOf(c) == key) return c;
  }
  return null;
}

/// The compound a new log of [picked] is drafted against.
///
/// BASE_LIBRARY is the source of truth for type and native unit. A
/// user-stored copy can be stale: it may predate a categorization change
/// (HCG used to be an ancillary), and older versions materialized it with
/// whatever unit was picked on its first log (any of mg/mcg/IU). So the
/// library's type/unit decide the route and IU-nativeness. Everything that is
/// genuinely per-user comes from the user's copy ([userCopyOf]): PK edits
/// (shown in the chip; that copy is what Confirm freezes into the snapshot),
/// the concentration, and a preferred dose unit. True customs have no
/// library row, so their current stored record is the canon.
///
/// Returns the drafted compound, the canon's (native) unit and the user
/// copy's (preferred) unit, if there is a copy.
({CompoundDefinition compound, Unit nativeUnit, Unit? preferredUnit}) resolveDraftCompound({
  required CompoundDefinition picked,
  required List<CompoundDefinition> userCompounds,
}) {
  final userOverride = userCopyOf(picked, userCompounds);
  CompoundDefinition canon = userOverride ?? picked;
  for (final v in BASE_LIBRARY.values) {
    if (v.base == picked.base && v.ester == picked.ester) {
      canon = v;
      break;
    }
  }
  final effective = (userOverride ?? canon).copyWith(
    type: canon.type,
    unit: canon.unit,
    concentration: userOverride?.concentration ?? canon.concentration,
  );
  return (compound: effective, nativeUnit: canon.unit, preferredUnit: userOverride?.unit);
}

/// Most recent log of (base, ester), or null.
Injection? lastLogOf({
  required String base,
  required String ester,
  required List<Injection> injections,
}) {
  final matches = injections
      .where((i) => i.snapshot.base == base && i.snapshot.ester == ester)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  return matches.isNotEmpty ? matches.first : null;
}

/// Site of the most recent log of any compound with this [base] (any ester)
/// that recorded one, or null.
String? lastSiteFor({required String base, required List<Injection> injections}) {
  final priors = injections
      .where((i) => i.snapshot.base == base && i.site != null && i.site!.isNotEmpty)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  return priors.isNotEmpty ? priors.first.site : null;
}

/// Starting values for the wizard's details step.
class DraftPrefill {
  const DraftPrefill({
    required this.compound,
    required this.lastLog,
    required this.dose,
    required this.unit,
    required this.site,
  });

  /// The compound being logged. Its [CompoundDefinition.concentration] seeds
  /// the concentration draft.
  final CompoundDefinition compound;

  /// The previous log of this compound ("Last: …" line); null in edit mode.
  final Injection? lastLog;

  /// Amount to pre-fill, in [unit]; null leaves the field empty.
  final double? dose;
  final Unit unit;
  final String site;
}

/// Pre-fill for a new log of [picked]: the compound from
/// [resolveDraftCompound]; amount and unit from the same source (the last
/// log, else the user's preferred unit with no amount — see
/// [resolveDosePrefill]), so a dose logged as 0.25 mg is never re-offered as
/// 0.25 mcg; the site of the last log of the same base, else the route's
/// default.
DraftPrefill prefillNewLog({
  required CompoundDefinition picked,
  required List<CompoundDefinition> userCompounds,
  required List<Injection> injections,
}) {
  final resolved = resolveDraftCompound(picked: picked, userCompounds: userCompounds);
  final compound = resolved.compound;
  final last = lastLogOf(base: compound.base, ester: compound.ester, injections: injections);
  final dose = resolveDosePrefill(
    nativeUnit: resolved.nativeUnit,
    preferredUnit: resolved.preferredUnit,
    lastDose: last?.dosage,
    lastUnit: last?.snapshot.unit,
  );
  return DraftPrefill(
    compound: compound,
    lastLog: last,
    dose: dose.dose,
    unit: dose.unit,
    site: lastSiteFor(base: compound.base, injections: injections) ?? defaultSiteFor(compound.type),
  );
}

/// Pre-fill for editing [injection] in place. The compound is the log's own
/// frozen snapshot — editing a log must never silently re-canonicalize its PK.
DraftPrefill prefillEdit(Injection injection) => DraftPrefill(
      compound: injection.snapshot,
      lastLog: null,
      dose: injection.dosage,
      unit: injection.snapshot.unit,
      site: injection.site ?? defaultSiteFor(injection.snapshot.type),
    );

/// How far a dose may stray from the last one, either way, before the wizard
/// shows its "unusual dose" warning (G5).
const double unusualDoseFactor = 3;

/// [dose] (in [unit]) divided by the [last] logged dose of the compound, when
/// that ratio is beyond [unusualDoseFactor] either way (> 3× or < ⅓); null
/// when it isn't, when there is no last log, or when the two can't be
/// compared. mg and mcg compare as mass, so 250 mg against a last 250 mcg is
/// 1000× — the unit slip this warning exists to catch; IU against a mass
/// unit can't be compared. Drives a soft, non-blocking warning only.
double? unusualDoseRatio({required double dose, required Unit unit, required Injection? last}) {
  if (last == null) return null;
  final a = _comparableAmount(dose, unit, last.snapshot.unit);
  final b = last.dosage;
  if (a == null || !a.isFinite || a <= 0 || !b.isFinite || b <= 0) return null;
  final ratio = a / b;
  return (ratio > unusualDoseFactor || ratio < 1 / unusualDoseFactor) ? ratio : null;
}

/// [v] in [from] expressed in [to]; null when the units aren't convertible.
double? _comparableAmount(double v, Unit from, Unit to) {
  if (from == to) return v;
  if (from == Unit.mg && to == Unit.mcg) return v * 1000;
  if (from == Unit.mcg && to == Unit.mg) return v / 1000;
  return null;
}

/// The enabled reminder for the same base+ester as [compound], if any — the
/// one a new log can advance.
Reminder? linkedReminderFor({
  required CompoundDefinition? compound,
  required List<Reminder> reminders,
}) {
  if (compound == null) return null;
  for (final r in reminders) {
    if (r.enabled && r.compoundBase == compound.base && r.compoundEster == compound.ester) {
      return r;
    }
  }
  return null;
}

/// The details step's default timestamp for a new log: [now] rounded to the
/// nearest 5 minutes as a whole timestamp, so 23:58 becomes 00:00 of the
/// *next* day rather than of today (B24).
///
/// When the host pre-selected a [day] (the Calendar's FAB), the log goes on
/// that day at the rounded clock time — unless it is today, which behaves
/// exactly like no pre-selection.
DateTime defaultLogTime({required DateTime now, DateTime? day}) {
  // Minute 60 normalizes into the next hour (and day) via the constructor.
  final rounded = DateTime(now.year, now.month, now.day, now.hour, (now.minute / 5).round() * 5);
  if (day == null || isSameCalendarDay(day, now)) return rounded;
  return DateTime(day.year, day.month, day.day, rounded.hour, rounded.minute);
}

/// Bounds for the log date picker: from 2000 (or earlier, to include
/// [current]) to 365 days after [now] (or later, to include [current]).
/// Planned doses may be dated ahead; imported history may predate 2020, and
/// a picker whose range excludes its initial date asserts (B28).
({DateTime first, DateTime last}) logDatePickerRange({
  required DateTime current,
  required DateTime now,
}) {
  final day = dateOnly(current);
  final floor = DateTime(2000);
  final ceiling = addCalendarDays(dateOnly(now), 365);
  return (
    first: day.isBefore(floor) ? day : floor,
    last: day.isAfter(ceiling) ? day : ceiling,
  );
}

/// How many calendar days ahead of [now] a log dated [at] is, when that is
/// more than 24 h away; null otherwise (including the past). Drives the
/// wizard's non-blocking "in the future" hint — planned doses are legitimate.
int? futureDaysAhead(DateTime at, {required DateTime now}) {
  if (!at.isAfter(now.add(const Duration(days: 1)))) return null;
  return calendarDaysBetween(now, at);
}

/// Local timestamp of a log taken on [day] at [hour]:[minute].
DateTime logDateTime(DateTime day, {required int hour, required int minute}) =>
    DateTime(day.year, day.month, day.day, hour, minute);

/// Site stored on a log: none for pill-form compounds or an empty selection.
String? logSite(CompoundType type, String site) =>
    (!isPillFormType(type) && site.isNotEmpty) ? site : null;

/// Notes stored on a log: trimmed, null when blank.
String? logNotes(String notes) => notes.trim().isEmpty ? null : notes.trim();

/// What confirming a new log produces.
class NewLog {
  const NewLog({required this.injection, required this.compoundUpsert});

  final Injection injection;

  /// The user compound to upsert before [injection] is stored: a built-in or
  /// unsaved compound adopted on its first log, or the existing user copy
  /// with a changed concentration. Null when nothing about it changed.
  final CompoundDefinition? compoundUpsert;
}

/// Builds a new log of [compound] (the drafted compound, see
/// [resolveDraftCompound]).
///
/// The log is filed under the user's copy ([userCopyOf]); when there is
/// none, one is materialized from [compound] under [adoptionId]. A
/// concentration typed or calculated in the wizard
/// ([concentrationDraft]) is baked into that copy and written back only when
/// it changed. The copy keeps its own unit: [unit] belongs to this log only
/// and goes into the snapshot, so logging in another unit neither reverts a
/// Compound Editor choice nor flags a built-in as edited.
NewLog buildNewLog({
  required CompoundDefinition compound,
  required List<CompoundDefinition> userCompounds,
  required double dosage,
  required Unit unit,
  required DateTime date,
  required String site,
  required String notes,
  required double? concentrationDraft,
  required DateTime now,
}) {
  final existing = userCopyOf(compound, userCompounds);
  final CompoundDefinition compDef;
  final CompoundDefinition? upsert;
  if (existing != null) {
    final draft = concentrationDraft;
    if (draft != null && draft != existing.concentration) {
      compDef = existing.copyWith(concentration: draft);
      upsert = compDef;
    } else {
      compDef = existing;
      upsert = null;
    }
  } else {
    compDef = CompoundDefinition(
      id: adoptionId(compound, userCompounds: userCompounds, now: now),
      base: compound.base,
      ester: compound.ester,
      type: compound.type,
      graphType: compound.graphType,
      halfLife: compound.halfLife,
      defaultHalfLife: compound.defaultHalfLife,
      timeToPeak: compound.timeToPeak,
      ratio: compound.ratio,
      unit: compound.unit,
      colorValue: compound.colorValue,
      isCustom: compound.isCustom,
      concentration: concentrationDraft ?? compound.concentration,
    );
    upsert = compDef;
  }
  return NewLog(
    injection: Injection(
      id: now.toIso8601String(),
      compoundId: compDef.id,
      date: date,
      dosage: dosage,
      snapshot: compDef.copyWith(unit: unit),
      site: logSite(compound.type, site),
      notes: logNotes(notes),
    ),
    compoundUpsert: upsert,
  );
}

/// The id a compound gets when its first log materializes a user copy (B6).
///
/// - A built-in is adopted under its BASE_LIBRARY key ([defaultDefFor]), so
///   every install converges on one id per compound and a backup merge
///   (which upserts by id) updates the copy instead of adding a second.
/// - A true custom keeps its own id (e.g. one picked from an old log's
///   snapshot after the stored custom was deleted, which relinks it).
/// - Either falls back to an id derived from [now] when that id is unusable:
///   empty, the legacy placeholder 'temp', or already held by another user
///   compound (legacy data — say, a built-in override renamed into a custom).
String adoptionId(
  CompoundDefinition compound, {
  required List<CompoundDefinition> userCompounds,
  required DateTime now,
}) {
  final preferred = defaultDefFor(compound)?.id ?? compound.id;
  final usable = preferred.isNotEmpty &&
      preferred != 'temp' &&
      !userCompounds.any((c) => c.id == preferred);
  return usable ? preferred : now.millisecondsSinceEpoch.toString();
}

/// [original] with its editable fields replaced. Id, compound id and the
/// frozen PK snapshot are kept — only the snapshot's display unit follows
/// [unit]; user compounds are never touched by an edit.
Injection buildEditedLog({
  required Injection original,
  required double dosage,
  required Unit unit,
  required DateTime date,
  required String site,
  required String notes,
}) =>
    Injection(
      id: original.id,
      compoundId: original.compoundId,
      date: date,
      dosage: dosage,
      snapshot: original.snapshot.copyWith(unit: unit),
      site: logSite(original.snapshot.type, site),
      notes: logNotes(notes),
    );
