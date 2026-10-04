import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/wizard/sticky_bar.dart';

void main() {
  group('unusualDoseMessage (G5)', () {
    final last = Injection(
      id: 'i',
      compoundId: 'te',
      date: DateTime(2026, 5, 1),
      dosage: 0.125,
      snapshot: BASE_LIBRARY['Testosterone Enanthate']!,
    );

    test('above: the factor, one decimal under 10, whole from 10', () {
      expect(unusualDoseMessage(3.2, last), "That's 3.2× your last dose (0.125 mg)");
      expect(unusualDoseMessage(4, last), "That's 4× your last dose (0.125 mg)");
      expect(unusualDoseMessage(12.4, last), "That's 12× your last dose (0.125 mg)");
      expect(unusualDoseMessage(1000, last), "That's 1000× your last dose (0.125 mg)");
    });

    test('below: the inverse factor, "less than"', () {
      expect(unusualDoseMessage(0.32, last), "That's 3.1× less than your last dose (0.125 mg)");
      expect(unusualDoseMessage(0.1, last), "That's 10× less than your last dose (0.125 mg)");
      expect(unusualDoseMessage(0.001, last.copyWithUnit(Unit.mcg)),
          "That's 1000× less than your last dose (0.125 mcg)");
    });
  });
}

extension on Injection {
  Injection copyWithUnit(Unit unit) => Injection(
        id: id,
        compoundId: compoundId,
        date: date,
        dosage: dosage,
        snapshot: snapshot.copyWith(unit: unit),
      );
}
