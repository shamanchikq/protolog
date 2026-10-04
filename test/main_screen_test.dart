import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/engine/reminder_schedule.dart';
import 'package:protolog_tracker/main.dart';
import 'package:protolog_tracker/services/app_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

// End-to-end checks of MainScreen's load, mutation and notification paths
// against mocked prefs.

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The real app: the notification plugin has no platform side in tests, so
/// init fails and the app must still load (A7).
Future<void> _boot(WidgetTester tester) async {
  await tester.pumpWidget(const ProtoLogApp());
  await _settle(tester);
}

/// MainScreen with a fake notification backend (and optionally a store).
Future<FakeNotificationBackend> _bootFake(WidgetTester tester,
    {AppStore? store, FakeNotificationBackend? backend}) async {
  final b = backend ?? FakeNotificationBackend();
  await tester.pumpWidget(MaterialApp(home: MainScreen(store: store, notificationBackend: b)));
  await _settle(tester);
  return b;
}

const _reminderNoSeed = {
  'id': 'r1',
  'compoundBase': 'Testosterone',
  'compoundEster': 'Enanthate',
  'scheduleMode': 'interval',
  'intervalDays': 3.5,
  'hour': 8,
  'minute': 0,
  'customSlots': [],
  'enabled': true,
};

/// An interval reminder (seed 500) due two days from now at 08:00.
Map<String, Object?> _dueReminder(DateTime anchor, {bool enabled = true, String id = 'r1', int seed = 500}) => {
      ..._reminderNoSeed,
      'id': id,
      'enabled': enabled,
      'anchorDate': anchor.toIso8601String(),
      'notificationSeed': seed,
    };

DateTime _anchor() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + 2, 8, 0);
}

Map<String, dynamic> _storedReminder(SharedPreferences prefs) =>
    (jsonDecode(prefs.getString('reminders')!) as List).single as Map<String, dynamic>;

void main() {
  testWidgets('fresh install loads to the dashboard and writes nothing',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _boot(tester);

    expect(find.text('Log dose'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  testWidgets('unreadable data is set aside verbatim and the user is told',
      (tester) async {
    SharedPreferences.setMockInitialValues({'injections': 'not json {'});
    await _boot(tester);

    expect(find.text('Log dose'), findsOneWidget);
    expect(find.textContaining("Couldn't read saved injections"), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final aside = prefs.getKeys().where((k) => k.startsWith('injections_unreadable_'));
    expect(aside, hasLength(1));
    expect(prefs.getString(aside.single), 'not json {');
    // The original stays untouched until the user changes something.
    expect(prefs.getString('injections'), 'not json {');
  });

  testWidgets('legacy reminders get their notification seed frozen on load',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'reminders': jsonEncode([_reminderNoSeed]),
    });
    await _boot(tester);

    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString('reminders')!) as List;
    expect(stored.single['notificationSeed'], 'r1'.hashCode);
  });

  testWidgets('fresh install: the first lab result is kept and saved', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _bootFake(tester);

    await tester.ensureVisible(find.text('+ Add'));
    await tester.tap(find.text('+ Add'));
    await _settle(tester); // pumpAndSettle can't: the chart spins while its isolate runs
    await tester.tap(find.text('Total T'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('bloodwork-value')), '18');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await _settle(tester);

    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString('bloodwork')!) as List;
    expect(stored.single['marker'], 'Total T');
    expect(stored.single['value'], 18);
  });

  testWidgets('boot reschedules enabled reminders only, sweep before schedule', (tester) async {
    final anchor = _anchor();
    SharedPreferences.setMockInitialValues({
      'reminders': jsonEncode([
        _dueReminder(anchor),
        _dueReminder(anchor, id: 'off', seed: 900, enabled: false),
      ]),
    });
    final backend = await _bootFake(tester);

    expect(backend.calls.first, 'init');
    final sweep = backend.calls.skip(1).take(kNotificationIdsPerReminder).toList();
    expect(sweep, [for (var i = 0; i < kNotificationIdsPerReminder; i++) 'cancel:${500 + i}']);
    expect(backend.pending.keys, [for (var i = 0; i < 10; i++) 500 + i]);
    expect(backend.pending[500]!.when, anchor);
    expect(backend.calls.any((c) => c.contains(':9')), isFalse,
        reason: 'the disabled reminder is left alone at boot');
  });

  testWidgets('notification Skip advances an interval reminder, saves and reschedules',
      (tester) async {
    final anchor = _anchor();
    SharedPreferences.setMockInitialValues({'reminders': jsonEncode([_dueReminder(anchor)])});
    final backend = await _bootFake(tester);
    backend.calls.clear();

    backend.onTap!('r1', 'skip');
    await _settle(tester);

    final next = anchor.add(const Duration(hours: 84));
    final prefs = await SharedPreferences.getInstance();
    expect(DateTime.parse(_storedReminder(prefs)['anchorDate'] as String), next);
    expect(backend.cancelCalls, hasLength(kNotificationIdsPerReminder));
    expect(backend.pending[500]!.when, next);
    expect(find.text('Skipped Testosterone — rescheduled'), findsOneWidget);
  });

  testWidgets('a tap that launched the app is handled once data has loaded', (tester) async {
    final anchor = _anchor();
    SharedPreferences.setMockInitialValues({'reminders': jsonEncode([_dueReminder(anchor)])});
    await _bootFake(tester,
        backend: FakeNotificationBackend()..launch = (payload: 'r1', actionId: 'skip'));

    final prefs = await SharedPreferences.getInstance();
    expect(DateTime.parse(_storedReminder(prefs)['anchorDate'] as String),
        anchor.add(const Duration(hours: 84)));
  });

  testWidgets('a failed save is reported instead of failing silently', (tester) async {
    final anchor = _anchor();
    final prefs = await FlakyPrefs.withValues({'reminders': jsonEncode([_dueReminder(anchor)])},
        refuse: {'reminders'});
    final backend = await _bootFake(tester, store: AppStore(prefs: () async => prefs));

    backend.onTap!('r1', 'skip');
    await _settle(tester);
    // The "Skipped …" snackbar goes first; the failure is queued behind it.
    expect(find.text('Skipped Testosterone — rescheduled'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);

    expect(find.textContaining("Couldn't save your latest change"), findsOneWidget);
    expect(prefs.writes, contains('reminders'));
    expect(DateTime.parse(_storedReminder(prefs)['anchorDate'] as String), anchor);
  });

  testWidgets('notifications that cannot start are reported', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = await _bootFake(tester, backend: FakeNotificationBackend()..failInit = true);

    expect(find.textContaining("Notifications couldn't start"), findsOneWidget);
    expect(backend.calls, ['init']);
  });
}
