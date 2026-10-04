import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/engine/injection_draft.dart';
import 'package:protolog_tracker/models.dart';

/// N5: a vial concentration over [maxConcentrationPerMl] is never stored.
void main() {
  final te = BASE_LIBRARY['Testosterone Enanthate']!;
  final now = DateTime(2026, 10, 4, 9);

  NewLog log(double? draft, List<CompoundDefinition> userCompounds) => buildNewLog(
        compound: te,
        userCompounds: userCompounds,
        dosage: 250,
        unit: Unit.mg,
        date: now,
        site: 'Vent. glute R',
        notes: '',
        concentrationDraft: draft,
        now: now,
      );

  test('isConcentrationTooHigh: only above the limit (infinity included)', () {
    expect(maxConcentrationPerMl, 100000);
    expect(isConcentrationTooHigh(null), isFalse);
    expect(isConcentrationTooHigh(0), isFalse);
    expect(isConcentrationTooHigh(250), isFalse);
    expect(isConcentrationTooHigh(100000), isFalse);
    expect(isConcentrationTooHigh(100000.5), isTrue);
    expect(isConcentrationTooHigh(1e308), isTrue);
    expect(isConcentrationTooHigh(double.infinity), isTrue);
  });

  test('an existing copy keeps its concentration', () {
    final copy = te.copyWith(id: 'te', concentration: 250);
    final r = log(1e9, [copy]);
    expect(r.compoundUpsert, isNull);
    expect(r.injection.snapshot.concentration, 250);
  });

  test('a first log adopts the compound without it', () {
    final r = log(1e9, const []);
    expect(r.compoundUpsert!.concentration, te.concentration);
    expect(r.injection.snapshot.concentration, te.concentration);
  });

  test('the limit itself is stored', () {
    final r = log(100000, [te.copyWith(id: 'te', concentration: 250)]);
    expect(r.compoundUpsert!.concentration, 100000);
  });
}
