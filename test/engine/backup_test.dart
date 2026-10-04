import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/engine/backup.dart';

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

Injection _inj(String id, {double mg = 150}) => Injection(
      id: id,
      compoundId: 'test_e',
      date: DateTime(2026, 6, 1, 8, 30),
      dosage: mg,
      snapshot: _testE,
      site: 'Delt L',
      notes: 'ok',
    );

Reminder _rem(String id, {double interval = 3.5}) => Reminder(
      id: id,
      compoundBase: 'Testosterone',
      compoundEster: 'Enanthate',
      intervalDays: interval,
      hour: 8,
      minute: 0,
      enabled: true,
      anchorDate: DateTime(2026, 7, 14, 8, 0),
      notificationSeed: 42,
    );

void main() {
  group('encode/decode round-trip', () {
    test('preserves all five collections', () {
      final json = encodeBackup(
        injections: [_inj('i1')],
        compounds: [_testE],
        reminders: [_rem('r1')],
        customSitesIM: ['Quad sweep L'],
        customSitesSubQ: ['Love handle R'],
      );
      final data = decodeBackup(json);
      expect(data, isNotNull);
      expect(data!.injections, hasLength(1));
      expect(data.injections.first.site, 'Delt L');
      expect(data.compounds.single.halfLife, 4.5);
      expect(data.reminders.single.notificationSeed, 42);
      expect(data.customSitesIM, ['Quad sweep L']);
      expect(data.customSitesSubQ, ['Love handle R']);
    });

    test('rejects non-JSON garbage', () {
      expect(decodeBackup('definitely not json'), isNull);
    });

    test('rejects foreign JSON without the protolog envelope', () {
      expect(decodeBackup('{"foo": 1}'), isNull);
      expect(decodeBackup('[1,2,3]'), isNull);
    });
  });

  group('mergeBackup', () {
    test('appends only injections with unseen ids and counts them', () {
      final incoming = decodeBackup(encodeBackup(
        injections: [_inj('dup'), _inj('new1'), _inj('new2')],
        compounds: [],
        reminders: [],
        customSitesIM: [],
        customSitesSubQ: [],
      ))!;
      final res = mergeBackup(
        injections: [_inj('dup')],
        compounds: [_testE],
        reminders: [],
        customSitesIM: [],
        customSitesSubQ: [],
        incoming: incoming,
      );
      expect(res.injections, hasLength(3));
      expect(res.newInjections, 2);
    });

    test('upserts compounds and reminders by id', () {
      final edited = _testE.copyWith(halfLife: 6.0);
      final incoming = decodeBackup(encodeBackup(
        injections: [],
        compounds: [edited],
        reminders: [_rem('r-new')],
        customSitesIM: [],
        customSitesSubQ: [],
      ))!;
      final res = mergeBackup(
        injections: [],
        compounds: [_testE],
        reminders: [_rem('r-old')],
        customSitesIM: [],
        customSitesSubQ: [],
        incoming: incoming,
      );
      expect(res.compounds.single.halfLife, 6.0); // incoming wins on same id
      expect(res.reminders.map((r) => r.id).toSet(), {'r-old', 'r-new'});
      expect(res.changedCompounds, 1);
      expect(res.changedReminders, 1);
    });

    test('identical incoming state is a no-op with zero counts', () {
      final incoming = decodeBackup(encodeBackup(
        injections: [_inj('i1')],
        compounds: [_testE],
        reminders: [_rem('r1')],
        customSitesIM: ['Quad sweep L'],
        customSitesSubQ: [],
      ))!;
      final res = mergeBackup(
        injections: [_inj('i1')],
        compounds: [_testE],
        reminders: [_rem('r1')],
        customSitesIM: ['Quad sweep L'],
        customSitesSubQ: [],
        incoming: incoming,
      );
      expect(res.newInjections, 0);
      expect(res.changedCompounds, 0);
      expect(res.changedReminders, 0);
      expect(res.customSitesIM, ['Quad sweep L']);
    });

    test('carries bloodwork entries and merges them additively by id', () {
      final b1 = BloodworkEntry(
        id: 'bw1', date: DateTime(2026, 7, 1), marker: 'Total T',
        value: 38.5, unit: 'nmol/L',
      );
      final b2 = BloodworkEntry(
        id: 'bw2', date: DateTime(2026, 7, 8), marker: 'E2',
        value: 120, unit: 'pmol/L',
      );
      final incoming = decodeBackup(encodeBackup(
        injections: [],
        compounds: [],
        reminders: [],
        customSitesIM: [],
        customSitesSubQ: [],
        bloodwork: [b1, b2],
      ))!;
      expect(incoming.bloodwork, hasLength(2));

      final res = mergeBackup(
        injections: [],
        compounds: [],
        reminders: [],
        customSitesIM: [],
        customSitesSubQ: [],
        bloodwork: [b1], // bw1 already present
        incoming: incoming,
      );
      expect(res.bloodwork.map((b) => b.id).toSet(), {'bw1', 'bw2'});
      expect(res.newBloodwork, 1);
    });

    test('old backups without a bloodwork key decode with an empty list', () {
      const legacy = '{"app":"protolog","schemaVersion":1,'
          '"injections":[],"compounds":[],"reminders":[],'
          '"customSitesIM":[],"customSitesSubQ":[]}';
      expect(decodeBackup(legacy), isNotNull);
      expect(decodeBackup(legacy)!.bloodwork, isEmpty);
    });

    test('unions custom sites without duplicates', () {
      final incoming = decodeBackup(encodeBackup(
        injections: [],
        compounds: [],
        reminders: [],
        customSitesIM: ['Quad sweep L', 'Pec R'],
        customSitesSubQ: ['Navel L'],
      ))!;
      final res = mergeBackup(
        injections: [],
        compounds: [],
        reminders: [],
        customSitesIM: ['Quad sweep L'],
        customSitesSubQ: [],
        incoming: incoming,
      );
      expect(res.customSitesIM, ['Quad sweep L', 'Pec R']);
      expect(res.customSitesSubQ, ['Navel L']);
    });
  });

  group('decodeBackup drops invalid records (A7)', () {
    String envelope(Map<String, Object?> sections) => jsonEncode({
          'app': 'protolog',
          'schemaVersion': 1,
          'injections': [],
          'compounds': [],
          'reminders': [],
          'customSitesIM': [],
          'customSitesSubQ': [],
          ...sections,
        });
    Map<String, dynamic> json(Reminder r) => jsonDecode(jsonEncode(r.toJson()));

    test('a clean file skips nothing', () {
      final data = decodeBackup(encodeBackup(
        injections: [_inj('i1')],
        compounds: [_testE],
        reminders: [_rem('r1')],
        customSitesIM: ['Delt L'],
        customSitesSubQ: [],
      ))!;
      expect(data.skipped, 0);
    });

    test('a weekday-0 reminder is dropped (its slot loop hung every launch)', () {
      final bad = json(_rem('bad'))
        ..['scheduleMode'] = 'custom'
        ..['customSlots'] = [
          {'weekday': 0, 'hour': 8, 'minute': 0},
        ];
      final data = decodeBackup(envelope({
        'reminders': [_rem('ok').toJson(), bad],
      }))!;
      expect(data.reminders.map((r) => r.id), ['ok']);
      expect(data.skipped, 1);
    });

    test('interval reminders with a zero, negative or absurd interval are dropped', () {
      final data = decodeBackup(envelope({
        'reminders': [
          json(_rem('zero'))..['intervalDays'] = 0,
          json(_rem('neg'))..['intervalDays'] = -3.5,
          json(_rem('huge'))..['intervalDays'] = 1e6,
          json(_rem('hour'))..['hour'] = 24,
          _rem('ok').toJson(),
        ],
      }))!;
      expect(data.reminders.map((r) => r.id), ['ok']);
      expect(data.skipped, 4);
    });

    test('records with non-finite numbers are dropped, so later saves keep working', () {
      // jsonEncode can't write Infinity, so splice 1e999 into the text.
      final text = encodeBackup(
        injections: [_inj('inf', mg: 123.25), _inj('ok')],
        compounds: [_testE.copyWith(id: 'hl', halfLife: 7.25)],
        reminders: [],
        customSitesIM: [],
        customSitesSubQ: [],
        bloodwork: [
          BloodworkEntry(
            id: 'bw', date: DateTime(2026, 7, 1), marker: 'E2',
            value: 42.125, unit: 'pmol/L',
          ),
        ],
        exportedAt: DateTime(2026, 7, 1), // keep the spliced numbers unique
      )
          .replaceFirst('123.25', '1e999')
          .replaceFirst('7.25', '-1e999')
          .replaceFirst('42.125', '1e999');
      final data = decodeBackup(text)!;
      expect(data.injections.map((i) => i.id), ['ok']);
      expect(data.compounds, isEmpty);
      expect(data.bloodwork, isEmpty);
      expect(data.skipped, 3);

      final res = mergeBackup(
        injections: [],
        compounds: [],
        reminders: [],
        customSitesIM: [],
        customSitesSubQ: [],
        incoming: data,
      );
      expect(() => jsonEncode(res.injections.map((e) => e.toJson()).toList()),
          returnsNormally);
    });

    test('a malformed record costs only itself, not the whole file', () {
      final data = decodeBackup(envelope({
        'injections': [_inj('ok').toJson(), {'id': 'no-date'}, 'junk', null],
      }))!;
      expect(data.injections.map((i) => i.id), ['ok']);
      expect(data.skipped, 3);
    });

    test('non-string custom sites are dropped', () {
      final data = decodeBackup(envelope({
        'customSitesIM': ['Delt L', 3, null],
      }))!;
      expect(data.customSitesIM, ['Delt L']);
      expect(data.skipped, 2);
    });

    test('a section that is not a list still rejects the file', () {
      expect(decodeBackup(envelope({'reminders': {'id': 'x'}})), isNull);
      expect(decodeBackup(envelope({'customSitesIM': 'Delt L'})), isNull);
    });
  });

  group('set-aside unreadable data', () {
    test('rides along in the backup file; restore ignores it', () {
      final text = encodeBackup(
        injections: [],
        compounds: [],
        reminders: [],
        customSitesIM: [],
        customSitesSubQ: [],
        unreadable: {'reminders_unreadable_1': '[{"id":'},
      );
      expect((jsonDecode(text) as Map)['unreadable'], {'reminders_unreadable_1': '[{"id":'});
      final data = decodeBackup(text)!;
      expect(data.reminders, isEmpty);
      expect(data.skipped, 0);
    });

    test('is omitted when there is none', () {
      final text = encodeBackup(
        injections: [],
        compounds: [],
        reminders: [],
        customSitesIM: [],
        customSitesSubQ: [],
      );
      expect((jsonDecode(text) as Map).containsKey('unreadable'), isFalse);
    });
  });
}
