import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../engine/reminder_notification_plan.dart';
import '../engine/reminder_schedule.dart';
import '../models.dart';

/// A notification tap (body or action button): the reminder id payload and
/// the action id (`'log'` / `'skip'`, null for a body tap).
typedef NotificationTapHandler = void Function(String? payload, String? actionId);

/// The slice of the notification plugin the reminder service uses, so tests
/// can substitute a fake.
abstract class NotificationBackend {
  /// Sets up time zones and the plugin; taps go to [onTap]. Throws if the
  /// plugin can't start.
  Future<void> initialize(NotificationTapHandler onTap);

  /// The tap that launched the app from a terminated state, if any.
  Future<({String? payload, String? actionId})?> launchTap();

  Future<void> requestPermission();

  /// Whether exact alarms are permitted (Android).
  Future<bool> canScheduleExact();

  /// Schedules one notification. [now] is the time the plan was made for.
  Future<void> schedule(PlannedNotification n, {required bool exact, required DateTime now});

  /// Cancels a pending (and removes a displayed) notification.
  Future<void> cancel(int id);
}

/// Reminder notifications: plugin init, the serial job queue, and
/// cancel-then-schedule per reminder from [planReminderNotifications].
///
/// All notification work runs one job at a time: a reminder's cancel sweep
/// must finish before its new schedule goes out, or the sweep (64
/// sequential calls) can wipe ids the schedule just created. The queue
/// starts with [init], so no job runs before the plugin and the platform
/// zone are ready; if init fails, every job is a no-op.
class ReminderNotificationService {
  ReminderNotificationService({
    required NotificationBackend backend,
    required List<Injection> Function() injections,
    this.onScheduleError,
    DateTime Function()? clock,
    void Function(VoidCallback)? afterFirstFrame,
  })  : _backend = backend,
        _injections = injections,
        _clock = clock ?? DateTime.now,
        _afterFirstFrame = afterFirstFrame ??
            ((cb) => WidgetsBinding.instance.addPostFrameCallback((_) => cb()));

  final NotificationBackend _backend;

  /// Read when a schedule job runs, so the body's "last dose" is current.
  final List<Injection> Function() _injections;
  final DateTime Function() _clock;
  final void Function(VoidCallback) _afterFirstFrame;

  /// Called once per reminder whose schedule partly failed, with the first
  /// error (the rest of that reminder's batch is still attempted).
  final void Function(Object error)? onScheduleError;

  Future<void> _chain = Future.value();
  bool _ready = false;

  /// The plugin initialized; until then (and forever after a failed init)
  /// queued jobs do nothing.
  bool get ready => _ready;

  /// Completes once every job queued so far has run.
  Future<void> get idle => _chain;

  /// Starts plugin init (call once, before queuing jobs); every job queued
  /// after this waits for it. Never throws. Taps — including the one that
  /// launched the app — go to [onTap]. Once ready, the notification
  /// permission is requested after the first frame, so the Activity can
  /// show the system dialog.
  Future<void> init({required NotificationTapHandler onTap}) {
    final started = _init(onTap);
    _chain = _chain.then((_) => started);
    return _chain;
  }

  Future<void> _init(NotificationTapHandler onTap) async {
    try {
      await _backend.initialize(onTap);
      _ready = true;
    } catch (_) {
      return;
    }
    try {
      final launch = await _backend.launchTap();
      if (launch != null) onTap(launch.payload, launch.actionId);
    } catch (_) {}
    _afterFirstFrame(requestPermission);
  }

  Future<void> requestPermission() async {
    try {
      await _backend.requestPermission();
    } catch (_) {
      // Permission request may fail on older Android versions; safe to ignore.
    }
  }

  /// Queues [job] behind all pending notification work (including init). A
  /// failing job never blocks the ones after it; if init failed, jobs are
  /// skipped.
  Future<void> _enqueue(Future<void> Function() job) {
    final run = _chain.then<void>((_) async {
      if (_ready) await job();
    });
    _chain = run.catchError((Object _) {});
    return _chain;
  }

  /// Cancel-then-schedule for one reminder (cancel only if it's disabled).
  Future<void> reschedule(Reminder r) => _enqueue(() async {
        await _cancelAll(r);
        if (r.enabled) await _schedule(r);
      });

  /// [reschedule] for every enabled reminder (disabled ones are left alone).
  void rescheduleAll(Iterable<Reminder> reminders) {
    for (final r in reminders) {
      if (r.enabled) reschedule(r);
    }
  }

  /// Cancels every id the reminder could have scheduled.
  Future<void> cancel(Reminder r) => _enqueue(() => _cancelAll(r));

  // Sweeps the reminder's whole id range regardless of its *current*
  // mode/slot count — a mode switch must not orphan ids scheduled under the
  // previous shape.
  Future<void> _cancelAll(Reminder r) async {
    for (var i = 0; i < kNotificationIdsPerReminder; i++) {
      await _backend.cancel(r.notificationIdBase + i);
    }
  }

  Future<void> _schedule(Reminder r) async {
    if (!r.enabled) return;
    final now = _clock();
    final plan = planReminderNotifications(r, now, injections: _injections());

    // Exact alarms when permitted (auto-granted on Android 13+ via
    // USE_EXACT_ALARM); inexact delivery can lag by up to an hour in Doze.
    var exact = false;
    try {
      exact = await _backend.canScheduleExact();
    } catch (_) {}

    // Per-call try so one bad occurrence doesn't drop the rest of the batch.
    Object? firstError;
    for (final n in plan) {
      try {
        await _backend.schedule(n, exact: exact, now: now);
      } catch (e) {
        firstError ??= e;
      }
    }
    if (firstError != null) onScheduleError?.call(firstError);
  }
}

/// [NotificationBackend] over flutter_local_notifications.
class LocalNotificationsBackend implements NotificationBackend {
  LocalNotificationsBackend([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> initialize(NotificationTapHandler onTap) async {
    tz.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // tz.local stays UTC: interval one-shots still fire at the right
      // instant; custom slots lose wall-clock anchoring until the next
      // app launch.
    }
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) => onTap(resp.payload, resp.actionId),
    );
  }

  @override
  Future<({String? payload, String? actionId})?> launchTap() async {
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (!(launch?.didNotificationLaunchApp ?? false)) return null;
    final resp = launch!.notificationResponse;
    return (payload: resp?.payload, actionId: resp?.actionId);
  }

  @override
  Future<void> requestPermission() async {
    await _android?.requestNotificationsPermission();
  }

  @override
  Future<bool> canScheduleExact() async =>
      await _android?.canScheduleExactNotifications() ?? false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'protolog_reminders',
      'Administration Reminders',
      channelDescription: 'Recurring compound administration reminders',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      actions: <AndroidNotificationAction>[
        // Both actions bring the app to the foreground: Log opens the wizard
        // prefilled; Skip advances the schedule via the same tap handler.
        AndroidNotificationAction('log', 'Log now',
            showsUserInterface: true, cancelNotification: true),
        AndroidNotificationAction('skip', 'Skip',
            showsUserInterface: true, cancelNotification: true),
      ],
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> schedule(PlannedNotification n, {required bool exact, required DateTime now}) async {
    // A custom slot is rebuilt from its wall-clock time in tz.local so it
    // survives DST; an interval one-shot keeps its exact instant.
    final slot = n.slotTime;
    final when = slot == null
        ? tz.TZDateTime.from(n.when, tz.local)
        : tz.TZDateTime(tz.local, n.when.year, n.when.month, n.when.day, slot.hour, slot.minute);
    // A custom one-shot can only land in the past if tz.local isn't the
    // device zone (lookup failed).
    if (slot != null && !n.repeatsWeekly && !when.isAfter(tz.TZDateTime.from(now, tz.local))) {
      return;
    }
    await _plugin.zonedSchedule(
      n.id,
      n.title,
      n.body,
      when,
      _details,
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: n.payload,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: n.repeatsWeekly ? DateTimeComponents.dayOfWeekAndTime : null,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id);
}
