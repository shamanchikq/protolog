import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/engine/reminder_notification_plan.dart';
import 'package:protolog_tracker/engine/reminder_schedule.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/services/reminder_notifications.dart';

import '../support/fakes.dart';

final _now = DateTime(2026, 5, 17, 20, 0); // Sun

Reminder _interval(String id, int seed, {bool enabled = true}) => Reminder(
      id: id,
      compoundBase: 'Testosterone',
      compoundEster: 'Enanthate',
      intervalDays: 3.5,
      hour: 8,
      minute: 0,
      enabled: enabled,
      anchorDate: DateTime(2026, 5, 18, 8, 0),
      notificationSeed: seed,
    );

Reminder _custom(String id, int seed) => Reminder(
      id: id,
      compoundBase: 'BPC-157',
      compoundEster: 'None',
      scheduleMode: 'custom',
      intervalDays: 0,
      hour: 0,
      minute: 0,
      customSlots: const [
        ReminderSlot(weekday: 1, hour: 8, minute: 0),
        ReminderSlot(weekday: 4, hour: 8, minute: 0),
      ],
      enabled: true,
      notificationSeed: seed,
    );

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

class _Harness {
  _Harness({FakeNotificationBackend? backend}) : backend = backend ?? FakeNotificationBackend() {
    service = ReminderNotificationService(
      backend: this.backend,
      injections: () => injections,
      onScheduleError: errors.add,
      clock: () => _now,
      afterFirstFrame: (cb) => cb(),
    );
  }

  final FakeNotificationBackend backend;
  late final ReminderNotificationService service;
  var injections = <Injection>[];
  final errors = <Object>[];
  final taps = <(String?, String?)>[];

  Future<void> init() => service.init(onTap: (p, a) => taps.add((p, a)));
}

List<String> _sweep(int base) =>
    [for (var i = 0; i < kNotificationIdsPerReminder; i++) 'cancel:${base + i}'];

void main() {
  test('reschedule sweeps the whole id range, then schedules the plan', () async {
    final h = _Harness();
    await h.init();
    final r = _interval('r', 100);

    await h.service.reschedule(r);

    final plan = planReminderNotifications(r, _now, injections: const []);
    expect(h.backend.calls, [
      'init',
      ..._sweep(100),
      for (final p in plan) 'schedule:${p.id}',
    ]);
    expect(h.backend.pending.keys, [for (var i = 0; i < 10; i++) 100 + i]);
    expect(h.backend.pending[100]!.when, DateTime(2026, 5, 18, 8, 0));
    expect(h.errors, isEmpty);
  });

  test('queued jobs never interleave: a sweep cannot wipe a fresh schedule', () async {
    final h = _Harness()..backend.slowCancel = true;
    await h.init();
    final a = _interval('a', 100);
    final b = _custom('b', 500);

    // Fire-and-forget, as the app does.
    h.service.reschedule(a);
    h.service.reschedule(b);
    h.service.reschedule(a);
    await h.service.idle;

    final calls = h.backend.calls.skip(1).toList();
    final planA = planReminderNotifications(a, _now, injections: const []);
    final planB = planReminderNotifications(b, _now, injections: const []);
    expect(calls, [
      ..._sweep(100), for (final p in planA) 'schedule:${p.id}',
      ..._sweep(500), for (final p in planB) 'schedule:${p.id}',
      ..._sweep(100), for (final p in planA) 'schedule:${p.id}',
    ]);
    expect(h.backend.pending.keys.toSet(),
        {for (final p in [...planA, ...planB]) p.id});
  });

  test('jobs queued before init finishes wait for it', () async {
    final h = _Harness()..backend.initGate = Completer<void>();
    final init = h.init();
    h.service.reschedule(_interval('r', 100));
    await pumpEventQueue();
    expect(h.backend.calls, ['init']);

    h.backend.initGate!.complete();
    await init;
    await h.service.idle;
    expect(h.backend.cancelCalls, hasLength(kNotificationIdsPerReminder));
    expect(h.backend.scheduleCalls, hasLength(kIntervalNotificationCount));
  });

  test('a failed init turns every job into a no-op', () async {
    final h = _Harness()..backend.failInit = true;
    await h.init();
    expect(h.service.ready, isFalse);

    h.service.reschedule(_interval('r', 100));
    h.service.rescheduleAll([_custom('c', 200)]);
    h.service.cancel(_interval('r', 100));
    await h.service.idle;

    expect(h.backend.calls, ['init']);
    expect(h.backend.permissionRequests, 0);
  });

  test('a failing job does not block the jobs after it', () async {
    final h = _Harness()..backend.failCancelIds = {103};
    await h.init();
    h.service.reschedule(_interval('a', 100));
    h.service.reschedule(_interval('b', 300));
    await h.service.idle;

    // a's sweep stopped at the failing cancel and nothing was scheduled.
    expect(h.backend.cancelCalls.where((c) => c.startsWith('cancel:10')), hasLength(4));
    expect(h.backend.pending.keys, [for (var i = 0; i < 10; i++) 300 + i]);
  });

  test('a disabled reminder is only cancelled; rescheduleAll skips it', () async {
    final h = _Harness();
    await h.init();
    await h.service.reschedule(_interval('off', 100, enabled: false));
    expect(h.backend.cancelCalls, hasLength(kNotificationIdsPerReminder));
    expect(h.backend.scheduleCalls, isEmpty);

    h.backend.calls.clear();
    h.service.rescheduleAll([_interval('off', 100, enabled: false), _interval('on', 300)]);
    await h.service.idle;
    expect(h.backend.cancelCalls.first, 'cancel:300');
    expect(h.backend.scheduleCalls, hasLength(10));
  });

  test('cancel sweeps every id the reminder could have used', () async {
    final h = _Harness();
    await h.init();
    await h.service.cancel(_custom('c', 700));
    expect(h.backend.calls.skip(1), _sweep(700));
  });

  test('one bad occurrence is reported once and the rest still go out', () async {
    final h = _Harness()..backend.failScheduleIds = {101, 104};
    await h.init();
    await h.service.reschedule(_interval('r', 100));
    expect(h.backend.scheduleCalls, hasLength(10));
    expect(h.backend.pending, hasLength(8));
    expect(h.errors, hasLength(1));
    expect('${h.errors.single}', contains('bad 101'));
  });

  test('exact alarms when permitted, inexact otherwise or on error', () async {
    final h = _Harness();
    await h.init();
    await h.service.reschedule(_interval('r', 100));
    expect(h.backend.exactFlags.toSet(), {true});

    h.backend
      ..exact = false
      ..exactFlags.clear();
    await h.service.reschedule(_interval('r', 100));
    expect(h.backend.exactFlags.toSet(), {false});

    h.backend
      ..exactError = StateError('old android')
      ..exactFlags.clear();
    await h.service.reschedule(_interval('r', 100));
    expect(h.backend.exactFlags.toSet(), {false});
  });

  test('the body uses the injections current when the job runs', () async {
    final h = _Harness()..backend.initGate = Completer<void>();
    h.init();
    h.service.reschedule(_interval('r', 100));
    h.injections = [
      Injection(id: 'i', compoundId: 'test_e', date: DateTime(2026, 5, 14), dosage: 150, snapshot: _testE),
    ];
    h.backend.initGate!.complete();
    await h.service.idle;
    expect(h.backend.pending[100]!.body, endsWith('last dose 150 mg'));
  });

  test('init delivers the launch tap and then asks for permission', () async {
    final h = _Harness()..backend.launch = (payload: 'r1', actionId: 'skip');
    await h.init();
    expect(h.service.ready, isTrue);
    expect(h.taps, [('r1', 'skip')]);
    expect(h.backend.permissionRequests, 1);

    // Later taps arrive through the handler given to the plugin.
    h.backend.onTap!('r2', null);
    expect(h.taps.last, ('r2', null));
  });
}
