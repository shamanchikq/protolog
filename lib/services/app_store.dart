import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data.dart';
import '../engine/record_validation.dart';
import '../engine/stored_data.dart';
import '../models.dart';

/// What [AppStore.load] read. The lists are growable — the caller adopts
/// them as live state. On a failed load every list is empty and nothing
/// will be saved this session.
class LoadResult {
  final List<Injection> injections;
  final List<CompoundDefinition> compounds;
  final List<Reminder> reminders;
  final List<BloodworkEntry> bloodwork;

  /// The load itself threw (e.g. prefs unavailable); nothing was read.
  final bool failed;

  /// Records dropped from collections whose raw text was set aside.
  final int skipped;

  /// Collections that weren't readable at all (and were set aside).
  final List<String> unreadable;

  /// Collections that couldn't be read *or* set aside — never saved this
  /// session (see [AppStore.unsafeKeys]).
  final List<String> unsafeKeys;

  const LoadResult({
    required this.injections,
    required this.compounds,
    required this.reminders,
    required this.bloodwork,
    this.failed = false,
    this.skipped = 0,
    this.unreadable = const [],
    this.unsafeKeys = const [],
  });

  /// User-facing banner text, or null for a clean load.
  String? get problem {
    if (failed) {
      return "Couldn't load saved data — nothing was changed. Restart to retry.";
    }
    if (unsafeKeys.isNotEmpty) {
      return "Some saved data couldn't be read or set aside — changes to "
          "${unsafeKeys.join(', ')} won't be saved this session.";
    }
    final parts = [
      if (skipped > 0) '$skipped saved ${skipped == 1 ? 'entry' : 'entries'}',
      if (unreadable.isNotEmpty) 'saved ${unreadable.join(' and ')}',
    ];
    if (parts.isEmpty) return null;
    return "Couldn't read ${parts.join(' or ')}. The original data was kept "
        'aside — nothing was deleted.';
  }
}

/// The wizard's custom injection-site lists (JSON string lists in prefs).
typedef CustomSites = ({List<String> im, List<String> subQ});

/// SharedPreferences persistence for the app's collections (A7 semantics):
///
/// * [load] decodes each collection record by record; whatever couldn't be
///   read is copied verbatim to `<key>_unreadable_<millis>` before anything
///   can save over it.
/// * A key whose stored contents were neither loaded nor set aside stays in
///   [unsafeKeys] and is never written this session.
/// * Saves are awaited and report failure instead of failing silently.
class AppStore {
  AppStore({
    Future<SharedPreferences> Function()? prefs,
    DateTime Function()? clock,
  })  : _prefs = prefs ?? SharedPreferences.getInstance,
        _clock = clock ?? DateTime.now;

  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _clock;

  static const kInjections = 'injections';
  static const kCompounds = 'compounds';
  static const kReminders = 'reminders';
  static const kBloodwork = 'bloodwork';

  /// Collections persisted as JSON lists, loaded through decodeStoredList.
  static const dataKeys = [kInjections, kCompounds, kReminders, kBloodwork];

  static const kCustomSitesIM = 'customSitesIM';
  static const kCustomSitesSubQ = 'customSitesSubQ';

  // Keys whose stored contents this session hasn't accounted for yet —
  // neither loaded nor set aside verbatim. Saves skip them, so a failed or
  // partial load can never overwrite data the app couldn't read (A7).
  final Set<String> _unsafeKeys = {...dataKeys};

  /// Collections that won't be saved this session, in [dataKeys] order.
  Set<String> get unsafeKeys => Set.unmodifiable(_unsafeKeys);

  /// Tolerant load (A7): never throws. A key becomes safe to save once its
  /// contents were read completely or set aside verbatim.
  Future<LoadResult> load() async {
    final SharedPreferences prefs;
    final Map<String, String?> raw;
    try {
      prefs = await _prefs();
      // A non-string value under a data key (never written by the app) is
      // handled like unreadable text.
      raw = {
        for (final k in dataKeys)
          k: switch (prefs.get(k)) { null => null, final String v => v, final v => '$v' },
      };
    } catch (_) {
      return LoadResult(
          injections: [], compounds: [], reminders: [], bloodwork: [],
          failed: true, unsafeKeys: dataKeys);
    }

    final inj = decodeStoredList(raw[kInjections], Injection.fromJson,
        isValid: isValidInjection);
    final comp = decodeStoredList(raw[kCompounds], CompoundDefinition.fromJson,
        isValid: isValidCompound);
    final bw = decodeStoredList(raw[kBloodwork], BloodworkEntry.fromJson,
        isValid: isValidBloodwork);
    final rem = decodeStoredList(raw[kReminders], Reminder.fromJson,
        isValid: isValidReminder);

    // Nothing has been written yet. Set aside every lossy collection's raw
    // text first; a key whose copy can't be written stays unsafe (never
    // saved this session).
    var skipped = 0;
    final unreadable = <String>[];
    for (final (key, res) in <(String, DecodedRecords<Object?>)>[
      (kInjections, inj), (kCompounds, comp), (kBloodwork, bw), (kReminders, rem),
    ]) {
      if (res.lossy) {
        if (!await _setAside(prefs, key, raw[key]!)) continue;
        skipped += res.skipped;
        if (res.unreadable) unreadable.add(key);
      }
      _unsafeKeys.remove(key);
    }

    // Freeze notification-id seeds for reminders saved before the seed
    // existed, while id.hashCode still matches what was scheduled.
    if (rem.items.any((r) => r.notificationSeed == null)) {
      await saveReminders(rem.items);
    }

    return LoadResult(
      injections: inj.items,
      compounds: raw[kCompounds] == null ? List.from(INITIAL_COMPOUNDS) : comp.items,
      reminders: rem.items,
      bloodwork: bw.items,
      skipped: skipped,
      unreadable: unreadable,
      unsafeKeys: [for (final k in dataKeys) if (_unsafeKeys.contains(k)) k],
    );
  }

  /// Copies [raw] to `<key>_unreadable_<millis>` unless an identical copy is
  /// already there from an earlier launch. True once the data is safe.
  Future<bool> _setAside(SharedPreferences prefs, String key, String raw) async {
    try {
      final prefix = unreadableKeyPrefix(key);
      for (final k in prefs.getKeys()) {
        if (k.startsWith(prefix) && prefs.get(k) == raw) return true;
      }
      return await prefs.setString(unreadableKey(key, _clock()), raw);
    } catch (_) {
      return false;
    }
  }

  Future<bool> saveInjections(List<Injection> items) =>
      _save(kInjections, () => [for (final e in items) e.toJson()]);

  Future<bool> saveCompounds(List<CompoundDefinition> items) =>
      _save(kCompounds, () => [for (final e in items) e.toJson()]);

  Future<bool> saveReminders(List<Reminder> items) =>
      _save(kReminders, () => [for (final e in items) e.toJson()]);

  Future<bool> saveBloodwork(List<BloodworkEntry> items) =>
      _save(kBloodwork, () => [for (final e in items) e.toJson()]);

  /// Writes one collection, encoded synchronously (the state at call time).
  /// False if encoding or the write failed. A key held back by [unsafeKeys]
  /// is skipped and counts as success — the load banner already said its
  /// changes won't be kept.
  Future<bool> _save(String key, List<Object?> Function() toJson) async {
    if (_unsafeKeys.contains(key)) return true;
    try {
      final text = jsonEncode(toJson());
      return await (await _prefs()).setString(key, text);
    } catch (_) {
      return false;
    }
  }

  /// The wizard-owned custom site lists. An entry that isn't valid JSON
  /// reads as empty.
  Future<CustomSites> readCustomSites() async {
    final prefs = await _prefs();
    return (im: _readSites(prefs, kCustomSitesIM), subQ: _readSites(prefs, kCustomSitesSubQ));
  }

  static List<String> _readSites(SharedPreferences prefs, String key) {
    final raw = prefs.getString(key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// False if either write failed.
  Future<bool> writeCustomSites(CustomSites sites) async {
    try {
      final prefs = await _prefs();
      final im = await prefs.setString(kCustomSitesIM, jsonEncode(sites.im));
      final subQ = await prefs.setString(kCustomSitesSubQ, jsonEncode(sites.subQ));
      return im && subQ;
    } catch (_) {
      return false;
    }
  }

  /// Raw text set aside by a lossy load, keyed by prefs key (carried out in
  /// full backups for manual recovery).
  Future<Map<String, String>> setAsideData() async {
    final prefs = await _prefs();
    final out = <String, String>{};
    for (final k in prefs.getKeys()) {
      final v = prefs.get(k);
      if (v is String && dataKeys.any((d) => k.startsWith(unreadableKeyPrefix(d)))) {
        out[k] = v;
      }
    }
    return out;
  }
}
