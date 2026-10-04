import 'dart:async';

import 'package:protolog_tracker/engine/reminder_notification_plan.dart';
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

  @override
  Future<void> initialize(NotificationTapHandler onTap) async {
    calls.add('init');
    if (initGate != null) await initGate!.future;
    if (failInit) throw StateError('no plugin');
    this.onTap = onTap;
  }

  @override
  Future<({String? payload, String? actionId})?> launchTap() async => launch;

  @override
  Future<void> requestPermission() async => permissionRequests++;

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
  Future<void> cancel(int id) async {
    if (slowCancel) await Future<void>.delayed(Duration.zero);
    calls.add('cancel:$id');
    if (failCancelIds.contains(id)) throw StateError('cancel $id');
    pending.remove(id);
  }

  Iterable<String> get scheduleCalls => calls.where((c) => c.startsWith('schedule:'));
  Iterable<String> get cancelCalls => calls.where((c) => c.startsWith('cancel:'));
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
