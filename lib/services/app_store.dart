import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:shared_preferences/shared_preferences.dart';

import '../data.dart';
import '../engine/migrations.dart';
import '../engine/record_validation.dart';
import '../engine/stored_data.dart';
import '../models.dart';
import 'custom_sites_store.dart';

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
    CustomSitesStore sites = const CustomSitesStore(),
  })  : _prefs = prefs ?? SharedPreferences.getInstance,
        _clock = clock ?? DateTime.now,
        _sites = sites;

  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _clock;

  /// The wizard's custom-site storage; backups read and write it through
  /// here so there is one owner of those keys.
  final CustomSitesStore _sites;

  static const kInjections = 'injections';
  static const kCompounds = 'compounds';
  static const kReminders = 'reminders';
  static const kBloodwork = 'bloodwork';

  /// Collections persisted as JSON lists, loaded through decodeStoredList.
  static const dataKeys = [kInjections, kCompounds, kReminders, kBloodwork];

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

    // Fix-ups for older data — G7 spelling, B6 duplicate compounds, legacy
    // 'temp' links — saved once; the next load finds nothing to do.
    final m = migrateRecords(
      injections: inj.items,
      compounds: raw[kCompounds] == null ? List.of(INITIAL_COMPOUNDS) : comp.items,
      reminders: rem.items,
    );
    if (m.injectionsChanged) await saveInjections(m.injections);
    if (m.compoundsChanged) await saveCompounds(m.compounds);
    // Also freezes notification-id seeds for reminders saved before the seed
    // existed, while id.hashCode still matches what was scheduled.
    if (m.remindersChanged || m.reminders.any((r) => r.notificationSeed == null)) {
      await saveReminders(m.reminders);
    }

    return LoadResult(
      injections: m.injections,
      compounds: m.compounds,
      reminders: m.reminders,
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

  Future<bool> saveInjections(List<Injection> items) => _save(kInjections, items);

  Future<bool> saveCompounds(List<CompoundDefinition> items) => _save(kCompounds, items);

  Future<bool> saveReminders(List<Reminder> items) => _save(kReminders, items);

  Future<bool> saveBloodwork(List<BloodworkEntry> items) => _save(kBloodwork, items);

  /// A collection longer than this is JSON-encoded on a background isolate
  /// (E4: a long injection history re-encoded on every change janked the
  /// UI); a shorter one inline, where the isolate hop would cost more.
  static const kIsolateEncodeThreshold = 300;

  // Per key, the last write queued: writes land in call order even when a
  // big background encode finishes after a later, smaller one.
  final Map<String, Future<bool>> _lastWrite = {};

  /// Writes one collection as it is at call time (the records are
  /// immutable, so a shallow copy is a snapshot). False if encoding or the
  /// write failed. A key held back by [unsafeKeys] is skipped and counts as
  /// success — the load banner already said its changes won't be kept.
  Future<bool> _save(String key, List<Object> items) {
    if (_unsafeKeys.contains(key)) return Future.value(true);
    final snapshot = List<Object>.of(items);
    final Future<String?> text = snapshot.length > kIsolateEncodeThreshold
        ? compute(_encode, snapshot).then<String?>((t) => t, onError: (Object _) => null)
        : Future.value(_tryEncode(snapshot));
    final previous = _lastWrite[key] ?? Future.value(true);
    final write = previous.then((_) async {
      try {
        final t = await text;
        return t != null && await (await _prefs()).setString(key, t);
      } catch (_) {
        return false;
      }
    });
    _lastWrite[key] = write;
    return write;
  }

  /// jsonEncode calls each record's toJson. Top-level-safe for [compute].
  static String _encode(List<Object> items) => jsonEncode(items);

  static String? _tryEncode(List<Object> items) {
    try {
      return _encode(items);
    } catch (_) {
      return null; // e.g. a non-finite double
    }
  }

  /// The wizard's custom site lists ([CustomSitesStore.load]: unreadable
  /// data reads as empty).
  Future<CustomSites> readCustomSites() => _sites.load();

  /// Writes both lists through [CustomSitesStore]; false if that threw.
  Future<bool> writeCustomSites(CustomSites sites) async {
    try {
      await _sites.save(sites);
      return true;
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
