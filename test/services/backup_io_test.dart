import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
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

final _bw = BloodworkEntry(
    id: 'b1', date: DateTime(2026, 6, 2), marker: 'E2', value: 90, unit: 'pmol/L');

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
      expect(p.summary, 'Adds 1 log and 1 injection site. Nothing else changes.');
    });

    test('says which records on this device the backup replaces (B23)', () async {
      SharedPreferences.setMockInitialValues({});
      final io = BackupIO(AppStore());
      final local = _state(injections: [_inj('i1')]);
      final current = (
        injections: local.injections,
        compounds: [_testE, _testE.copyWith(id: 'c2', base: 'Custom')],
        reminders: [_rem('r1'), _rem('r2')],
        bloodwork: <BloodworkEntry>[],
      );
      final file = encodeBackup(
        injections: [_inj('i1'), _inj('i2'), _inj('i3')],
        compounds: [_testE.copyWith(halfLife: 6), _testE.copyWith(id: 'c2', base: 'Custom')],
        reminders: [_rem('r1', interval: 7), _rem('r2', interval: 7), _rem('r3')],
        customSitesIM: const [],
        customSitesSubQ: const [],
        bloodwork: [_bw],
      );
      final p = (await io.preview(file, current))!;
      expect(p.summary,
          'Adds 2 logs, 1 reminder and 1 lab result. '
          "Replaces the matching 1 compound and 2 reminders on this device with the backup's copy. "
          'Nothing else changes.');
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

    expect(await BackupIO(AppStore(sites: const ThrowingSitesStore())).commitSites(p), isFalse);
  });

  group('share', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('backup_io_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('hands the sheet the file and the anchor, then deletes the file (D4, D8)', () async {
      SharedPreferences.setMockInitialValues({});
      ShareParams? shared;
      var existedDuringShare = false;
      final io = BackupIO(
        AppStore(),
        clock: () => DateTime(2026, 10, 3),
        tempDir: () async => tmp,
        shareSheet: (p) async {
          shared = p;
          existedDuringShare = File(p.files!.single.path).existsSync();
        },
      );
      const origin = Rect.fromLTWH(0, 0, 400, 800);

      await io.share(_state(injections: [_inj('i1')]), origin: origin);

      expect(shared!.sharePositionOrigin, origin);
      expect(shared!.files!.single.path, endsWith('protolog_backup_2026-10-03.json'));
      expect(existedDuringShare, isTrue);
      expect(tmp.listSync(), isEmpty);
    });

    test('the file is deleted even when the sheet fails', () async {
      SharedPreferences.setMockInitialValues({});
      final io = BackupIO(AppStore(),
          tempDir: () async => tmp, shareSheet: (_) async => throw StateError('no sheet'));
      await expectLater(io.share(_state()), throwsStateError);
      expect(tmp.listSync(), isEmpty);
    });
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
