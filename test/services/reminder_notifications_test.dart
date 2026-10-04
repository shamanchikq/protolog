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

Reminder _custom(String id, int seed, {DateTime? acknowledgedUntil}) => Reminder(
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
      acknowledgedUntil: acknowledgedUntil,
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

Injection _dose(double mg, DateTime at) =>
    Injection(id: 'i$mg', compoundId: 'test_e', date: at, dosage: mg, snapshot: _testE);

class _Harness {
  _Harness({FakeNotificationBackend? backend}) : backend = backend ?? FakeNotificationBackend() {
    service = ReminderNotificationService(
      backend: this.backend,
      injections: () => injections,
      onScheduleError: errors.add,
      clock: () => now,
      afterFirstFrame: (cb) => cb(),
    );
  }

  final FakeNotificationBackend backend;
  late final ReminderNotificationService service;
  var now = _now;
  var injections = <Injection>[];
  final errors = <Object>[];
  final taps = <(String?, String?)>[];

  Future<void> init() => service.init(onTap: (p, a) => taps.add((p, a)));

  /// A new process on the same platform state (the app was relaunched).
  _Harness relaunch() => _Harness(backend: backend)
    ..now = now
    ..injections = injections;

  List<PlannedNotification> plan(Reminder r) =>
      planReminderNotifications(r, now, injections: injections);
}

List<String> _sweep(int base) =>
    [for (var i = 0; i < kNotificationIdsPerReminder; i++) 'cancel:${base + i}'];

List<String> _sends(List<PlannedNotification> plan) => [for (final p in plan) 'schedule:${p.id}'];

void main() {
  group('reconcileAll (launch, resume, restore)', () {
    test('first run: reads the pending ids and sends the whole plan, cancelling nothing',
        () async {
      final h = _Harness();
      await h.init();
      final a = _interval('a', 100);
      final b = _custom('b', 500);

      await h.service.reconcileAll([a, b]);

      expect(h.backend.calls, ['init', 'pending', ..._sends(h.plan(a)), ..._sends(h.plan(b))]);
      expect(h.backend.pending.keys.toSet(), {for (final p in [...h.plan(a), ...h.plan(b)]) p.id});
      expect(h.backend.pending[100]!.when, DateTime(2026, 5, 18, 8, 0));
      expect(h.errors, isEmpty);
    });

    test('nothing changed: a second reconcile only reads the pending ids', () async {
      final h = _Harness();
      await h.init();
      final rs = [_interval('a', 100), _custom('b', 500)];
      await h.service.reconcileAll(rs);
      h.backend.calls.clear();

      await h.service.reconcileAll(rs);

      expect(h.backend.calls, ['pending']);
    });

    test('a launch never dismisses a delivered notification (B18)', () async {
      final h = _Harness();
      await h.init();
      final a = _interval('a', 100);
      await h.service.reconcileAll([a]);

      // The first dose fires and sits in the shade; the user opens the app.
      h.backend.deliver(100);
      final next = h.relaunch()..now = DateTime(2026, 5, 18, 9, 0);
      await next.init();
      h.backend.calls.clear();
      await next.service.reconcileAll([a]);

      expect(h.backend.displayed, {100});
      expect(h.backend.cancelCalls, isEmpty);
      // The interval plan moved on by one: every id is re-sent in place.
      expect(h.backend.scheduleCalls, _sends(next.plan(a)));
      expect(h.backend.pending[100]!.when, DateTime(2026, 5, 21, 20, 0));
    });

    test('a cold start re-sends even unchanged pending notifications (force-stop heals)',
        () async {
      final h = _Harness();
      await h.init();
      final a = _interval('a', 100);
      await h.service.reconcileAll([a]);

      final next = h.relaunch();
      await next.init();
      h.backend.calls.clear();
      await next.service.reconcileAll([a]);

      expect(h.backend.calls, ['pending', ..._sends(next.plan(a))]);
    });

    test('cancels only pending ids no enabled reminder plans', () async {
      final h = _Harness();
      await h.init();
      final a = _interval('a', 100);
      final off = _interval('off', 300, enabled: false);
      await h.service.reconcileAll([a, _interval('off', 300)]);
      h.backend
        ..deliver(301) // shown, no longer pending: left alone
        ..pending[900] = h.plan(a).first; // an old seed's leftover (N6)
      h.backend.calls.clear();

      await h.service.reconcileAll([a, off]);

      expect(h.backend.cancelCalls.toSet(),
          {for (var i = 0; i < 10; i++) if (i != 1) 'cancel:${300 + i}', 'cancel:900'});
      expect(h.backend.scheduleCalls, isEmpty);
      expect(h.backend.displayed, {301});
      expect(h.backend.pending.keys.toSet(), {for (final p in h.plan(a)) p.id});
    });

    test('a changed body is re-sent in place (B19)', () async {
      final h = _Harness();
      await h.init();
      final a = _interval('a', 100);
      await h.service.reconcileAll([a]);
      h.backend.calls.clear();

      h.injections = [_dose(150, DateTime(2026, 5, 14))];
      await h.service.reconcileAll([a]);

      expect(h.backend.calls, ['pending', ..._sends(h.plan(a))]);
      expect(h.backend.pending[100]!.body, endsWith('last dose 150 mg'));
    });

    test("acked one-shots that fired are topped up on resume (N7)", () async {
      final h = _Harness();
      await h.init();
      // Monday's slot was acknowledged: 8 weekly one-shots from next Monday.
      final b = _custom('b', 500, acknowledgedUntil: DateTime(2026, 5, 18, 8, 0));
      await h.service.reconcileAll([b]);
      final mondayShots = [for (var w = 0; w < kAckedSlotOneShots; w++) 500 + customSlotIdOffset(0, oneShot: w)];
      expect(h.backend.pending.keys, containsAll(mondayShots));

      // Next Monday's one-shot fires; the app comes back on Tuesday.
      h.backend.deliver(mondayShots.first);
      h.now = DateTime(2026, 5, 26, 9, 0);
      h.backend.calls.clear();
      await h.service.reconcileAll([b]);

      // The ack has passed: Monday is a weekly repeat again, the one-shots go.
      final weekly = 500 + customSlotIdOffset(0);
      expect(h.backend.pending[weekly]!.repeatsWeekly, isTrue);
      expect(h.backend.pending.keys, isNot(contains(mondayShots[1])));
      expect(h.backend.displayed, {mondayShots.first});
    });

    test('if the pending ids cannot be read, falls back to the complete sweep', () async {
      final h = _Harness()..backend.failPending = true;
      await h.init();
      final a = _interval('a', 100);
      final off = _interval('off', 300, enabled: false);

      await h.service.reconcileAll([a, off]);

      expect(h.backend.calls,
          ['init', 'pending', ..._sweep(100), ..._sweep(300), ..._sends(h.plan(a))]);
    });
  });

  group('reschedule (an explicit change to one reminder)', () {
    test('reconciles only its own id range', () async {
      final h = _Harness();
      await h.init();
      final a = _interval('a', 100);
      await h.service.reconcileAll([a, _interval('other', 300)]);
      h.backend.pending[150] = h.plan(a).first; // stale id in a's range
      h.backend.calls.clear();

      final skipped = a.copyWith(anchorDate: DateTime(2026, 5, 21, 20, 0));
      await h.service.reschedule(skipped, previous: a);

      expect(h.backend.calls, ['pending', 'cancel:150', ..._sends(h.plan(skipped))]);
      expect(h.backend.pending.keys, containsAll([for (var i = 0; i < 10; i++) 300 + i]));
    });

    test('unchanged: sends nothing', () async {
      final h = _Harness();
      await h.init();
      final a = _interval('a', 100);
      await h.service.reschedule(a);
      h.backend.calls.clear();

      await h.service.reschedule(a, previous: a);

      expect(h.backend.calls, ['pending']);
    });

    test('a disabled reminder gets the complete sweep, shown ones included', () async {
      final h = _Harness();
      await h.init();
      final a = _interval('a', 100);
      await h.service.reschedule(a);
      h.backend.deliver(100);
      h.backend.calls.clear();

      await h.service.reschedule(a.copyWith(enabled: false), previous: a);

      expect(h.backend.calls, _sweep(100));
      expect(h.backend.pending, isEmpty);
      expect(h.backend.displayed, isEmpty);
    });

    test('a shape change sweeps every id before the new plan goes out', () async {
      final h = _Harness();
      await h.init();
      final a = _interval('a', 100);
      await h.service.reschedule(a);
      h.backend.calls.clear();

      final custom = _custom('a', 100);
      await h.service.reschedule(custom, previous: a);

      expect(h.backend.calls, [..._sweep(100), ..._sends(h.plan(custom))]);
      expect(h.backend.pending.keys.toSet(), {for (final p in h.plan(custom)) p.id});
    });

    test('a new id base sweeps the old range too', () async {
      final h = _Harness();
      await h.init();
      final a = _interval('a', 100);
      await h.service.reschedule(a);
      h.backend.calls.clear();

      final reseeded = a.copyWith(notificationSeed: 700);
      await h.service.reschedule(reseeded, previous: a);

      expect(h.backend.calls, [..._sweep(100), ..._sweep(700), ..._sends(h.plan(reseeded))]);
    });

    test('if the pending ids cannot be read, sweeps then sends', () async {
      final h = _Harness()..backend.failPending = true;
      await h.init();
      final a = _interval('a', 100);
      await h.service.reschedule(a);
      expect(h.backend.calls, ['init', 'pending', ..._sweep(100), ..._sends(h.plan(a))]);
    });
  });

  test('queued jobs never interleave: a sweep cannot wipe a fresh schedule', () async {
    final h = _Harness()..backend.slowCancel = true;
    await h.init();
    final a = _interval('a', 100);
    final b = _custom('b', 500);

    // Fire-and-forget, as the app does.
    h.service.reschedule(a);
    h.service.cancel(a);
    h.service.reschedule(b);
    h.service.reschedule(a);
    await h.service.idle;

    expect(h.backend.calls.skip(1), [
      'pending', ..._sends(h.plan(a)),
      ..._sweep(100),
      'pending', ..._sends(h.plan(b)),
      'pending', ..._sends(h.plan(a)),
    ]);
    expect(h.backend.pending.keys.toSet(), {for (final p in [...h.plan(a), ...h.plan(b)]) p.id});
  });

  test('jobs queued before init finishes wait for it', () async {
    final h = _Harness()..backend.initGate = Completer<void>();
    final init = h.init();
    h.service.reconcileAll([_interval('r', 100)]);
    await pumpEventQueue();
    expect(h.backend.calls, ['init']);

    h.backend.initGate!.complete();
    await init;
    await h.service.idle;
    expect(h.backend.scheduleCalls, hasLength(kIntervalNotificationCount));
  });

  test('a failed init turns every job into a no-op', () async {
    final h = _Harness()..backend.failInit = true;
    await h.init();
    expect(h.service.ready, isFalse);

    h.service.reschedule(_interval('r', 100));
    h.service.reconcileAll([_custom('c', 200)]);
    h.service.cancel(_interval('r', 100));
    await h.service.idle;

    expect(h.backend.calls, ['init']);
    expect(h.backend.permissionRequests, 0);
  });

  test('a failing job does not block the jobs after it', () async {
    final h = _Harness()..backend.failCancelIds = {103};
    await h.init();
    h.service.cancel(_interval('a', 100));
    h.service.reschedule(_interval('b', 300));
    await h.service.idle;

    // a's sweep stopped at the failing cancel; b still went out.
    expect(h.backend.cancelCalls, ['cancel:100', 'cancel:101', 'cancel:102', 'cancel:103']);
    expect(h.backend.pending.keys, [for (var i = 0; i < 10; i++) 300 + i]);
  });

  test('a failing reconcile cancel costs only that id', () async {
    final h = _Harness()..backend.failCancelIds = {900};
    await h.init();
    final a = _interval('a', 100);
    h.backend.pending
      ..[900] = PlannedNotification(id: 900, when: _now, title: 't', body: 'b', payload: 'x')
      ..[901] = PlannedNotification(id: 901, when: _now, title: 't', body: 'b', payload: 'x');

    await h.service.reconcileAll([a]);

    expect(h.backend.cancelCalls, ['cancel:900', 'cancel:901']);
    expect(h.backend.pending.keys.toSet(), {900, for (final p in h.plan(a)) p.id});
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

    // The next reconcile retries just the two that failed.
    h.backend
      ..failScheduleIds = {}
      ..calls.clear();
    await h.service.reconcileAll([_interval('r', 100)]);
    expect(h.backend.scheduleCalls, ['schedule:101', 'schedule:104']);
  });

  test('exact alarms when permitted, inexact otherwise or on error', () async {
    final h = _Harness();
    await h.init();
    await h.service.reschedule(_interval('r', 100));
    expect(h.backend.exactFlags.toSet(), {true});

    // A change of permission re-sends every notification in the new mode.
    h.backend
      ..exact = false
      ..exactFlags.clear();
    await h.service.reschedule(_interval('r', 100));
    expect(h.backend.exactFlags, List.filled(10, false));

    h.backend
      ..exact = true
      ..exactError = StateError('old android')
      ..exactFlags.clear();
    await h.service.reschedule(_interval('r', 100));
    expect(h.backend.exactFlags, isEmpty, reason: 'still inexact: nothing to re-send');
  });

  test('the body uses the injections current when the job runs', () async {
    final h = _Harness()..backend.initGate = Completer<void>();
    h.init();
    h.service.reschedule(_interval('r', 100));
    h.injections = [_dose(150, DateTime(2026, 5, 14))];
    h.backend.initGate!.complete();
    await h.service.idle;
    expect(h.backend.pending[100]!.body, endsWith('last dose 150 mg'));
  });

  test('reports the permission answer and reads whether notifications are on (B20)',
      () async {
    final answers = <bool?>[];
    final backend = FakeNotificationBackend()..enabled = false;
    final service = ReminderNotificationService(
      backend: backend,
      injections: () => const [],
      onPermissionResult: answers.add,
      afterFirstFrame: (cb) => cb(),
    );
    expect(await service.notificationsEnabled(), isNull, reason: 'not initialized');

    await service.init(onTap: (_, _) {});
    await pumpEventQueue();
    expect(answers, [false]);
    expect(await service.notificationsEnabled(), isFalse);

    backend.grantOnRequest = true;
    expect(await service.requestPermission(), isTrue);
    expect(await service.notificationsEnabled(), isTrue);

    backend.enabled = null;
    expect(await service.notificationsEnabled(), isNull, reason: "platform can't tell");
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
