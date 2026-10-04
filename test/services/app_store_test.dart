import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/services/app_store.dart';
import 'package:protolog_tracker/services/custom_sites_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

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
    );

Reminder _rem(String id, {int? seed = 42}) => Reminder(
      id: id,
      compoundBase: 'Testosterone',
      compoundEster: 'Enanthate',
      intervalDays: 3.5,
      hour: 8,
      minute: 0,
      enabled: true,
      anchorDate: DateTime(2026, 7, 14, 8, 0),
      notificationSeed: seed,
    );

final _bw = BloodworkEntry(
    id: 'b1', date: DateTime(2026, 6, 2), marker: 'E2', value: 90, unit: 'pmol/L');

String _list(List<Object?> items) => jsonEncode(items);

final _at = DateTime(2026, 10, 3, 12);
AppStore _store([Future<SharedPreferences> Function()? prefs]) =>
    AppStore(prefs: prefs, clock: () => _at);

Future<FlakyPrefs> _flaky(Map<String, Object> initial,
        {Set<String> refuse = const {}, Set<String> throwOn = const {}}) =>
    FlakyPrefs.withValues(initial, refuse: refuse, throwOn: throwOn);

void main() {
  group('load', () {
    test('a clean load reads every collection and writes nothing', () async {
      final initial = <String, Object>{
        'injections': _list([_inj('i1').toJson()]),
        'compounds': _list([_testE.toJson()]),
        'reminders': _list([_rem('r1').toJson()]),
        'bloodwork': _list([_bw.toJson()]),
      };
      final prefs = await _flaky(initial);
      final store = _store(() async => prefs);

      final res = await store.load();

      expect(res.failed, isFalse);
      expect(res.problem, isNull);
      expect(res.injections.single.id, 'i1');
      expect(res.compounds.single.id, 'test_e');
      expect(res.reminders.single.notificationSeed, 42);
      expect(res.bloodwork.single.marker, 'E2');
      expect(store.unsafeKeys, isEmpty);
      expect(prefs.writes, isEmpty);
    });

    test('old data is fixed up and saved once (G7, B6)', () async {
      final adopted = _testE.copyWith(id: 'adopted');
      final aiReminder = _rem('r1').copyWith(compoundBase: 'Anastrazole', compoundEster: 'None');
      final prefs = await _flaky({
        'injections': _list([_inj('i1').toJson()..['compoundId'] = 'adopted']),
        'compounds': _list([adopted.toJson(), _testE.toJson()]),
        'reminders': _list([aiReminder.toJson()]),
      });

      final res = await _store(() async => prefs).load();

      expect(res.compounds.map((c) => c.id), ['test_e']);
      expect(res.injections.single.compoundId, 'test_e');
      expect(res.reminders.single.compoundBase, 'Anastrozole');
      expect(prefs.writes, ['injections', 'compounds', 'reminders']);
      expect(res.problem, isNull);

      prefs.writes.clear();
      final again = await _store(() async => prefs).load();
      expect(prefs.writes, isEmpty);
      expect(again.reminders.single.compoundBase, 'Anastrozole');
    });

    test('a fresh install starts from the initial compounds', () async {
      SharedPreferences.setMockInitialValues({});
      final res = await _store().load();
      expect(res.compounds.map((c) => c.id), INITIAL_COMPOUNDS.map((c) => c.id));
      expect(res.injections, isEmpty);
      expect(res.problem, isNull);
    });

    test('loaded lists are growable, even when nothing was stored', () async {
      // They become live app state; the first add must not throw.
      for (final initial in <Map<String, Object>>[{}, {'injections': 'garbage'}]) {
        SharedPreferences.setMockInitialValues(initial);
        final res = await _store().load();
        expect(() => res.injections.add(_inj('i1')), returnsNormally);
        expect(() => res.reminders.add(_rem('r1')), returnsNormally);
        expect(() => res.bloodwork.add(_bw), returnsNormally);
        expect(() => res.compounds.add(_testE), returnsNormally);
      }
      final failed = await _store(() async => throw StateError('x')).load();
      expect(() => failed.injections.add(_inj('i1')), returnsNormally);
      expect(() => failed.compounds.add(_testE), returnsNormally);
    });

    test('a saved empty compound list stays empty', () async {
      SharedPreferences.setMockInitialValues({'compounds': '[]'});
      expect((await _store().load()).compounds, isEmpty);
    });

    test('unreadable text is set aside verbatim before anything is saved', () async {
      final prefs = await _flaky({'injections': 'not json {'});
      final store = _store(() async => prefs);

      final res = await store.load();

      final aside = 'injections_unreadable_${_at.millisecondsSinceEpoch}';
      expect(prefs.writes, [aside]);
      expect(prefs.getString(aside), 'not json {');
      expect(prefs.getString('injections'), 'not json {');
      expect(res.unreadable, ['injections']);
      expect(res.injections, isEmpty);
      expect(res.problem,
          "Couldn't read saved injections. The original data was kept aside — nothing was deleted.");
      // Set aside, so the key is safe to save over again.
      expect(store.unsafeKeys, isEmpty);
      expect(await store.saveInjections([_inj('i2')]), isTrue);
      expect(prefs.getString('injections'), contains('"i2"'));
      expect(prefs.getString(aside), 'not json {');
    });

    test('bad records are dropped and counted; the raw list is set aside', () async {
      final raw = _list([
        _inj('good').toJson(),
        {'id': 'broken'},
        {..._inj('neg').toJson(), 'dosage': -5},
      ]);
      final prefs = await _flaky({'injections': raw});

      final res = await _store(() async => prefs).load();

      expect(res.injections.map((i) => i.id), ['good']);
      expect(res.skipped, 2);
      expect(res.unreadable, isEmpty);
      expect(prefs.getString('injections_unreadable_${_at.millisecondsSinceEpoch}'), raw);
      expect(res.problem, startsWith("Couldn't read 2 saved entries."));
    });

    test('an identical copy from an earlier launch is not duplicated', () async {
      final prefs = await _flaky({
        'bloodwork': 'garbage',
        'bloodwork_unreadable_1': 'garbage',
      });
      final res = await _store(() async => prefs).load();
      expect(prefs.writes, isEmpty);
      expect(res.unreadable, ['bloodwork']);
    });

    test('a non-string value under a data key is set aside as text', () async {
      final prefs = await _flaky({'reminders': 42});
      final res = await _store(() async => prefs).load();
      expect(prefs.getString('reminders_unreadable_${_at.millisecondsSinceEpoch}'), '42');
      expect(res.unreadable, ['reminders']);
    });

    test('a key that cannot be set aside is never written this session', () async {
      final prefs = await _flaky(
        {'injections': 'not json {', 'reminders': _list([_rem('r1').toJson()])},
        refuse: {'injections_unreadable_'},
      );
      final store = _store(() async => prefs);

      final res = await store.load();

      expect(store.unsafeKeys, {'injections'});
      expect(res.unsafeKeys, ['injections']);
      expect(res.unreadable, isEmpty, reason: 'only counted once set aside');
      expect(res.problem,
          "Some saved data couldn't be read or set aside — changes to injections won't be saved this session.");

      prefs.writes.clear();
      expect(await store.saveInjections([_inj('i1')]), isTrue,
          reason: 'held back on purpose, not a failure');
      expect(prefs.writes, isEmpty);
      expect(prefs.getString('injections'), 'not json {');
      // Other collections still save.
      expect(await store.saveReminders([_rem('r2')]), isTrue);
      expect(prefs.getString('reminders'), contains('"r2"'));
    });

    test('a load that cannot reach prefs fails closed: nothing is saved', () async {
      SharedPreferences.setMockInitialValues({'injections': _list([_inj('i1').toJson()])});
      var calls = 0;
      final store = _store(() async {
        if (calls++ == 0) throw StateError('no prefs');
        return SharedPreferences.getInstance();
      });

      final res = await store.load();

      expect(res.failed, isTrue);
      expect(res.injections, isEmpty);
      expect(res.problem, "Couldn't load saved data — nothing was changed. Restart to retry.");
      expect(store.unsafeKeys, AppStore.dataKeys.toSet());
      expect(await store.saveInjections([]), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('injections'), contains('"i1"'));
    });

    test('legacy reminders get their notification seed frozen', () async {
      final prefs = await _flaky({'reminders': _list([_rem('r1', seed: null).toJson()
        ..remove('notificationSeed')])});
      await _store(() async => prefs).load();
      expect(prefs.writes, ['reminders']);
      final stored = jsonDecode(prefs.getString('reminders')!) as List;
      expect(stored.single['notificationSeed'], 'r1'.hashCode);
    });
  });

  group('large collections (E4)', () {
    List<Injection> big([String prefix = 'i']) =>
        [for (var i = 0; i < AppStore.kIsolateEncodeThreshold + 50; i++) _inj('$prefix$i')];

    test('are encoded on a background isolate to the same text', () async {
      SharedPreferences.setMockInitialValues({});
      final store = _store();
      await store.load();
      final list = big();

      final saved = store.saveInjections(list);
      list.add(_inj('later')); // the save is a snapshot of the call
      expect(await saved, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('injections'),
          jsonEncode([for (final e in list.take(list.length - 1)) e.toJson()]));
    });

    test('writes land in call order even when the big encode finishes last', () async {
      SharedPreferences.setMockInitialValues({});
      final store = _store();
      await store.load();

      final first = store.saveInjections(big());
      final second = store.saveInjections([_inj('only')]);
      expect(await second, isTrue);
      expect(await first, isTrue);

      expect((await _store().load()).injections.map((i) => i.id), ['only']);
    });

    test('an unencodable big collection reports failure and writes nothing', () async {
      final prefs = await _flaky({});
      final store = _store(() async => prefs);
      await store.load();
      expect(await store.saveInjections([...big(), _inj('nan', mg: double.nan)]), isFalse);
      expect(prefs.writes, isEmpty);
    });
  });

  group('save', () {
    test('round-trips every collection through a fresh load', () async {
      SharedPreferences.setMockInitialValues({});
      final store = _store();
      await store.load();
      expect(await store.saveInjections([_inj('i1'), _inj('i2', mg: 0.25)]), isTrue);
      expect(await store.saveCompounds([_testE]), isTrue);
      expect(await store.saveReminders([_rem('r1')]), isTrue);
      expect(await store.saveBloodwork([_bw]), isTrue);

      final res = await _store().load();
      expect(res.injections.map((i) => i.dosage), [150, 0.25]);
      expect(res.compounds.single.toJson(), _testE.toJson());
      expect(res.reminders.single.toJson(), _rem('r1').toJson());
      expect(res.bloodwork.single.toJson(), _bw.toJson());
      expect(res.problem, isNull);
    });

    test('a refused write reports failure', () async {
      final prefs = await _flaky({}, refuse: {'compounds'});
      final store = _store(() async => prefs);
      await store.load();
      expect(await store.saveCompounds([_testE]), isFalse);
    });

    test('a throwing write reports failure', () async {
      final prefs = await _flaky({}, throwOn: {'bloodwork'});
      final store = _store(() async => prefs);
      await store.load();
      expect(await store.saveBloodwork([_bw]), isFalse);
    });

    test('unencodable data reports failure and leaves the stored copy alone', () async {
      final prefs = await _flaky({'injections': _list([_inj('i1').toJson()])});
      final store = _store(() async => prefs);
      await store.load();
      expect(await store.saveInjections([_inj('bad', mg: double.infinity)]), isFalse);
      expect(prefs.getString('injections'), contains('"i1"'));
    });

    test('encodes the list as it was when the save was requested', () async {
      SharedPreferences.setMockInitialValues({});
      final store = _store();
      await store.load();
      final list = [_inj('i1')];
      final saved = store.saveInjections(list);
      list.add(_inj('later'));
      await saved;
      final res = await _store().load();
      expect(res.injections.map((i) => i.id), ['i1']);
    });
  });

  group('custom sites (through the wizard\'s CustomSitesStore)', () {
    test('round-trip, readable by the wizard', () async {
      SharedPreferences.setMockInitialValues({});
      final store = _store();
      expect(await store.writeCustomSites(const CustomSites(im: ['Quad L'], subQ: ['Flank R'])),
          isTrue);
      final sites = await store.readCustomSites();
      expect(sites.im, ['Quad L']);
      expect(sites.subQ, ['Flank R']);
      expect((await const CustomSitesStore().load()).subQ, ['Flank R']);
    });

    test('garbage or non-string entries read as empty / are dropped', () async {
      SharedPreferences.setMockInitialValues({
        'customSitesIM': 'nope',
        'customSitesSubQ': jsonEncode(['Flank R', 3, null]),
      });
      final sites = await _store().readCustomSites();
      expect(sites.im, isEmpty);
      expect(sites.subQ, ['Flank R']);
    });

    test('a failed write reports failure', () async {
      final store = AppStore(sites: const ThrowingSitesStore());
      expect(await store.writeCustomSites(const CustomSites(subQ: ['x'])), isFalse);
    });

    test('a refused write reports failure too', () async {
      final prefs = await FlakyPrefs.withValues({}, refuse: {'customSites'});
      final store = AppStore(sites: CustomSitesStore(prefs: () async => prefs));
      expect(await store.writeCustomSites(const CustomSites(subQ: ['x'])), isFalse);
    });
  });

  test('setAsideData returns only set-aside copies of data collections', () async {
    SharedPreferences.setMockInitialValues({
      'injections': '[]',
      'injections_unreadable_1': 'raw-inj',
      'bloodwork_unreadable_2': 'raw-bw',
      'customSitesIM_unreadable_3': 'not a data key',
      'reminders_unreadable_4': 7,
    });
    expect(await _store().setAsideData(), {
      'injections_unreadable_1': 'raw-inj',
      'bloodwork_unreadable_2': 'raw-bw',
    });
  });
}
