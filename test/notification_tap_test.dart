import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/engine/reminder_schedule.dart';
import 'package:protolog_tracker/main.dart';
import 'package:protolog_tracker/ui/views/add_injection_wizard.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

// B14: a notification's payload names the occurrence it announced, and the
// tap handler acts on that occurrence. (Bare-id payloads from older
// releases are covered in main_screen_test.dart.)

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<FakeNotificationBackend> _boot(WidgetTester tester) async {
  final b = FakeNotificationBackend();
  await tester.pumpWidget(MaterialApp(home: MainScreen(notificationBackend: b)));
  await _settle(tester);
  return b;
}

/// Interval reminder, 3.5 days, seed 500, next dose two days ahead at 08:00.
Map<String, Object?> _reminder(DateTime anchor) => {
      'id': 'r1',
      'compoundBase': 'Testosterone',
      'compoundEster': 'Enanthate',
      'scheduleMode': 'interval',
      'intervalDays': 3.5,
      'hour': 8,
      'minute': 0,
      'customSlots': [],
      'enabled': true,
      'anchorDate': anchor.toIso8601String(),
      'notificationSeed': 500,
    };

DateTime _anchor() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + 2, 8, 0);
}

Future<DateTime> _storedAnchor() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = (jsonDecode(prefs.getString('reminders')!) as List).single as Map;
  return DateTime.parse(stored['anchorDate'] as String);
}

void main() {
  testWidgets('Skip acts on the announced occurrence; a repeated delivery changes nothing',
      (tester) async {
    final anchor = _anchor();
    SharedPreferences.setMockInitialValues({'reminders': jsonEncode([_reminder(anchor)])});
    final backend = await _boot(tester);

    final payload = backend.pending[500]!.payload;
    expect(ReminderPayload.parse(payload), ReminderPayload('r1', occurrence: anchor));

    backend.onTap!(payload, 'skip');
    await _settle(tester);
    final next = anchor.add(const Duration(hours: 84));
    expect(await _storedAnchor(), next);
    expect(backend.pending[500]!.when, next);
    expect(find.text('Skipped Testosterone — rescheduled'), findsOneWidget);

    // The same Skip again (a re-delivered launch intent, or the old
    // notification still in the shade): that dose is already skipped.
    await tester.pump(const Duration(seconds: 5));
    await _settle(tester);
    backend.calls.clear();
    backend.onTap!(payload, 'skip');
    await _settle(tester);
    expect(await _storedAnchor(), next);
    expect(backend.cancelCalls, isEmpty, reason: 'nothing to reschedule');
    expect(find.text('Skipped Testosterone'), findsOneWidget);
  });

  testWidgets('Log now with a current payload opens the wizard for that compound',
      (tester) async {
    SharedPreferences.setMockInitialValues({'reminders': jsonEncode([_reminder(_anchor())])});
    final backend = await _boot(tester);

    backend.onTap!(backend.pending[500]!.payload, 'log');
    await _settle(tester);
    expect(find.byType(AddInjectionWizard), findsOneWidget);
  });

  testWidgets('a payload for an unknown reminder is ignored', (tester) async {
    SharedPreferences.setMockInitialValues({'reminders': jsonEncode([_reminder(_anchor())])});
    final backend = await _boot(tester);
    backend.calls.clear();

    backend.onTap!(const ReminderPayload('gone').encode(), 'skip');
    await _settle(tester);
    expect(backend.calls, isEmpty);
    expect(find.textContaining('Skipped'), findsNothing);
  });
}
