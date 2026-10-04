import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/engine/injection_draft.dart';
import 'package:protolog_tracker/models.dart';

void main() {
  final testE = BASE_LIBRARY['Testosterone Enanthate']!;
  final sema = BASE_LIBRARY['Semaglutide']!; // library unit: mcg
  final hcg = BASE_LIBRARY['HCG']!; // peptide, IU-native
  final sust = BASE_LIBRARY['Sustanon 250']!; // library concentration 250
  const custom = CompoundDefinition(
    id: 'c1',
    base: 'Kisspeptin',
    ester: 'None',
    type: CompoundType.peptide,
    graphType: GraphType.event,
    halfLife: 0.2,
    timeToPeak: 0.05,
    ratio: 1,
    unit: Unit.mcg,
    colorValue: 0xFF123456,
    isCustom: true,
    concentration: 2,
  );
  final now = DateTime(2026, 5, 18, 9, 30, 15, 123);
  final at = DateTime(2026, 5, 18, 8, 0);

  Injection log(CompoundDefinition snap, double dosage, DateTime date, {String? site, String id = 'i'}) =>
      Injection(id: id, compoundId: snap.id, date: date, dosage: dosage, snapshot: snap, site: site);

  group('resolveDraftCompound', () {
    test('built-in without a user copy is the library entry', () {
      final r = resolveDraftCompound(picked: testE, userCompounds: const []);
      expect(r.compound.base, 'Testosterone');
      expect(r.compound.halfLife, 4.5);
      expect(r.nativeUnit, Unit.mg);
      expect(r.preferredUnit, isNull);
    });

    test('user copy supplies PK, concentration and preferred unit; library keeps type/unit', () {
      // A stale copy: wrong type (HCG used to be an ancillary) and a mg unit.
      final copy = hcg.copyWith(
          id: 'h', type: CompoundType.ancillary, unit: Unit.mg, halfLife: 2.0, concentration: 1000);
      final r = resolveDraftCompound(picked: hcg, userCompounds: [copy]);
      expect(r.compound.id, 'h');
      expect(r.compound.halfLife, 2.0);
      expect(r.compound.concentration, 1000);
      expect(r.compound.type, CompoundType.peptide);
      expect(r.compound.unit, Unit.iu);
      expect(r.nativeUnit, Unit.iu);
      expect(r.preferredUnit, Unit.mg);
    });

    test('a copy without a concentration falls back to the library one', () {
      final r = resolveDraftCompound(picked: sust, userCompounds: [sust.copyWith(id: 's')]);
      expect(r.compound.concentration, 250);
    });

    test('B6: of duplicate user copies, the one the Library edits (the last) wins', () {
      final r = resolveDraftCompound(
        picked: testE,
        userCompounds: [testE.copyWith(id: 'a', halfLife: 5), testE.copyWith(id: 'b', halfLife: 6)],
      );
      expect(r.compound.id, 'b');
      expect(r.compound.halfLife, 6);
    });

    test('a true custom is its own canon', () {
      final r = resolveDraftCompound(picked: custom, userCompounds: const [custom]);
      expect(r.compound.id, 'c1');
      expect(r.compound.type, CompoundType.peptide);
      expect(r.nativeUnit, Unit.mcg);
      expect(r.preferredUnit, Unit.mcg);
    });
  });

  group('prefillNewLog', () {
    test('no history: no amount, native unit, route default site', () {
      final p = prefillNewLog(picked: testE, userCompounds: const [], injections: const []);
      expect(p.dose, isNull);
      expect(p.unit, Unit.mg);
      expect(p.site, defaultIntramuscularSite);
      expect(p.lastLog, isNull);

      final q = prefillNewLog(picked: sema, userCompounds: const [], injections: const []);
      expect(q.unit, Unit.mcg);
      expect(q.site, defaultSubcutaneousSite);
    });

    test('last log supplies amount + unit together; site comes from the same base', () {
      final older = log(sema.copyWith(unit: Unit.mcg), 250, DateTime(2026, 5, 1), site: 'Glute L', id: 'old');
      final newer = log(sema.copyWith(unit: Unit.mg), 0.25, DateTime(2026, 5, 10), id: 'new');
      final p = prefillNewLog(picked: sema, userCompounds: const [], injections: [older, newer]);
      expect(p.lastLog!.id, 'new');
      expect(p.dose, 0.25);
      expect(p.unit, Unit.mg);
      expect(p.site, 'Glute L'); // newest log *with* a site
    });

    test('site is shared across esters of a base, dose is not', () {
      final cyp = BASE_LIBRARY['Testosterone Cypionate']!;
      final p = prefillNewLog(
        picked: testE,
        userCompounds: const [],
        injections: [log(cyp, 100, DateTime(2026, 5, 1), site: 'Delt R')],
      );
      expect(p.site, 'Delt R');
      expect(p.dose, isNull);
      expect(p.lastLog, isNull);
    });

    test('no prior log: the user copy\'s preferred unit, without an amount', () {
      final p = prefillNewLog(
          picked: sema, userCompounds: [sema.copyWith(id: 's', unit: Unit.mg)], injections: const []);
      expect(p.dose, isNull);
      expect(p.unit, Unit.mg);
    });
  });

  test('prefillEdit uses the frozen snapshot and the log\'s own values', () {
    final snap = testE.copyWith(id: 'te', halfLife: 9, concentration: 200);
    final inj = Injection(
        id: 'e1', compoundId: 'te', date: at, dosage: 0.125, snapshot: snap, site: 'Quad L');
    final p = prefillEdit(inj);
    expect(p.compound, same(snap));
    expect(p.dose, 0.125);
    expect(p.unit, Unit.mg);
    expect(p.site, 'Quad L');
    expect(p.lastLog, isNull);
    // A log without a site falls back to the route default.
    expect(prefillEdit(log(hcg, 250, at)).site, defaultSubcutaneousSite);
  });

  group('linkedReminderFor', () {
    Reminder reminder(String base, String ester, {bool enabled = true}) => Reminder(
        id: '$base$ester', compoundBase: base, compoundEster: ester,
        intervalDays: 3.5, hour: 8, minute: 0, enabled: enabled);

    test('first enabled reminder with the same base+ester', () {
      final rs = [
        reminder('Testosterone', 'Enanthate', enabled: false),
        reminder('Testosterone', 'Cypionate'),
        reminder('Testosterone', 'Enanthate'),
      ];
      expect(linkedReminderFor(compound: testE, reminders: rs), same(rs[2]));
      expect(linkedReminderFor(compound: null, reminders: rs), isNull);
      expect(linkedReminderFor(compound: sema, reminders: rs), isNull);
    });
  });

  group('defaultLogTime', () {
    test('rounds now to the nearest 5 minutes', () {
      expect(defaultLogTime(now: DateTime(2026, 5, 18, 10, 2, 59)), DateTime(2026, 5, 18, 10, 0));
      expect(defaultLogTime(now: DateTime(2026, 5, 18, 10, 3)), DateTime(2026, 5, 18, 10, 5));
      expect(defaultLogTime(now: DateTime(2026, 5, 18, 10, 58)), DateTime(2026, 5, 18, 11, 0));
    });

    test('B24: 23:58 rounds to midnight of the next day, not of today', () {
      expect(defaultLogTime(now: DateTime(2026, 5, 18, 23, 58)), DateTime(2026, 5, 19));
      expect(defaultLogTime(now: DateTime(2026, 12, 31, 23, 59)), DateTime(2027, 1, 1));
      // The host pre-selecting today (Calendar's default) behaves the same.
      expect(defaultLogTime(now: DateTime(2026, 5, 18, 23, 58), day: DateTime(2026, 5, 18, 9)),
          DateTime(2026, 5, 19));
    });

    test('another pre-selected day gets the rounded clock time on that day', () {
      expect(defaultLogTime(now: DateTime(2026, 5, 18, 9, 31), day: DateTime(2026, 5, 10)),
          DateTime(2026, 5, 10, 9, 30));
      expect(defaultLogTime(now: DateTime(2026, 5, 18, 9, 31), day: DateTime(2026, 6, 2, 23, 59)),
          DateTime(2026, 6, 2, 9, 30));
    });
  });

  group('logDatePickerRange (B28)', () {
    final now = DateTime(2026, 5, 18, 9, 30);

    test('from 2000 to a year ahead for a current date', () {
      final r = logDatePickerRange(current: DateTime(2026, 5, 18), now: now);
      expect(r.first, DateTime(2000));
      expect(r.last, DateTime(2027, 5, 18));
    });

    test('stretches to include an older or later current value', () {
      final old = logDatePickerRange(current: DateTime(1998, 3, 4, 17, 15), now: now);
      expect(old.first, DateTime(1998, 3, 4));
      expect(old.last, DateTime(2027, 5, 18));
      final late = logDatePickerRange(current: DateTime(2031, 1, 2, 8), now: now);
      expect(late.first, DateTime(2000));
      expect(late.last, DateTime(2031, 1, 2));
    });

    test('keeps working past 2030', () {
      final r = logDatePickerRange(current: DateTime(2031, 6, 1), now: DateTime(2031, 6, 1, 12));
      expect(r.last, DateTime(2032, 5, 31));
    });
  });

  group('futureDaysAhead (B28)', () {
    final now = DateTime(2026, 5, 18, 9, 30);

    test('null up to a day ahead, and for the past', () {
      expect(futureDaysAhead(now.subtract(const Duration(days: 3)), now: now), isNull);
      expect(futureDaysAhead(now, now: now), isNull);
      expect(futureDaysAhead(DateTime(2026, 5, 19, 8), now: now), isNull);
      expect(futureDaysAhead(DateTime(2026, 5, 19, 9, 30), now: now), isNull); // exactly 24 h
    });

    test('calendar days ahead once more than a day out', () {
      expect(futureDaysAhead(DateTime(2026, 5, 19, 10), now: now), 1);
      expect(futureDaysAhead(DateTime(2026, 5, 21, 8), now: now), 3);
      expect(futureDaysAhead(DateTime(2027, 5, 18), now: now), 365);
    });
  });

  group('unusualDoseRatio (G5)', () {
    final last = log(sema.copyWith(unit: Unit.mcg), 250, at);

    test('null without a last log, or within 3× either way', () {
      expect(unusualDoseRatio(dose: 2500, unit: Unit.mcg, last: null), isNull);
      for (final d in [250.0, 100.0, 84.0, 700.0, 750.0]) {
        expect(unusualDoseRatio(dose: d, unit: Unit.mcg, last: last), isNull, reason: '$d');
      }
    });

    test('the ratio to the last dose beyond 3× or under ⅓', () {
      expect(unusualDoseRatio(dose: 2500, unit: Unit.mcg, last: last), 10);
      expect(unusualDoseRatio(dose: 800, unit: Unit.mcg, last: last), closeTo(3.2, 1e-9));
      expect(unusualDoseRatio(dose: 25, unit: Unit.mcg, last: last), closeTo(0.1, 1e-9));
      expect(unusualDoseRatio(dose: 80, unit: Unit.mcg, last: last), closeTo(0.32, 1e-9));
    });

    test('mg and mcg compare as mass — a unit slip is the case that matters', () {
      expect(unusualDoseRatio(dose: 250, unit: Unit.mg, last: last), 1000);
      expect(unusualDoseRatio(dose: 0.25, unit: Unit.mg, last: last), isNull); // = 250 mcg
      final mgLast = log(testE, 250, at);
      expect(unusualDoseRatio(dose: 250, unit: Unit.mcg, last: mgLast), closeTo(0.001, 1e-12));
    });

    test('IU and mass can\'t be compared; bad numbers never warn', () {
      expect(unusualDoseRatio(dose: 5000, unit: Unit.iu, last: last), isNull);
      expect(unusualDoseRatio(dose: 0, unit: Unit.mcg, last: last), isNull);
      expect(unusualDoseRatio(dose: double.nan, unit: Unit.mcg, last: last), isNull);
      expect(unusualDoseRatio(dose: 250, unit: Unit.mcg, last: log(sema, 0, at)), isNull);
    });
  });

  test('logDateTime combines a day with a clock time', () {
    expect(logDateTime(DateTime(2026, 5, 18, 23, 59), hour: 8, minute: 5), DateTime(2026, 5, 18, 8, 5));
  });

  test('logSite / logNotes', () {
    expect(logSite(CompoundType.steroid, 'Delt L'), 'Delt L');
    expect(logSite(CompoundType.peptide, ''), isNull);
    expect(logSite(CompoundType.oral, 'Delt L'), isNull);
    expect(logSite(CompoundType.ancillary, 'Delt L'), isNull);
    expect(logNotes('  hi  '), 'hi');
    expect(logNotes('   '), isNull);
  });

  group('buildNewLog', () {
    test('first log of a built-in adopts it as a user copy under its library key (B6)', () {
      final drafted = resolveDraftCompound(picked: testE, userCompounds: const []).compound;
      final r = buildNewLog(
        compound: drafted,
        userCompounds: const [],
        dosage: 250,
        unit: Unit.mg,
        date: at,
        site: 'Delt L',
        notes: ' first ',
        concentrationDraft: null,
        now: now,
      );
      final adopted = r.compoundUpsert!;
      expect(adopted.id, 'Testosterone Enanthate'); // the BASE_LIBRARY key
      expect(adopted.base, 'Testosterone');
      expect(adopted.ester, 'Enanthate');
      expect(adopted.type, CompoundType.steroid);
      expect(adopted.graphType, testE.graphType);
      expect(adopted.halfLife, 4.5);
      expect(adopted.defaultHalfLife, 4.5);
      expect(adopted.timeToPeak, testE.timeToPeak);
      expect(adopted.ratio, testE.ratio);
      expect(adopted.colorValue, testE.colorValue);
      expect(adopted.isCustom, isFalse);
      expect(adopted.concentration, isNull);

      final inj = r.injection;
      expect(inj.id, now.toIso8601String());
      expect(inj.compoundId, adopted.id);
      expect(inj.date, at);
      expect(inj.dosage, 250);
      expect(inj.site, 'Delt L');
      expect(inj.notes, 'first');
      expect(inj.snapshot.id, adopted.id);
      expect(inj.snapshot.halfLife, 4.5);
    });

    test('adoption bakes in a concentration from the wizard, else the compound\'s', () {
      final withDraft = buildNewLog(
        compound: testE, userCompounds: const [], dosage: 1, unit: Unit.mg, date: at,
        site: '', notes: '', concentrationDraft: 300, now: now,
      );
      expect(withDraft.compoundUpsert!.concentration, 300);
      final fromLibrary = buildNewLog(
        compound: sust, userCompounds: const [], dosage: 1, unit: Unit.mg, date: at,
        site: '', notes: '', concentrationDraft: null, now: now,
      );
      expect(fromLibrary.compoundUpsert!.concentration, 250);
    });

    test('existing user copy: log is filed under it, nothing written back', () {
      final copy = testE.copyWith(id: 'te', halfLife: 5.5, concentration: 250);
      final r = buildNewLog(
        compound: copy, userCompounds: [copy], dosage: 125, unit: Unit.mg, date: at,
        site: 'Quad R', notes: '', concentrationDraft: 250, now: now,
      );
      expect(r.compoundUpsert, isNull);
      expect(r.injection.compoundId, 'te');
      expect(r.injection.snapshot.halfLife, 5.5);
      expect(r.injection.snapshot.concentration, 250);
      expect(r.injection.notes, isNull);
    });

    test('existing user copy: a changed concentration is written back', () {
      final copy = testE.copyWith(id: 'te', concentration: 200);
      final r = buildNewLog(
        compound: copy, userCompounds: [copy], dosage: 125, unit: Unit.mg, date: at,
        site: 'Quad R', notes: '', concentrationDraft: 250, now: now,
      );
      expect(r.compoundUpsert!.id, 'te');
      expect(r.compoundUpsert!.concentration, 250);
      expect(r.injection.snapshot.concentration, 250);
      // A cleared draft (null) never erases the stored concentration.
      final kept = buildNewLog(
        compound: copy, userCompounds: [copy], dosage: 125, unit: Unit.mg, date: at,
        site: '', notes: '', concentrationDraft: null, now: now,
      );
      expect(kept.compoundUpsert, isNull);
      expect(kept.injection.snapshot.concentration, 200);
    });

    test('the dose unit goes into the snapshot only, never the compound', () {
      final copy = sema.copyWith(id: 's');
      final r = buildNewLog(
        compound: copy, userCompounds: [copy], dosage: 0.5, unit: Unit.mg, date: at,
        site: '', notes: '', concentrationDraft: null, now: now,
      );
      expect(r.injection.snapshot.unit, Unit.mg);
      expect(r.compoundUpsert, isNull);

      final adopted = buildNewLog(
        compound: sema, userCompounds: const [], dosage: 0.5, unit: Unit.mg, date: at,
        site: '', notes: '', concentrationDraft: 2.5, now: now,
      );
      expect(adopted.injection.snapshot.unit, Unit.mg);
      expect(adopted.compoundUpsert!.unit, Unit.mcg);
      expect(adopted.compoundUpsert!.concentration, 2.5);
    });

    test('true custom: filed under the stored custom, stays custom', () {
      final r = buildNewLog(
        compound: custom, userCompounds: const [custom], dosage: 100, unit: Unit.mcg, date: at,
        site: 'Abdominal L', notes: '', concentrationDraft: 2, now: now,
      );
      expect(r.compoundUpsert, isNull);
      expect(r.injection.compoundId, 'c1');
      expect(r.injection.snapshot.isCustom, isTrue);
      expect(r.injection.site, 'Abdominal L');
    });

    test('a custom not yet stored is materialized with its flags', () {
      final r = buildNewLog(
        compound: custom, userCompounds: const [], dosage: 100, unit: Unit.mcg, date: at,
        site: '', notes: '', concentrationDraft: null, now: now,
      );
      expect(r.compoundUpsert!.isCustom, isTrue);
      expect(r.compoundUpsert!.concentration, 2);
      expect(r.injection.site, isNull);
    });

    test('pill-form compounds never store a site', () {
      final oxa = BASE_LIBRARY['Oxandrolone']!;
      final r = buildNewLog(
        compound: oxa, userCompounds: const [], dosage: 20, unit: Unit.mg, date: at,
        site: 'Vent. glute R', notes: '', concentrationDraft: null, now: now,
      );
      expect(r.injection.site, isNull);
    });
  });

  group('buildNewLog — compound identity (B6)', () {
    NewLog logFirst(CompoundDefinition c, List<CompoundDefinition> users, {DateTime? at2}) =>
        buildNewLog(
          compound: c, userCompounds: users, dosage: 1, unit: c.unit, date: at,
          site: '', notes: '', concentrationDraft: null, now: at2 ?? now,
        );

    test('two installs adopt a built-in under the same id, whenever they log it', () {
      final a = logFirst(testE, const []);
      final b = logFirst(testE, const [], at2: DateTime(2027, 1, 1));
      expect(a.compoundUpsert!.id, b.compoundUpsert!.id);
      expect(logFirst(sust, const []).compoundUpsert!.id, 'Sustanon 250');
    });

    test('a legacy user compound already holding the library id: timestamp id', () {
      // E.g. a built-in override renamed into a custom keeps its old id.
      final legacy = testE.copyWith(id: 'Testosterone Enanthate', base: 'Renamed', isCustom: true);
      final r = logFirst(testE, [legacy]);
      expect(r.compoundUpsert!.id, now.millisecondsSinceEpoch.toString());
      expect(r.compoundUpsert!.base, 'Testosterone');
    });

    test('an existing copy is matched by base+ester key; the last duplicate wins', () {
      final first = testE.copyWith(id: 'a', halfLife: 5);
      final last = testE.copyWith(id: 'b', halfLife: 6);
      final r = logFirst(testE, [first, last]);
      expect(r.compoundUpsert, isNull);
      expect(r.injection.compoundId, 'b');
      expect(r.injection.snapshot.halfLife, 6);
    });

    test('a true custom not yet stored keeps its own id when usable', () {
      expect(logFirst(custom, const []).compoundUpsert!.id, 'c1');
      final ts = now.millisecondsSinceEpoch.toString();
      expect(logFirst(custom.copyWith(id: 'temp'), const []).compoundUpsert!.id, ts);
      expect(logFirst(custom.copyWith(id: ''), const []).compoundUpsert!.id, ts);
      final other = testE.copyWith(id: 'c1', halfLife: 9); // id taken by another compound
      expect(logFirst(custom, [other]).compoundUpsert!.id, ts);
    });
  });

  group('buildEditedLog', () {
    final snap = testE.copyWith(id: 'te', halfLife: 9, concentration: 200);
    final original = Injection(
      id: 'e1', compoundId: 'te', date: DateTime(2026, 5, 1, 17, 15), dosage: 250,
      snapshot: snap, site: 'Vent. glute R', notes: 'old',
    );

    test('keeps id, compoundId and the frozen snapshot; replaces editable fields', () {
      final e = buildEditedLog(
        original: original, dosage: 300.5, unit: Unit.mg, date: at, site: 'Delt L', notes: ' new ',
      );
      expect(e.id, 'e1');
      expect(e.compoundId, 'te');
      expect(e.snapshot.id, 'te');
      expect(e.snapshot.halfLife, 9);
      expect(e.snapshot.concentration, 200);
      expect(e.dosage, 300.5);
      expect(e.date, at);
      expect(e.site, 'Delt L');
      expect(e.notes, 'new');
    });

    test('the unit follows the selector; blank site/notes clear', () {
      final e = buildEditedLog(original: original, dosage: 1, unit: Unit.mcg, date: at, site: '', notes: '');
      expect(e.snapshot.unit, Unit.mcg);
      expect(e.snapshot.halfLife, 9);
      expect(e.site, isNull);
      expect(e.notes, isNull);
    });
  });
}
