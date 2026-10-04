import 'dart:async';

import 'package:protolog_tracker/engine/reminder_notification_plan.dart';
import 'package:protolog_tracker/services/custom_sites_store.dart';
import 'package:protolog_tracker/services/reminder_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records every call and keeps the platform's pending set, so tests can
/// check both ordering and the end state.
class FakeNotificationBackend implements NotificationBackend {
  final calls = <String>[];
  final pending = <int, PlannedNotification>{};
  final exactFlags = <bool>[];

  bool failInit = false;
  Completer<void>? initGate;
  ({String? payload, String? actionId})? launch;
  Object? exactError;
  bool exact = true;
  Set<int> failScheduleIds = {};
  Set<int> failCancelIds = {};

  /// Makes each cancel yield to the event loop, like a platform call.
  bool slowCancel = false;
  int permissionRequests = 0;
  NotificationTapHandler? onTap;

  /// Delivered notifications still showing in the shade.
  final displayed = <int>{};

  /// Makes pendingIds throw.
  bool failPending = false;

  /// The platform delivers [id]: it shows in the shade, and a one-shot stops
  /// being pending (a weekly repeat stays pending).
  void deliver(int id) {
    final n = pending[id];
    if (n == null) return;
    displayed.add(id);
    if (!n.repeatsWeekly) pending.remove(id);
  }

  @override
  Future<void> initialize(NotificationTapHandler onTap) async {
    calls.add('init');
    if (initGate != null) await initGate!.future;
    if (failInit) throw StateError('no plugin');
    this.onTap = onTap;
  }

  @override
  Future<({String? payload, String? actionId})?> launchTap() async => launch;

  /// What areNotificationsEnabled reports (null: the platform can't tell).
  bool? enabled = true;

  /// When set, a permission request changes [enabled] to this.
  bool? grantOnRequest;

  @override
  Future<bool?> requestPermission() async {
    permissionRequests++;
    if (grantOnRequest != null) enabled = grantOnRequest;
    return enabled;
  }

  @override
  Future<bool?> areNotificationsEnabled() async => enabled;

  @override
  Future<bool> canScheduleExact() async {
    if (exactError != null) throw exactError!;
    return exact;
  }

  @override
  Future<void> schedule(PlannedNotification n, {required bool exact, required DateTime now}) async {
    calls.add('schedule:${n.id}');
    if (failScheduleIds.contains(n.id)) throw StateError('bad ${n.id}');
    exactFlags.add(exact);
    pending[n.id] = n;
  }

  @override
  Future<Set<int>> pendingIds() async {
    calls.add('pending');
    if (failPending) throw StateError('no pending list');
    return pending.keys.toSet();
  }

  @override
  Future<void> cancel(int id) async {
    if (slowCancel) await Future<void>.delayed(Duration.zero);
    calls.add('cancel:$id');
    if (failCancelIds.contains(id)) throw StateError('cancel $id');
    pending.remove(id);
    displayed.remove(id);
  }

  Iterable<String> get scheduleCalls => calls.where((c) => c.startsWith('schedule:'));
  Iterable<String> get cancelCalls => calls.where((c) => c.startsWith('cancel:'));
}

/// A [CustomSitesStore] whose writes fail.
class ThrowingSitesStore extends CustomSitesStore {
  const ThrowingSitesStore();

  @override
  Future<void> save(CustomSites sites) async => throw StateError('disk full');
}

/// Real mock prefs whose writes can be made to fail per key prefix.
class FlakyPrefs implements SharedPreferences {
  FlakyPrefs(this._inner, {this.refuse = const {}, this.throwOn = const {}});
  final SharedPreferences _inner;

  /// setString returns false for keys starting with one of these.
  Set<String> refuse;

  /// setString throws for keys starting with one of these.
  Set<String> throwOn;

  final writes = <String>[];

  /// Fresh mock prefs holding [initial], wrapped.
  static Future<FlakyPrefs> withValues(Map<String, Object> initial,
      {Set<String> refuse = const {}, Set<String> throwOn = const {}}) async {
    SharedPreferences.setMockInitialValues(initial);
    return FlakyPrefs(await SharedPreferences.getInstance(), refuse: refuse, throwOn: throwOn);
  }

  @override
  Object? get(String key) => _inner.get(key);
  @override
  String? getString(String key) => _inner.getString(key);
  @override
  Set<String> getKeys() => _inner.getKeys();
  @override
  Future<bool> setString(String key, String value) async {
    writes.add(key);
    if (throwOn.any(key.startsWith)) throw StateError('disk full');
    if (refuse.any(key.startsWith)) return false;
    return _inner.setString(key, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
