import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/engine/migrations.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/theme.dart';

// The pre-G7 library entry, as old data stored it.
const _oldAi = CompoundDefinition(
  id: 'Anastrazole',
  base: 'Anastrazole',
  ester: 'None',
  type: CompoundType.ancillary,
  graphType: GraphType.activeWindow,
  halfLife: 2.1,
  defaultHalfLife: 2.1,
  timeToPeak: 0.5,
  ratio: 1,
  unit: Unit.mg,
  colorValue: 0xFF94A3B8,
);

const _testE = CompoundDefinition(
  id: 'test_e',
  base: 'Testosterone',
  ester: 'Enanthate',
  type: CompoundType.steroid,
  graphType: GraphType.curve,
  halfLife: 4.5,
  timeToPeak: 1.5,
  ratio: 0.72,
  unit: Unit.mg,
  colorValue: 0xFF5DC59C,
);

Injection _log(String id, CompoundDefinition snap, {String? compoundId}) => Injection(
      id: id,
      compoundId: compoundId ?? snap.id,
      date: DateTime(2026, 6, 1, 8),
      dosage: 0.5,
      snapshot: snap,
    );

Reminder _rem(String base, {String ester = 'None'}) => Reminder(
      id: 'r-$base',
      compoundBase: base,
      compoundEster: ester,
      intervalDays: 3.5,
      hour: 8,
      minute: 0,
      enabled: true,
      notificationSeed: 42,
    );

void main() {
  test('the library spells it Anastrozole, which picks up the AI palette color (G7)', () {
    expect(BASE_LIBRARY.containsKey('Anastrazole'), isFalse);
    final ai = BASE_LIBRARY['Anastrozole']!;
    expect((ai.id, ai.base), ('Anastrozole', 'Anastrozole'));
    expect(AppTheme.compoundColor(ai.base), isNotNull);
  });

  group('G7: Anastrazole → Anastrozole', () {
    test('renames the base and the library id everywhere it was stored', () {
      final custom = _oldAi.copyWith(id: '1690000000', isCustom: true, halfLife: 2.0);
      final res = migrateRecords(
        injections: [_log('i1', _oldAi), _log('i2', custom)],
        compounds: [custom],
        reminders: [_rem('Anastrazole'), _rem('Testosterone', ester: 'Enanthate')],
      );

      expect(res.compounds.single.base, 'Anastrozole');
      expect(res.compounds.single.id, '1690000000', reason: 'only the library id is renamed');
      final (i1, i2) = (res.injections[0], res.injections[1]);
      expect((i1.compoundId, i1.snapshot.id, i1.snapshot.base),
          ('Anastrozole', 'Anastrozole', 'Anastrozole'));
      expect((i2.compoundId, i2.snapshot.base), ('1690000000', 'Anastrozole'));
      expect(i2.snapshot.halfLife, 2.0, reason: 'the snapshot keeps its frozen PK');
      expect(res.reminders.map((r) => r.compoundBase), ['Anastrozole', 'Testosterone']);
      expect(res.reminders.first.notificationSeed, 42);
      expect((res.injectionsChanged, res.compoundsChanged, res.remindersChanged),
          (true, true, true));
    });

    test('a second run changes nothing', () {
      final once = migrateRecords(
        injections: [_log('i1', _oldAi)],
        compounds: [_oldAi],
        reminders: [_rem('Anastrazole')],
      );
      final twice = migrateRecords(
        injections: once.injections,
        compounds: once.compounds,
        reminders: once.reminders,
      );
      expect(twice.changed, isFalse);
      expect(identical(twice.injections.single, once.injections.single), isTrue);
    });
  });

  test('current data comes back as the same records, unflagged', () {
    final injections = [_log('i1', _testE)];
    final compounds = [_testE];
    final reminders = [_rem('Testosterone', ester: 'Enanthate')];
    final res = migrateRecords(
        injections: injections, compounds: compounds, reminders: reminders);
    expect(res.changed, isFalse);
    expect(identical(res.injections.single, injections.single), isTrue);
    expect(identical(res.compounds.single, compounds.single), isTrue);
    expect(identical(res.reminders.single, reminders.single), isTrue);
    // Fresh, growable lists.
    expect(() => res.injections.add(_log('x', _testE)), returnsNormally);
    expect(identical(res.injections, injections), isFalse);
  });

  group("legacy 'temp' ids", () {
    test('a stored library override takes its library id; its logs follow', () {
      final override = BASE_LIBRARY['Testosterone Cypionate']!.copyWith(id: 'temp', halfLife: 6);
      final res = migrateRecords(
        injections: [_log('i1', override)],
        compounds: [override],
        reminders: const [],
      );
      expect(res.compounds.single.id, 'Testosterone Cypionate');
      expect(res.compounds.single.halfLife, 6);
      expect(res.injections.single.compoundId, 'Testosterone Cypionate');
    });

    test('a log links by base+ester to the user compound, else the library entry', () {
      final cyp = BASE_LIBRARY['Testosterone Cypionate']!;
      final custom = const CompoundDefinition(
        id: 'my-pep',
        base: 'MyPeptide',
        ester: 'None',
        type: CompoundType.peptide,
        graphType: GraphType.event,
        halfLife: 0.5,
        timeToPeak: 0.1,
        ratio: 1,
        unit: Unit.mcg,
        colorValue: 0xFF000000,
        isCustom: true,
      );
      final unknown = custom.copyWith(base: 'Gone');
      final res = migrateRecords(
        injections: [
          _log('user', _testE, compoundId: 'temp'),
          _log('lib', cyp, compoundId: 'temp'),
          _log('none', unknown, compoundId: 'temp'),
          _log('mine', custom, compoundId: 'temp'),
        ],
        compounds: [_testE, custom],
        reminders: const [],
      );
      expect(res.injections.map((i) => i.compoundId),
          ['test_e', 'Testosterone Cypionate', 'temp', 'my-pep']);
      expect(res.injectionsChanged, isTrue);
      expect(res.compoundsChanged, isFalse);
    });
  });

  test('B6: duplicate compounds collapse to the later one and logs relink', () {
    final adopted = _testE.copyWith(id: '1700000000', concentration: 250);
    final restored = _testE.copyWith(halfLife: 5);
    final res = migrateRecords(
      injections: [_log('a', adopted), _log('b', restored)],
      compounds: [adopted, restored],
      reminders: const [],
    );
    expect(res.compounds, hasLength(1));
    expect((res.compounds.single.id, res.compounds.single.halfLife), ('test_e', 5));
    expect(res.compounds.single.concentration, 250, reason: 'vial strength carried over');
    expect(res.injections.map((i) => i.compoundId), ['test_e', 'test_e']);
    expect((res.injectionsChanged, res.compoundsChanged), (true, true));
  });
}
