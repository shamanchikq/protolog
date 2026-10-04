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

  /// Asks the OS for permission to post notifications: true if granted,
  /// null if the platform doesn't say.
  Future<bool?> requestPermission();

  /// Whether the OS currently lets the app post notifications (runtime
  /// permission and the app-level switch); null if the platform can't tell.
  Future<bool?> areNotificationsEnabled();

  /// Whether exact alarms are permitted (Android).
  Future<bool> canScheduleExact();

  /// Schedules one notification. A pending notification with the same id is
  /// replaced in place (both platforms key pending requests by id), without
  /// touching one already showing in the shade. [now] is the time the plan
  /// was made for.
  Future<void> schedule(PlannedNotification n, {required bool exact, required DateTime now});

  /// Ids of notifications scheduled and not yet delivered. A repeating one
  /// stays pending after it fires; a delivered one-shot is not listed (it
  /// may still be showing in the shade).
  Future<Set<int>> pendingIds();

  /// Cancels a pending (and removes a displayed) notification.
  Future<void> cancel(int id);
}

/// Reminder notifications: plugin init, the serial job queue, and keeping
/// the platform's pending notifications in line with
/// [planReminderNotifications].
///
/// **Reconcile, don't sweep (B18, E3).** Cancelling an id also dismisses a
/// notification showing in the shade, and every cancel is a platform call
/// that rewrites the plugin's cache. So routine updates — launch, resume, a
/// dose, a skip — read the pending ids, cancel only pending ids the new plan
/// doesn't use, and schedule only what is missing or different (a changed id
/// is replaced in place by [NotificationBackend.schedule]). A notification
/// already delivered is never dismissed by them.
///
/// "Different" is judged against what this process scheduled (an in-memory
/// ledger). It starts empty, so the first reconcile after a cold start
/// re-sends every planned notification: Android drops an app's alarms on
/// force-stop while the plugin still lists them as pending, and a cold start
/// is the only way back from that.
///
/// **Complete cancellation** — every id the reminder could own, shown or
/// pending — still happens when a reminder is deleted ([cancel]), disabled,
/// or changes shape (mode, slots or id base; see [reschedule]), and whenever
/// the pending ids can't be read.
///
/// All notification work runs one job at a time, so a sweep can never wipe
/// ids a newer schedule just created. The queue starts with [init], so no
/// job runs before the plugin and the platform zone are ready; if init
/// fails, every job is a no-op.
class ReminderNotificationService {
  ReminderNotificationService({
    required NotificationBackend backend,
    required List<Injection> Function() injections,
    this.onScheduleError,
    this.onPermissionResult,
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

  /// Called once per job whose schedule partly failed, with the first error
  /// (the rest of that batch is still attempted).
  final void Function(Object error)? onScheduleError;

  /// Called with the answer to the permission request made after init
  /// (null: unknown), so the app can check whether it's blocked.
  final void Function(bool? granted)? onPermissionResult;

  Future<void> _chain = Future.value();
  bool _ready = false;

  /// id → signature of what this process last scheduled under it (see the
  /// class doc). Only trusted for ids the platform still lists as pending.
  final Map<int, String> _sent = {};

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
    _afterFirstFrame(() async {
      final granted = await requestPermission();
      onPermissionResult?.call(granted);
    });
  }

  /// Asks the OS for permission to post notifications; true if granted,
  /// null if unknown or the request failed.
  Future<bool?> requestPermission() async {
    try {
      return await _backend.requestPermission();
    } catch (_) {
      // Permission request may fail on older Android versions; safe to ignore.
      return null;
    }
  }

  /// Whether the OS lets the app post notifications (B20). Null before or
  /// after a failed init, and when the platform can't tell.
  Future<bool?> notificationsEnabled() async {
    if (!_ready) return null;
    try {
      return await _backend.areNotificationsEnabled();
    } catch (_) {
      return null;
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

  /// Brings the platform in line with [reminders] — the app's full list — at
  /// launch, on resume and after a restore: cancels every pending id that no
  /// enabled reminder plans (leftovers of disabled, deleted or re-seeded
  /// reminders included) and sends what is missing or changed. Never
  /// dismisses a delivered notification. Falls back to the complete sweep
  /// if the pending ids can't be read.
  Future<void> reconcileAll(Iterable<Reminder> reminders) {
    final list = List<Reminder>.of(reminders);
    return _enqueue(() async {
      final pending = await _pendingIds();
      if (pending == null) {
        for (final r in list) {
          await _sweep(r);
        }
        await _send([for (final r in list) ..._plan(r)], const {});
        return;
      }
      final plan = [for (final r in list) ..._plan(r)];
      final wanted = {for (final n in plan) n.id};
      await _cancelEach(pending.where((id) => !wanted.contains(id)));
      await _send(plan, pending);
    });
  }

  /// Updates one reminder after an explicit change; [previous] is the
  /// version it replaces, if any. A disabled reminder, or one whose shape
  /// changed, gets the complete sweep first (the previous id base's too);
  /// otherwise the reminder's own id range is reconciled like
  /// [reconcileAll] does.
  Future<void> reschedule(Reminder r, {Reminder? previous}) => _enqueue(() async {
        final reshaped = previous != null && _shapeChanged(previous, r);
        Set<int>? pending;
        if (r.enabled && !reshaped) pending = await _pendingIds();
        if (pending == null) {
          if (reshaped && previous.notificationIdBase != r.notificationIdBase) {
            await _sweep(previous);
          }
          await _sweep(r);
          await _send(_plan(r), const {});
          return;
        }
        final plan = _plan(r);
        final wanted = {for (final n in plan) n.id};
        await _cancelEach(pending.where((id) => _owns(r, id) && !wanted.contains(id)));
        await _send(plan, pending);
      });

  /// Cancels every id the reminder could have scheduled, pending or shown
  /// (it was deleted).
  Future<void> cancel(Reminder r) => _enqueue(() => _sweep(r));

  List<PlannedNotification> _plan(Reminder r) =>
      planReminderNotifications(r, _clock(), injections: _injections());

  static bool _owns(Reminder r, int id) =>
      id >= r.notificationIdBase && id < r.notificationIdBase + kNotificationIdsPerReminder;

  /// Mode, slot layout or id base differ, so ids map to other occurrences.
  static bool _shapeChanged(Reminder a, Reminder b) {
    if (a.scheduleMode != b.scheduleMode || a.notificationIdBase != b.notificationIdBase) {
      return true;
    }
    if (a.scheduleMode != 'custom') return false;
    if (a.customSlots.length != b.customSlots.length) return true;
    for (var i = 0; i < a.customSlots.length; i++) {
      final x = a.customSlots[i], y = b.customSlots[i];
      if (x.weekday != y.weekday || x.hour != y.hour || x.minute != y.minute) return true;
    }
    return false;
  }

  /// The platform's pending ids, or null if they can't be read.
  Future<Set<int>?> _pendingIds() async {
    try {
      final ids = await _backend.pendingIds();
      // Whatever isn't pending any more fired or was cancelled elsewhere.
      _sent.removeWhere((id, _) => !ids.contains(id));
      return ids;
    } catch (_) {
      return null;
    }
  }

  // Sweeps the reminder's whole id range regardless of its *current*
  // mode/slot count — a mode switch must not orphan ids scheduled under the
  // previous shape. A failing cancel aborts the job.
  Future<void> _sweep(Reminder r) async {
    for (var i = 0; i < kNotificationIdsPerReminder; i++) {
      final id = r.notificationIdBase + i;
      await _backend.cancel(id);
      _sent.remove(id);
    }
  }

  /// Cancels [ids] one by one; a failure costs only that id.
  Future<void> _cancelEach(Iterable<int> ids) async {
    for (final id in ids.toList()) {
      try {
        await _backend.cancel(id);
        _sent.remove(id);
      } catch (_) {}
    }
  }

  /// Schedules each of [plan] unless [pending] holds its id with exactly what
  /// this process last sent under it.
  Future<void> _send(List<PlannedNotification> plan, Set<int> pending) async {
    if (plan.isEmpty) return;
    final now = _clock();

    // Exact alarms when permitted (auto-granted on Android 13+ via
    // USE_EXACT_ALARM); inexact delivery can lag by up to an hour in Doze.
    var exact = false;
    try {
      exact = await _backend.canScheduleExact();
    } catch (_) {}

    // Per-call try so one bad occurrence doesn't drop the rest of the batch.
    Object? firstError;
    for (final n in plan) {
      final sig = _signature(n, exact);
      if (pending.contains(n.id) && _sent[n.id] == sig) continue;
      try {
        await _backend.schedule(n, exact: exact, now: now);
        _sent[n.id] = sig;
      } catch (e) {
        _sent.remove(n.id);
        firstError ??= e;
      }
    }
    if (firstError != null) onScheduleError?.call(firstError);
  }

  /// Everything that decides what the platform does with [n]. A weekly
  /// repeat is keyed by weekday and clock time rather than its next date, so
  /// it isn't re-sent every week; the UTC offset catches a zone change.
  static String _signature(PlannedNotification n, bool exact) {
    final when = n.repeatsWeekly
        ? 'weekly ${n.when.weekday} ${n.slotTime} ${n.when.timeZoneOffset}'
        : '${n.when.toUtc().toIso8601String()} ${n.slotTime}';
    return [when, n.title, n.body, n.payload, exact].join('\u0000');
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
    const androidSettings = AndroidInitializationSettings(_smallIcon);
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

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  @override
  Future<bool?> requestPermission() async {
    final android = _android;
    if (android != null) return android.requestNotificationsPermission();
    return _ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  @override
  Future<bool?> areNotificationsEnabled() async {
    final android = _android;
    if (android != null) return android.areNotificationsEnabled();
    return (await _ios?.checkPermissions())?.isEnabled;
  }

  @override
  Future<bool> canScheduleExact() async =>
      await _android?.canScheduleExactNotifications() ?? false;

  /// Monochrome status-bar icon (D7; res/drawable, kept from the release
  /// shrinker by res/raw/keep.xml). The full-colour launcher icon renders
  /// as a white square.
  static const _smallIcon = 'ic_stat_protolog';

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'protolog_reminders',
      'Administration Reminders',
      channelDescription: 'Recurring compound administration reminders',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      icon: _smallIcon,
      // The body names the compound and the last dose: hide it on a secure
      // lock screen (D8).
      visibility: NotificationVisibility.private,
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
  Future<Set<int>> pendingIds() async =>
      {for (final p in await _plugin.pendingNotificationRequests()) p.id};

  @override
  Future<void> cancel(int id) => _plugin.cancel(id);
}
