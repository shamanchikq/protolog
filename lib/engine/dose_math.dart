import '../models.dart';

/// Dose ↔ volume conversion for the log wizard.
///
/// Vial concentration is stored per compound in one of two families:
/// - **IU/mL** for IU-native compounds (HCG, HGH — native unit `iu`);
/// - **mg/mL** for everything else, *including* mcg-dosed peptides — a 5 mg
///   BPC-157 vial in 2 mL of bac water is 2.5 mg/mL, and a 250 mcg dose of it
///   is 0.1 mL. The dose unit therefore needs a mass factor (1 mg = 1000 mcg)
///   whenever it differs from the concentration's mass unit.
///
/// "IU" on the volume side is a different thing: the graduations of a U-100
/// insulin syringe (100 units = 1 mL), used to read off a volume. See
/// [mlFromSyringeUnits] / [syringeUnitsFromMl].

/// Graduations per mL on a U-100 insulin syringe.
const double syringeUnitsPerMl = 100;

/// Volume in mL for a reading of [units] on a U-100 syringe.
double mlFromSyringeUnits(double units) => units / syringeUnitsPerMl;

/// U-100 syringe reading for a volume of [ml].
double syringeUnitsFromMl(double ml) => ml * syringeUnitsPerMl;

/// How many [unit]s one concentration unit (mg, or IU when
/// [iuConcentration]) holds. Null when the two can't be related: a mass dose
/// against an IU/mL vial, or an IU dose against a mg/mL vial.
double? _doseUnitsPerConcentrationUnit(Unit unit, {required bool iuConcentration}) {
  if (iuConcentration) return unit == Unit.iu ? 1 : null;
  switch (unit) {
    case Unit.mg:
      return 1;
    case Unit.mcg:
      return 1000;
    case Unit.iu:
      return null;
  }
}

/// Dose (in [unit]) delivered by [volumeMl] of a vial at [concentration]
/// (IU/mL when [iuConcentration], otherwise mg/mL).
///
/// Null when the concentration is unknown, non-positive or non-finite, the
/// volume is negative or non-finite, or [unit] can't be expressed in the
/// concentration's family.
double? doseForVolume({
  required double volumeMl,
  required double? concentration,
  required Unit unit,
  required bool iuConcentration,
}) {
  final perConc = _doseUnitsPerConcentrationUnit(unit, iuConcentration: iuConcentration);
  if (perConc == null || !_validConcentration(concentration)) return null;
  if (!volumeMl.isFinite || volumeMl < 0) return null;
  return volumeMl * concentration! * perConc;
}

/// Volume in mL that holds [dose] (in [unit]) of a vial at [concentration]
/// (IU/mL when [iuConcentration], otherwise mg/mL). Inverse of
/// [doseForVolume]; null under the same conditions, or for a negative or
/// non-finite dose.
double? volumeForDose({
  required double dose,
  required double? concentration,
  required Unit unit,
  required bool iuConcentration,
}) {
  final perConc = _doseUnitsPerConcentrationUnit(unit, iuConcentration: iuConcentration);
  if (perConc == null || !_validConcentration(concentration)) return null;
  if (!dose.isFinite || dose < 0) return null;
  return dose / (concentration! * perConc);
}

bool _validConcentration(double? c) => c != null && c.isFinite && c > 0;

/// Units the dose selector offers for a compound whose library ("native")
/// unit is [nativeUnit]. IU-native compounds dose only in IU — their vial is
/// IU/mL, which has no mass equivalent; everything else is mass-dosed and may
/// switch between mg and mcg.
List<Unit> doseUnitOptions(Unit nativeUnit) =>
    nativeUnit == Unit.iu ? const [Unit.iu] : const [Unit.mg, Unit.mcg];

/// The amount + unit the wizard pre-fills for a new log of a compound.
///
/// Amount and unit always come from the same source, so a dose last logged as
/// 0.25 mg can never be re-offered as 0.25 mcg:
/// 1. the last log ([lastDose] in [lastUnit]) when that unit is still offered
///    for the compound (see [doseUnitOptions]);
/// 2. otherwise no amount, in the user's [preferredUnit] (set in the Compound
///    Editor) if offered, else [nativeUnit].
///
/// A last log in a unit that is no longer offered (legacy data — e.g. HCG once
/// logged as mg) is not pre-filled at all: it can't be converted to IU.
({double? dose, Unit unit}) resolveDosePrefill({
  required Unit nativeUnit,
  Unit? preferredUnit,
  double? lastDose,
  Unit? lastUnit,
}) {
  final options = doseUnitOptions(nativeUnit);
  if (lastDose != null &&
      lastDose.isFinite &&
      lastDose > 0 &&
      lastUnit != null &&
      options.contains(lastUnit)) {
    return (dose: lastDose, unit: lastUnit);
  }
  final unit = (preferredUnit != null && options.contains(preferredUnit))
      ? preferredUnit
      : nativeUnit;
  return (dose: null, unit: unit);
}
