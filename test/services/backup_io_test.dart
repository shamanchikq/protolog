import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/engine/backup.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/services/app_store.dart';
import 'package:protolog_tracker/services/backup_io.dart';
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

Injection _inj(String id) => Injection(
    id: id, compoundId: 'test_e', date: DateTime(2026, 6, 1), dosage: 150, snapshot: _testE);

AppCollections _state({List<Injection> injections = const []}) => (
      injections: injections,
      compounds: const <CompoundDefinition>[],
      reminders: const <Reminder>[],
      bloodwork: const <BloodworkEntry>[],
    );

String _file({List<Injection> injections = const [], List<String> sitesIM = const [], List<Object?> extraInjections = const []}) {
  final json = jsonDecode(encodeBackup(
    injections: injections,
    compounds: const [],
    reminders: const [],
    customSitesIM: sitesIM,
    customSitesSubQ: const [],
  )) as Map<String, dynamic>;
  (json['injections'] as List).addAll(extraInjections);
  return jsonEncode(json);
}

void main() {
  group('preview', () {
    test('rejects text that is not a ProtoLog backup', () async {
      SharedPreferences.setMockInitialValues({});
      final io = BackupIO(AppStore());
      expect(await io.preview('{"hello": 1}', _state()), isNull);
      expect(await io.preview('garbage', _state()), isNull);
    });

    test('a backup of the current state is a no-op', () async {
      SharedPreferences.setMockInitialValues({'customSitesIM': jsonEncode(['Quad L'])});
      final io = BackupIO(AppStore());
      final p = (await io.preview(_file(injections: [_inj('i1')], sitesIM: ['Quad L']),
          _state(injections: [_inj('i1')])))!;
      expect(p.isNoOp, isTrue);
      expect(p.nothingToMergeMessage, 'Backup matches current data — nothing to merge');
    });

    test('merges with the stored custom sites and summarises the changes', () async {
      SharedPreferences.setMockInitialValues({'customSitesIM': jsonEncode(['Quad L'])});
      final io = BackupIO(AppStore());
      final p = (await io.preview(
          _file(injections: [_inj('i1'), _inj('i2')], sitesIM: ['Quad L', 'Pec R']),
          _state(injections: [_inj('i1')])))!;

      expect(p.isNoOp, isFalse);
      expect(p.merged.injections.map((i) => i.id), ['i1', 'i2']);
      expect(p.merged.customSitesIM, ['Quad L', 'Pec R']);
      expect(p.summary,
          '1 new logs, 0 compound updates, 0 reminder updates, 0 lab results, 1 new sites. '
          'Existing data is never deleted.');
    });

    test('mentions invalid entries that will be skipped', () async {
      SharedPreferences.setMockInitialValues({});
      final io = BackupIO(AppStore());
      final p = (await io.preview(
          _file(injections: [_inj('i2')], extraInjections: [{'id': 'broken'}]), _state()))!;
      expect(p.skipped, 1);
      expect(p.summary, contains('1 invalid entry in the file will be skipped. '));

      final noop = (await io.preview(_file(extraInjections: [{'id': 'a'}, {'id': 'b'}]), _state()))!;
      expect(noop.isNoOp, isTrue);
      expect(noop.nothingToMergeMessage,
          'Nothing new to merge — 2 invalid entries in the file were skipped');
    });
  });

  test('commitSites writes the merged sites and reports failure', () async {
    SharedPreferences.setMockInitialValues({});
    final ok = BackupIO(AppStore());
    final p = (await ok.preview(_file(sitesIM: ['Pec R']), _state()))!;
    expect(await ok.commitSites(p), isTrue);
    expect((await AppStore().readCustomSites()).im, ['Pec R']);

    final flaky = await FlakyPrefs.withValues({}, refuse: {'customSitesIM'});
    expect(await BackupIO(AppStore(prefs: () async => flaky)).commitSites(p), isFalse);
  });

  test('encode carries the stored sites and any set-aside data', () async {
    SharedPreferences.setMockInitialValues({
      'customSitesSubQ': jsonEncode(['Flank R']),
      'injections_unreadable_5': 'raw',
    });
    final text = await BackupIO(AppStore()).encode(_state(injections: [_inj('i1')]));
    final json = jsonDecode(text) as Map<String, dynamic>;
    expect(json['customSitesSubQ'], ['Flank R']);
    expect(json['unreadable'], {'injections_unreadable_5': 'raw'});
    expect(decodeBackup(text)!.injections.single.id, 'i1');
  });
}
