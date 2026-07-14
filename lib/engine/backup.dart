import 'dart:convert';
import '../models.dart';

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

  const BackupData({
    required this.injections,
    required this.compounds,
    required this.reminders,
    required this.customSitesIM,
    required this.customSitesSubQ,
    this.bloodwork = const [],
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
  final int changedCompounds;
  final int changedReminders;
  final int newBloodwork;

  const BackupMergeResult({
    required this.injections,
    required this.compounds,
    required this.reminders,
    required this.customSitesIM,
    required this.customSitesSubQ,
    required this.bloodwork,
    required this.newInjections,
    required this.changedCompounds,
    required this.changedReminders,
    required this.newBloodwork,
  });
}

String encodeBackup({
  required List<Injection> injections,
  required List<CompoundDefinition> compounds,
  required List<Reminder> reminders,
  required List<String> customSitesIM,
  required List<String> customSitesSubQ,
  List<BloodworkEntry> bloodwork = const [],
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
  });
}

/// Returns null for anything that isn't a ProtoLog backup (bad JSON, foreign
/// envelope, newer schema than this build understands, malformed entries).
BackupData? decodeBackup(String text) {
  try {
    final root = jsonDecode(text);
    if (root is! Map<String, dynamic>) return null;
    if (root['app'] != 'protolog') return null;
    final version = root['schemaVersion'];
    if (version is! int || version > backupSchemaVersion) return null;

    List<T> parseList<T>(String key, T Function(Map<String, dynamic>) fromJson) =>
        ((root[key] as List?) ?? const [])
            .map((e) => fromJson(e as Map<String, dynamic>))
            .toList();

    return BackupData(
      injections: parseList('injections', Injection.fromJson),
      compounds: parseList('compounds', CompoundDefinition.fromJson),
      reminders: parseList('reminders', Reminder.fromJson),
      customSitesIM: ((root['customSitesIM'] as List?) ?? const []).cast<String>(),
      customSitesSubQ: ((root['customSitesSubQ'] as List?) ?? const []).cast<String>(),
      bloodwork: parseList('bloodwork', BloodworkEntry.fromJson),
    );
  } catch (_) {
    return null;
  }
}

/// Additive merge — nothing is ever deleted:
/// - injections: incoming entries with unseen ids are appended;
/// - compounds/reminders: upsert by id (incoming wins), new ids appended;
/// - custom sites: set union, current order first.
BackupMergeResult mergeBackup({
  required List<Injection> injections,
  required List<CompoundDefinition> compounds,
  required List<Reminder> reminders,
  required List<String> customSitesIM,
  required List<String> customSitesSubQ,
  List<BloodworkEntry> bloodwork = const [],
  required BackupData incoming,
}) {
  final mergedInjections = List<Injection>.from(injections);
  final seenIds = injections.map((i) => i.id).toSet();
  var newInjections = 0;
  for (final inj in incoming.injections) {
    if (seenIds.add(inj.id)) {
      mergedInjections.add(inj);
      newInjections++;
    }
  }

  // Upsert helper; counts entries whose serialized form actually changed.
  (List<T>, int) upsert<T>(
    List<T> current,
    List<T> incoming,
    String Function(T) idOf,
    Map<String, dynamic> Function(T) jsonOf,
  ) {
    final merged = List<T>.from(current);
    var changed = 0;
    for (final item in incoming) {
      final idx = merged.indexWhere((c) => idOf(c) == idOf(item));
      if (idx < 0) {
        merged.add(item);
        changed++;
      } else if (jsonEncode(jsonOf(merged[idx])) != jsonEncode(jsonOf(item))) {
        merged[idx] = item;
        changed++;
      }
    }
    return (merged, changed);
  }

  final (mergedCompounds, changedCompounds) = upsert<CompoundDefinition>(
      compounds, incoming.compounds, (c) => c.id, (c) => c.toJson());
  final (mergedReminders, changedReminders) = upsert<Reminder>(
      reminders, incoming.reminders, (r) => r.id, (r) => r.toJson());
  final (mergedBloodwork, newBloodwork) = upsert<BloodworkEntry>(
      bloodwork, incoming.bloodwork, (b) => b.id, (b) => b.toJson());

  List<String> union(List<String> a, List<String> b) =>
      {...a, ...b}.toList();

  return BackupMergeResult(
    injections: mergedInjections,
    compounds: mergedCompounds,
    reminders: mergedReminders,
    customSitesIM: union(customSitesIM, incoming.customSitesIM),
    customSitesSubQ: union(customSitesSubQ, incoming.customSitesSubQ),
    bloodwork: mergedBloodwork,
    newInjections: newInjections,
    changedCompounds: changedCompounds,
    changedReminders: changedReminders,
    newBloodwork: newBloodwork,
  );
}
