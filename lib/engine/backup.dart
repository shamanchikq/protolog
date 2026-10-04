import 'dart:convert';
import '../models.dart';
import 'migrations.dart';
import 'record_validation.dart';
import 'stored_data.dart';

/// Full-state backup serde + merge. The envelope is versioned so future
/// schema changes can migrate instead of rejecting old files.
const int backupSchemaVersion = 1;

class BackupData {
  final List<Injection> injections;
  final List<CompoundDefinition> compounds;
  final List<Reminder> reminders;
  final List<String> customSitesIM;
  final List<String> customSitesSubQ;
  final List<BloodworkEntry> bloodwork;

  /// Entries in the file that were malformed or failed validation and were
  /// left out (shown in the restore preview).
  final int skipped;

  const BackupData({
    required this.injections,
    required this.compounds,
    required this.reminders,
    required this.customSitesIM,
    required this.customSitesSubQ,
    this.bloodwork = const [],
    this.skipped = 0,
  });
}

class BackupMergeResult {
  final List<Injection> injections;
  final List<CompoundDefinition> compounds;
  final List<Reminder> reminders;
  final List<String> customSitesIM;
  final List<String> customSitesSubQ;
  final List<BloodworkEntry> bloodwork;
  final int newInjections;

  /// Records with an id this device didn't have.
  final int newCompounds;
  final int newReminders;
  final int newBloodwork;

  /// Records this device had under the same id, overwritten by the backup's
  /// differing copy (incoming wins — records carry no edit timestamps).
  final int replacedCompounds;
  final int replacedReminders;
  final int replacedBloodwork;

  /// Custom sites the merge added (both routes).
  final int newSites;

  /// Ids of the reminders the merge added or replaced: their notifications
  /// must be rescheduled — or cancelled, when the backup's copy is disabled.
  final Set<String> changedReminderIds;

  int get changedCompounds => newCompounds + replacedCompounds;
  int get changedReminders => newReminders + replacedReminders;

  /// Everything the merge would change; 0 means the backup adds nothing.
  int get totalChanges => newInjections + changedCompounds + changedReminders +
      newBloodwork + replacedBloodwork + newSites;

  const BackupMergeResult({
    required this.injections,
    required this.compounds,
    required this.reminders,
    required this.customSitesIM,
    required this.customSitesSubQ,
    required this.bloodwork,
    required this.newInjections,
    this.newCompounds = 0,
    this.newReminders = 0,
    this.newBloodwork = 0,
    this.replacedCompounds = 0,
    this.replacedReminders = 0,
    this.replacedBloodwork = 0,
    required this.newSites,
    this.changedReminderIds = const {},
  });
}

/// `protolog_backup_YYYY-MM-DD.json` for a backup made at [at].
String backupFileName(DateTime at) => 'protolog_backup_${at.year}'
    '-${at.month.toString().padLeft(2, '0')}'
    '-${at.day.toString().padLeft(2, '0')}.json';

String encodeBackup({
  required List<Injection> injections,
  required List<CompoundDefinition> compounds,
  required List<Reminder> reminders,
  required List<String> customSitesIM,
  required List<String> customSitesSubQ,
  List<BloodworkEntry> bloodwork = const [],
  Map<String, String> unreadable = const {},
  DateTime? exportedAt,
}) {
  return jsonEncode({
    'app': 'protolog',
    'schemaVersion': backupSchemaVersion,
    'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
    'injections': injections.map((e) => e.toJson()).toList(),
    'compounds': compounds.map((e) => e.toJson()).toList(),
    'reminders': reminders.map((e) => e.toJson()).toList(),
    'customSitesIM': customSitesIM,
    'customSitesSubQ': customSitesSubQ,
    'bloodwork': bloodwork.map((e) => e.toJson()).toList(),
    // Raw stored text the app set aside at load because it couldn't read it
    // (A7) — carried out for manual recovery; restore ignores it.
    if (unreadable.isNotEmpty) 'unreadable': unreadable,
  });
}

/// Returns null for anything that isn't a ProtoLog backup (bad JSON, foreign
/// envelope, newer schema than this build understands, a section that isn't
/// a list). Individual entries that are malformed or fail semantic
/// validation (record_validation.dart) are dropped and counted in
/// [BackupData.skipped] rather than rejecting the file: the good data stays
/// restorable, and the file itself is never modified.
BackupData? decodeBackup(String text) {
  try {
    final root = jsonDecode(text);
    if (root is! Map<String, dynamic>) return null;
    if (root['app'] != 'protolog') return null;
    final version = root['schemaVersion'];
    if (version is! int || version > backupSchemaVersion) return null;

    var skipped = 0;
    List<T> records<T>(
      String key,
      T Function(Map<String, dynamic>) fromJson,
      bool Function(T) isValid,
    ) {
      final res = decodeRecords(root[key] ?? const [], fromJson, isValid: isValid);
      if (res.unreadable) throw FormatException('"$key" is not a list');
      skipped += res.skipped;
      return res.items;
    }

    List<String> sites(String key) {
      final list = root[key] ?? const [];
      if (list is! List) throw FormatException('"$key" is not a list');
      final out = list.whereType<String>().toList();
      skipped += list.length - out.length;
      return out;
    }

    final injections = records('injections', Injection.fromJson, isValidInjection);
    final compounds = records('compounds', CompoundDefinition.fromJson, isValidCompound);
    final reminders = records('reminders', Reminder.fromJson, isValidReminder);
    final bloodwork = records('bloodwork', BloodworkEntry.fromJson, isValidBloodwork);
    final sitesIM = sites('customSitesIM');
    final sitesSubQ = sites('customSitesSubQ');
    return BackupData(
      injections: injections,
      compounds: compounds,
      reminders: reminders,
      customSitesIM: sitesIM,
      customSitesSubQ: sitesSubQ,
      bloodwork: bloodwork,
      skipped: skipped,
    );
  } catch (_) {
    return null;
  }
}

/// Additive merge — nothing is ever deleted:
/// - injections: incoming entries with unseen ids are appended;
/// - compounds/reminders/bloodwork: upsert by id — the incoming copy
///   replaces a differing local one (B23: a new-phone restore needs that,
///   and records carry no edit timestamps to pick the newer), new ids are
///   appended;
/// - a replaced reminder keeps this device's notification seed (N6), so the
///   ids its notifications were scheduled under stay its own;
/// - custom sites: set union, current order first.
///
/// The backup's records get the load-time fix-ups ([migrateRecords]) before
/// anything is compared, and the merged state gets them again — so two
/// compounds for one base+ester (say a log on the new phone adopted a
/// built-in under a fresh id, and the backup holds the old one) collapse to
/// the backup's, with logs relinked (B6).
BackupMergeResult mergeBackup({
  required List<Injection> injections,
  required List<CompoundDefinition> compounds,
  required List<Reminder> reminders,
  required List<String> customSitesIM,
  required List<String> customSitesSubQ,
  List<BloodworkEntry> bloodwork = const [],
  required BackupData incoming,
}) {
  final theirs = migrateRecords(
    injections: incoming.injections,
    compounds: incoming.compounds,
    reminders: incoming.reminders,
  );
  final mergedInjections = List<Injection>.from(injections);
  final seenIds = injections.map((i) => i.id).toSet();
  var newInjections = 0;
  for (final inj in theirs.injections) {
    if (seenIds.add(inj.id)) {
      mergedInjections.add(inj);
      newInjections++;
    }
  }

  // Upsert by id. [adopt] turns an incoming item into what replaces the
  // local one (default: as is). Only entries whose serialized form actually
  // changes count — and are reported in the returned ids.
  ({List<T> merged, int added, int replaced, Set<String> ids}) upsert<T>(
    List<T> current,
    List<T> incoming,
    String Function(T) idOf,
    Map<String, dynamic> Function(T) jsonOf, {
    T Function(T incoming, T local)? adopt,
  }) {
    final merged = List<T>.from(current);
    var added = 0, replaced = 0;
    final ids = <String>{};
    for (final item in incoming) {
      final idx = merged.indexWhere((c) => idOf(c) == idOf(item));
      if (idx < 0) {
        merged.add(item);
        added++;
        ids.add(idOf(item));
        continue;
      }
      final next = adopt == null ? item : adopt(item, merged[idx]);
      if (jsonEncode(jsonOf(merged[idx])) != jsonEncode(jsonOf(next))) {
        merged[idx] = next;
        replaced++;
        ids.add(idOf(item));
      }
    }
    return (merged: merged, added: added, replaced: replaced, ids: ids);
  }

  final comp = upsert<CompoundDefinition>(
      compounds, theirs.compounds, (c) => c.id, (c) => c.toJson());
  final rem = upsert<Reminder>(
      reminders, theirs.reminders, (r) => r.id, (r) => r.toJson(),
      adopt: (theirs, ours) => theirs.copyWith(notificationSeed: ours.notificationIdBase));
  final bw = upsert<BloodworkEntry>(
      bloodwork, incoming.bloodwork, (b) => b.id, (b) => b.toJson());

  List<String> union(List<String> a, List<String> b) =>
      {...a, ...b}.toList();
  final sitesIM = union(customSitesIM, incoming.customSitesIM);
  final sitesSubQ = union(customSitesSubQ, incoming.customSitesSubQ);

  final merged = migrateRecords(
    injections: mergedInjections,
    compounds: comp.merged,
    reminders: rem.merged,
  );

  return BackupMergeResult(
    injections: merged.injections,
    compounds: merged.compounds,
    reminders: merged.reminders,
    customSitesIM: sitesIM,
    customSitesSubQ: sitesSubQ,
    bloodwork: bw.merged,
    newInjections: newInjections,
    newCompounds: comp.added,
    replacedCompounds: comp.replaced,
    newReminders: rem.added,
    replacedReminders: rem.replaced,
    newBloodwork: bw.added,
    replacedBloodwork: bw.replaced,
    newSites: (sitesIM.length - customSitesIM.length) +
        (sitesSubQ.length - customSitesSubQ.length),
    changedReminderIds: rem.ids,
  );
}
