import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/engine/dose_math.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/utils.dart';

void main() {
  group('doseForVolume', () {
    test('mg dose at mg/mL is volume × concentration', () {
      // Test E 250 mg/mL, 0.5 mL → 125 mg.
      expect(
        doseForVolume(volumeMl: 0.5, concentration: 250, unit: Unit.mg, iuConcentration: false),
        closeTo(125, 1e-9),
      );
    });

    test('mcg dose at mg/mL converts mg → mcg (A1 repro)', () {
      // BPC-157 at 2.5 mg/mL, 0.1 mL → 250 mcg (was logged as 0.25 mcg).
      expect(
        doseForVolume(volumeMl: 0.1, concentration: 2.5, unit: Unit.mcg, iuConcentration: false),
        closeTo(250, 1e-9),
      );
    });

    test('IU-native dose at IU/mL is volume × concentration', () {
      // HCG 5000 IU in 5 mL = 1000 IU/mL; 0.25 mL → 250 IU.
      expect(
        doseForVolume(volumeMl: 0.25, concentration: 1000, unit: Unit.iu, iuConcentration: true),
        closeTo(250, 1e-9),
      );
    });

    test('null, zero, negative or non-finite concentration → null', () {
      for (final conc in <double?>[null, 0, -2.5, double.nan, double.infinity]) {
        expect(
          doseForVolume(volumeMl: 0.1, concentration: conc, unit: Unit.mcg, iuConcentration: false),
          isNull,
          reason: 'concentration $conc',
        );
      }
    });

    test('negative or non-finite volume → null; zero volume → 0', () {
      expect(doseForVolume(volumeMl: -0.1, concentration: 2.5, unit: Unit.mg, iuConcentration: false), isNull);
      expect(doseForVolume(volumeMl: double.nan, concentration: 2.5, unit: Unit.mg, iuConcentration: false), isNull);
      expect(doseForVolume(volumeMl: 0, concentration: 2.5, unit: Unit.mg, iuConcentration: false), 0);
    });

    test('unit/concentration families that cannot be related → null', () {
      // Mass dose against an IU/mL vial, and IU dose against a mg/mL vial.
      expect(doseForVolume(volumeMl: 0.1, concentration: 1000, unit: Unit.mg, iuConcentration: true), isNull);
      expect(doseForVolume(volumeMl: 0.1, concentration: 1000, unit: Unit.mcg, iuConcentration: true), isNull);
      expect(doseForVolume(volumeMl: 0.1, concentration: 2.5, unit: Unit.iu, iuConcentration: false), isNull);
    });
  });

  group('volumeForDose', () {
    test('mg dose at mg/mL', () {
      expect(
        volumeForDose(dose: 125, concentration: 250, unit: Unit.mg, iuConcentration: false),
        closeTo(0.5, 1e-12),
      );
    });

    test('mcg dose at mg/mL converts mcg → mg (A1 repro)', () {
      // 250 mcg at 2.5 mg/mL → 0.10 mL (hint showed 100 mL).
      expect(
        volumeForDose(dose: 250, concentration: 2.5, unit: Unit.mcg, iuConcentration: false),
        closeTo(0.1, 1e-12),
      );
    });

    test('IU-native dose at IU/mL', () {
      expect(
        volumeForDose(dose: 250, concentration: 1000, unit: Unit.iu, iuConcentration: true),
        closeTo(0.25, 1e-12),
      );
    });

    test('round-trips with doseForVolume', () {
      for (final u in [Unit.mg, Unit.mcg]) {
        final ml = volumeForDose(dose: 300, concentration: 5, unit: u, iuConcentration: false)!;
        expect(
          doseForVolume(volumeMl: ml, concentration: 5, unit: u, iuConcentration: false),
          closeTo(300, 1e-9),
        );
      }
    });

    test('null / zero concentration, bad dose, or mismatched families → null', () {
      expect(volumeForDose(dose: 250, concentration: null, unit: Unit.mcg, iuConcentration: false), isNull);
      expect(volumeForDose(dose: 250, concentration: 0, unit: Unit.mcg, iuConcentration: false), isNull);
      expect(volumeForDose(dose: -1, concentration: 2.5, unit: Unit.mcg, iuConcentration: false), isNull);
      expect(volumeForDose(dose: double.infinity, concentration: 2.5, unit: Unit.mg, iuConcentration: false), isNull);
      expect(volumeForDose(dose: 250, concentration: 1000, unit: Unit.mcg, iuConcentration: true), isNull);
      expect(volumeForDose(dose: 250, concentration: 2.5, unit: Unit.iu, iuConcentration: false), isNull);
    });
  });

  group('U-100 syringe units', () {
    test('100 units = 1 mL', () {
      expect(syringeUnitsFromMl(1), 100);
      expect(syringeUnitsFromMl(0.1), closeTo(10, 1e-12));
      expect(mlFromSyringeUnits(10), closeTo(0.1, 1e-12));
      expect(mlFromSyringeUnits(0), 0);
    });

    test('syringe units feed doseForVolume like any other volume', () {
      // 10 units of BPC-157 at 2.5 mg/mL = 0.1 mL = 250 mcg.
      expect(
        doseForVolume(
          volumeMl: mlFromSyringeUnits(10),
          concentration: 2.5,
          unit: Unit.mcg,
          iuConcentration: false,
        ),
        closeTo(250, 1e-9),
      );
    });
  });

  group('doseUnitOptions', () {
    test('IU-native compounds only dose in IU; everything else in mg or mcg', () {
      expect(doseUnitOptions(Unit.iu), [Unit.iu]);
      expect(doseUnitOptions(Unit.mg), [Unit.mg, Unit.mcg]);
      expect(doseUnitOptions(Unit.mcg), [Unit.mg, Unit.mcg]);
    });
  });

  group('resolveDosePrefill', () {
    test('last log wins: amount and unit both come from it (A2 repro)', () {
      // Semaglutide (library mcg) last logged as 0.25 mg → 0.25 mg, not 0.25 mcg.
      final p = resolveDosePrefill(
        nativeUnit: Unit.mcg,
        preferredUnit: Unit.mcg,
        lastDose: 0.25,
        lastUnit: Unit.mg,
      );
      expect(p.dose, 0.25);
      expect(p.unit, Unit.mg);
    });

    test('no prior log: the user\'s preferred unit, without an amount', () {
      final p = resolveDosePrefill(nativeUnit: Unit.mcg, preferredUnit: Unit.mg);
      expect(p.dose, isNull);
      expect(p.unit, Unit.mg);
    });

    test('no prior log and no preference: the native unit', () {
      final p = resolveDosePrefill(nativeUnit: Unit.mcg);
      expect(p.dose, isNull);
      expect(p.unit, Unit.mcg);
    });

    test('a last log in a unit no longer offered is not re-offered under another unit', () {
      // Legacy HCG logged as 500 mg must not become 500 IU.
      final p = resolveDosePrefill(
        nativeUnit: Unit.iu,
        preferredUnit: Unit.mg, // legacy stored copy
        lastDose: 500,
        lastUnit: Unit.mg,
      );
      expect(p.dose, isNull);
      expect(p.unit, Unit.iu);

      // And the reverse: a mass peptide once logged in IU.
      final q = resolveDosePrefill(nativeUnit: Unit.mcg, lastDose: 10, lastUnit: Unit.iu);
      expect(q.dose, isNull);
      expect(q.unit, Unit.mcg);
    });

    test('a non-positive or non-finite last dose is not prefilled', () {
      for (final d in [0.0, -1.0, double.nan, double.infinity]) {
        final p = resolveDosePrefill(nativeUnit: Unit.mg, lastDose: d, lastUnit: Unit.mg);
        expect(p.dose, isNull, reason: 'lastDose $d');
        expect(p.unit, Unit.mg);
      }
    });

    test('IU-native with a matching IU log prefills it', () {
      final p = resolveDosePrefill(nativeUnit: Unit.iu, lastDose: 250, lastUnit: Unit.iu);
      expect(p.dose, 250);
      expect(p.unit, Unit.iu);
    });
  });

  group('formatAmount', () {
    test('whole numbers have no decimal point', () {
      expect(formatAmount(250), '250');
      expect(formatAmount(250.0), '250');
      expect(formatAmount(0), '0');
    });

    test('fractions keep their digits without trailing zeros', () {
      expect(formatAmount(0.25), '0.25');
      expect(formatAmount(5.5), '5.5');
      expect(formatAmount(0.1), '0.1');
      expect(formatAmount(125.5), '125.5');
    });

    test('N1: up to 6 decimals, so a stored dose round-trips through the field', () {
      expect(formatAmount(0.125), '0.125');
      expect(formatAmount(6.6666), '6.6666');
      expect(formatAmount(2.999), '2.999');
      expect(formatAmount(0.0625), '0.0625');
      expect(formatAmount(1 / 3), '0.333333');
      expect(formatAmount(2.9999999), '3'); // past 6 decimals rounds
      for (final v in [0.125, 6.6666, 0.0625, 12.345678, 1234.5, 0.000001]) {
        expect(parseFlexibleDouble(formatAmount(v)), v, reason: '$v');
      }
    });

    test('float noise is dropped', () {
      expect(formatAmount(0.1 + 0.2), '0.3');
      expect(formatAmount(0.1 * 2.5 * 1000), '250');
    });

    test('a "." decimal and no thousands grouping (parseFlexibleDouble rejects "5,000")', () {
      expect(formatAmount(5000), '5000');
      expect(formatAmount(12500.75), '12500.75');
      expect(parseFlexibleDouble(formatAmount(5000)), 5000);
    });

    test('negative zero reads as 0', () {
      expect(formatAmount(-0.0), '0');
      expect(formatAmount(-0.0000001), '0');
    });
  });
}
