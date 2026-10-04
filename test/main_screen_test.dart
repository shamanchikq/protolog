import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/engine/reminder_notification_plan.dart';
import 'package:protolog_tracker/engine/reminder_schedule.dart';
import 'package:protolog_tracker/main.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/services/app_store.dart';
import 'package:protolog_tracker/services/backup_io.dart';
import 'package:protolog_tracker/ui/theme.dart';
import 'package:protolog_tracker/ui/views/add_injection_wizard.dart';
import 'package:protolog_tracker/ui/views/calendar_page.dart';
import 'package:protolog_tracker/ui/views/compound_detail_page.dart';
import 'package:protolog_tracker/ui/views/dashboard_view.dart';
import 'package:protolog_tracker/ui/views/library_page.dart';
import 'package:protolog_tracker/ui/views/reminder_editor_page.dart';
import 'package:protolog_tracker/ui/views/reminders_page.dart';
import 'package:protolog_tracker/ui/widgets/library_row.dart';
import 'package:protolog_tracker/ui/widgets/swimlane_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/finders.dart';

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

/// BackupIO whose file picker returns [text].
class _PickedBackup extends BackupIO {
  _PickedBackup(this.text) : super(AppStore());
  final String text;

  @override
  Future<String?> pickFile() async => text;
}

/// BackupIO that records the share request instead of opening the sheet.
class _SharedBackup extends BackupIO {
  _SharedBackup() : super(AppStore());
  final origins = <Rect?>[];

  @override
  Future<void> share(AppCollections current, {Rect? origin}) async => origins.add(origin);
}

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

  testWidgets('boot reconciles: stale ids cancelled, shown notifications kept (B18)',
      (tester) async {
    final anchor = _anchor();
    SharedPreferences.setMockInitialValues({
      'reminders': jsonEncode([
        _dueReminder(anchor),
        _dueReminder(anchor, id: 'off', seed: 900, enabled: false),
      ]),
    });
    final backend = FakeNotificationBackend()
      // Delivered earlier and still in the shade.
      ..displayed.addAll({500, 900})
      // A pending leftover of the now-disabled reminder.
      ..pending[905] = PlannedNotification(
          id: 905, when: anchor, title: 't', body: 'b', payload: 'off');
    await _bootFake(tester, backend: backend);

    expect(backend.calls.take(2), ['init', 'pending']);
    expect(backend.cancelCalls, ['cancel:905']);
    expect(backend.pending.keys.toSet(), {for (var i = 0; i < 10; i++) 500 + i});
    expect(backend.pending[500]!.when, anchor);
    expect(backend.displayed, {500, 900});
  });

  testWidgets('resume reconciles reminders: only the missing one goes out (N7/G4)',
      (tester) async {
    final anchor = _anchor();
    SharedPreferences.setMockInitialValues({'reminders': jsonEncode([_dueReminder(anchor)])});
    final backend = await _bootFake(tester);
    backend
      ..deliver(500)
      ..calls.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);

    expect(backend.calls, ['pending', 'schedule:500']);
    expect(backend.displayed, {500});
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
    // Same shape: every id is replaced in place, nothing is cancelled.
    expect(backend.cancelCalls, isEmpty);
    expect(backend.scheduleCalls, hasLength(10));
    expect(backend.pending[500]!.when, next);
    expect(find.text('Skipped Testosterone — rescheduled'), findsOneWidget);
  });

  testWidgets('row actions apply to the current reminder, not the copy the row captured (B15)',
      (tester) async {
    final anchor = _anchor();
    SharedPreferences.setMockInitialValues({'reminders': jsonEncode([_dueReminder(anchor)])});
    final backend = await _bootFake(tester);
    await tester.tap(find.text('Reminders').first);
    await _settle(tester);
    RemindersPage page() => tester.widget<RemindersPage>(find.byType(RemindersPage));
    final stale = page().reminders.single;

    // The reminder moves on (a Skip from the shade) while a row still holds
    // the old copy; then Pause is pressed on that row.
    backend.onTap!('r1', 'skip');
    await _settle(tester);
    page().onToggleEnabled(stale);
    await _settle(tester);

    final prefs = await SharedPreferences.getInstance();
    final stored = _storedReminder(prefs);
    expect(stored['enabled'], isFalse);
    expect(DateTime.parse(stored['anchorDate'] as String), anchor.add(const Duration(hours: 84)),
        reason: 'the pause must not write the pre-skip anchor back');
    expect(backend.pending, isEmpty, reason: 'paused: every id cancelled');

    // Resume from the same stale copy: enabled again, anchor still current.
    page().onToggleEnabled(stale);
    await _settle(tester);
    expect(_storedReminder(prefs)['enabled'], isTrue);
    expect(DateTime.parse(_storedReminder(prefs)['anchorDate'] as String),
        anchor.add(const Duration(hours: 84)));
  });

  testWidgets('editing or deleting a log refreshes the reminder text (B19)', (tester) async {
    final anchor = _anchor();
    final dose = Injection(
        id: 'i1',
        compoundId: 'test_e',
        date: DateTime.now().subtract(const Duration(days: 1)),
        dosage: 150,
        snapshot: _testE);
    SharedPreferences.setMockInitialValues({
      'reminders': jsonEncode([_dueReminder(anchor)]),
      'injections': jsonEncode([dose.toJson()]),
    });
    final backend = await _bootFake(tester);
    expect(backend.pending[500]!.body, endsWith('last dose 150 mg'));

    await tester.tap(find.text('Calendar').first);
    await _settle(tester);
    tester.widget<CalendarPage>(find.byType(CalendarPage)).onEditInjection!(dose);
    await _settle(tester);
    tester.widget<AddInjectionWizard>(find.byType(AddInjectionWizard)).onEdit!(Injection(
        id: 'i1', compoundId: 'test_e', date: dose.date, dosage: 200, snapshot: _testE));
    await _settle(tester);
    expect(backend.pending[500]!.body, endsWith('last dose 200 mg'));

    tester.widget<CalendarPage>(find.byType(CalendarPage, skipOffstage: false))
        .onDeleteInjection('i1');
    await _settle(tester);
    expect(backend.pending[500]!.body, 'Time to administer Testosterone Enanthate');
    expect(backend.cancelCalls, isEmpty);
  });

  testWidgets('a restore that disables a reminder cancels its notifications (B16, N6)',
      (tester) async {
    final anchor = _anchor();
    SharedPreferences.setMockInitialValues({'reminders': jsonEncode([_dueReminder(anchor)])});
    // The backup's copy is paused and carries another device's seed.
    final file = jsonEncode({
      'app': 'protolog',
      'schemaVersion': 1,
      'reminders': [_dueReminder(anchor, enabled: false, seed: 777)],
    });
    final backend = FakeNotificationBackend();
    await tester.pumpWidget(MaterialApp(
        home: MainScreen(notificationBackend: backend, backup: _PickedBackup(file))));
    await _settle(tester);
    backend
      ..deliver(500)
      ..calls.clear();

    await tester.tap(find.text('Library').first);
    await _settle(tester);
    tester.widget<LibraryPage>(find.byType(LibraryPage)).onRestore();
    await _settle(tester);
    expect(find.text("Replaces the matching 1 reminder on this device with the backup's copy. "
        'Nothing else changes.'), findsOneWidget);
    await tester.tap(find.text('Merge'));
    await _settle(tester);

    final prefs = await SharedPreferences.getInstance();
    expect(_storedReminder(prefs)['enabled'], isFalse);
    expect(_storedReminder(prefs)['notificationSeed'], 500, reason: 'N6: the local seed stays');
    expect(backend.cancelCalls,
        [for (var i = 0; i < kNotificationIdsPerReminder; i++) 'cancel:${500 + i}']);
    expect(backend.pending, isEmpty);
    expect(backend.displayed, isEmpty);
  });

  group('deleting a custom compound (B11)', () {
    const custom = CompoundDefinition(
      id: 'c1',
      base: 'MyPep',
      ester: 'None',
      type: CompoundType.peptide,
      graphType: GraphType.event,
      halfLife: 0.5,
      timeToPeak: 0.1,
      ratio: 1,
      unit: Unit.mcg,
      colorValue: 0xFF336699,
      isCustom: true,
    );
    Map<String, Object?> reminderFor(CompoundDefinition c, String id, int seed) => {
          ..._dueReminder(_anchor(), id: id, seed: seed),
          'compoundBase': c.base,
          'compoundEster': c.ester,
        };

    Future<FakeNotificationBackend> deleteFromDetail(
        WidgetTester tester, CompoundDefinition c, List<Object?> stored) async {
      SharedPreferences.setMockInitialValues({
        'compounds': jsonEncode([c.toJson()]),
        'reminders': jsonEncode(stored),
      });
      final backend = await _bootFake(tester);
      backend.calls.clear();
      await tester.tap(find.text('Library').first);
      await _settle(tester);
      tester.widget<LibraryPage>(find.byType(LibraryPage)).onOpenDetail(c);
      await _settle(tester);
      tester.widget<CompoundDetailPage>(find.byType(CompoundDetailPage)).onDelete();
      await _settle(tester);
      return backend;
    }

    testWidgets('also deletes its reminders and cancels their notifications', (tester) async {
      final backend = await deleteFromDetail(tester, custom, [
        reminderFor(custom, 'mine', 600),
        _dueReminder(_anchor(), id: 'other', seed: 900),
      ]);

      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString('reminders')!) as List;
      expect(stored.map((r) => r['id']), ['other']);
      expect(jsonDecode(prefs.getString('compounds')!), isEmpty);
      expect(backend.cancelCalls,
          [for (var i = 0; i < kNotificationIdsPerReminder; i++) 'cancel:${600 + i}']);
      expect(backend.pending.keys.toSet(), {for (var i = 0; i < 10; i++) 900 + i});
      expect(find.text('Deleted MyPep and its 1 reminder'), findsOneWidget);
    });

    testWidgets("keeps reminders a shadowed built-in still serves", (tester) async {
      final shadow = BASE_LIBRARY['BPC-157']!.copyWith(id: 'c2', isCustom: true, halfLife: 1);
      final backend =
          await deleteFromDetail(tester, shadow, [reminderFor(shadow, 'bpc', 600)]);

      final prefs = await SharedPreferences.getInstance();
      expect((jsonDecode(prefs.getString('reminders')!) as List).single['id'], 'bpc');
      expect(backend.cancelCalls, isEmpty);
    });
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
    // Dark ink on the warn background: light text there is only 2.6:1.
    expect(
        tester.widget<Text>(find.textContaining("Couldn't save your latest change")).style?.color,
        AppTheme.bg);
    expect(prefs.writes, contains('reminders'));
    expect(DateTime.parse(_storedReminder(prefs)['anchorDate'] as String), anchor);
  });

  testWidgets('blocked notifications are reported once while a reminder is on (B20)',
      (tester) async {
    SharedPreferences.setMockInitialValues({'reminders': jsonEncode([_dueReminder(_anchor())])});
    final backend = await _bootFake(tester, backend: FakeNotificationBackend()..enabled = false);
    expect(find.textContaining('Notifications are off for ProtoLog'), findsOneWidget);
    expect(backend.permissionRequests, 1);

    backend.grantOnRequest = true;
    await tester.tap(find.text('Allow'));
    await _settle(tester);
    expect(backend.permissionRequests, 2);

    // Blocked again later: the notice isn't repeated this session.
    backend.enabled = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 10));
    await _settle(tester);
    expect(find.textContaining('Notifications are off for ProtoLog'), findsNothing);
  });

  testWidgets('blocked notifications go unmentioned without an active reminder (B20)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _bootFake(tester, backend: FakeNotificationBackend()..enabled = false);
    expect(find.textContaining('Notifications are off for ProtoLog'), findsNothing);
  });

  testWidgets('notifications that cannot start are reported', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = await _bootFake(tester, backend: FakeNotificationBackend()..failInit = true);

    expect(find.textContaining("Notifications couldn't start"), findsOneWidget);
    expect(backend.calls, ['init']);
  });

  testWidgets('a recolored built-in shows on every surface, routes included (B26)',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 3000);
    addTearDown(tester.view.reset);
    final recolored =
        BASE_LIBRARY['Testosterone Enanthate']!.copyWith(colorValue: userColor.toARGB32());
    SharedPreferences.setMockInitialValues({
      'compounds': jsonEncode([recolored.toJson()]),
      'reminders': jsonEncode([_dueReminder(_anchor())]),
    });
    await _bootFake(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    Finder userColored(Type on) =>
        find.descendant(of: find.byType(on), matching: coloredWith(userColor));

    await tester.tap(find.text('Library').first);
    await _settle(tester);
    expect(userColored(LibraryRow), findsWidgets);
    tester.widget<LibraryPage>(find.byType(LibraryPage)).onOpenDetail(recolored);
    await _settle(tester);
    expect(userColored(CompoundDetailPage), findsOneWidget);
    nav.pop();
    await tester.pump(const Duration(seconds: 1)); // the route's exit transition
    await _settle(tester);

    await tester.tap(find.text('Reminders').first);
    await _settle(tester);
    expect(userColored(RemindersPage), findsWidgets);
    RemindersPage page() => tester.widget<RemindersPage>(find.byType(RemindersPage));
    final reminder = page().reminders.single;

    page().onEditReminder(reminder);
    await _settle(tester);
    expect(userColored(ReminderEditorPage), findsOneWidget);
    nav.pop();
    await tester.pump(const Duration(seconds: 1)); // the route's exit transition
    await _settle(tester);

    page().onLogNow(reminder);
    await _settle(tester);
    expect(userColored(AddInjectionWizard), findsOneWidget);
  });

  testWidgets('dashboard rebuilds keep one resolver and swimlane card until data changes (E2)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _bootFake(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    DashboardView dash() => tester.widget<DashboardView>(find.byType(DashboardView));
    SwimlaneCard lanes() => tester.widget<SwimlaneCard>(find.byType(SwimlaneCard));
    final resolver = dash().colorResolver;
    final card = lanes();

    // Unrelated rebuilds: a chart setting, a blocked-notifications refresh.
    dash().onSettingsChanged(const GraphSettings(
        normalized: true, cumulative: false, timeRange: 'zoom'));
    await _settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(dash().settings.timeRange, 'zoom');
    expect(dash().colorResolver, same(resolver), reason: 'the painter compares it by identity');
    expect(lanes(), same(card));

    // A recolor saved from the wizard: a new resolver, with the new color.
    await tester.tap(find.text('Log dose'));
    await _settle(tester);
    final wizard = tester.widget<AddInjectionWizard>(find.byType(AddInjectionWizard));
    final te = BASE_LIBRARY['Testosterone Enanthate']!;
    wizard.addUserCompound(te.copyWith(colorValue: userColor.toARGB32()));
    await _settle(tester);
    expect(wizard.colorResolver!('Testosterone'), userColor, reason: 'routes read it live');
    // A logged dose: the lanes resample.
    wizard.onAdd(
        Injection(id: 'i1', compoundId: te.id, date: DateTime.now(), dosage: 250, snapshot: te),
        false);
    nav.pop();
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);

    expect(dash().colorResolver, isNot(same(resolver)));
    expect(dash().colorResolver('Testosterone'), userColor);
    expect(lanes(), isNot(same(card)));
    expect(lanes().injections, hasLength(1));
  });

  group('saving the reminder editor applies to the current reminder', () {
    Future<(FakeNotificationBackend, RemindersPage Function())> openEditor(
        WidgetTester tester, Map<String, Object?> reminder) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 2000);
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({'reminders': jsonEncode([reminder])});
      final backend = await _bootFake(tester);
      await tester.tap(find.text('Reminders').first);
      await _settle(tester);
      RemindersPage page() =>
          tester.widget<RemindersPage>(find.byType(RemindersPage, skipOffstage: false));
      page().onEditReminder(page().reminders.single);
      await tester.pump(const Duration(seconds: 1)); // the route's entry transition
      await _settle(tester);
      expect(find.text('Edit reminder'), findsOneWidget);
      return (backend, page);
    }

    // Saves the open editor. The "Skipped …" snackbar shows over the
    // editor's save bar, so it goes first.
    Future<void> save(WidgetTester tester) async {
      tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
      await tester.pump();
      await tester.tap(find.text('Save reminder'));
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(find.text('Edit reminder'), findsNothing, reason: 'saved and closed');
    }

    testWidgets('an unchanged schedule keeps an advance made while it was open', (tester) async {
      final anchor = _anchor();
      final (backend, _) = await openEditor(tester, _dueReminder(anchor));
      backend.onTap!('r1', 'skip'); // from the shade, editor still open
      await _settle(tester);
      final skipped = anchor.add(const Duration(hours: 84));
      final prefs = await SharedPreferences.getInstance();
      expect(DateTime.parse(_storedReminder(prefs)['anchorDate'] as String), skipped);

      await save(tester);
      expect(DateTime.parse(_storedReminder(prefs)['anchorDate'] as String), skipped,
          reason: 'not the anchor the editor was opened with');
      expect(backend.pending[500]!.when, skipped);
    });

    testWidgets('a changed schedule is saved as edited', (tester) async {
      final anchor = _anchor();
      final (backend, _) = await openEditor(tester, _dueReminder(anchor));
      backend.onTap!('r1', 'skip');
      await _settle(tester);

      await tester.tap(find.text('+')); // every 3.5 → 4 days
      await tester.pump();
      await save(tester);
      final stored = _storedReminder(await SharedPreferences.getInstance());
      expect(stored['intervalDays'], 4.0);
      expect(DateTime.parse(stored['anchorDate'] as String), anchor,
          reason: 'the new rhythm starts from the first dose the editor showed');
    });

    testWidgets("a custom reminder keeps the slot skipped while it was open", (tester) async {
      final (_, page) = await openEditor(tester, {
        ..._reminderNoSeed,
        'id': 'c1',
        'compoundBase': 'BPC-157',
        'compoundEster': 'None',
        'scheduleMode': 'custom',
        'intervalDays': 0,
        'customSlots': [for (var d = 1; d <= 7; d++) {'weekday': d, 'hour': 9, 'minute': 0}],
        'notificationSeed': 700,
      });
      page().onSkip(page().reminders.single); // in-app Skip of the next slot
      await _settle(tester);
      final prefs = await SharedPreferences.getInstance();
      final acked = _storedReminder(prefs)['acknowledgedUntil'] as String?;
      expect(acked, isNotNull);

      await save(tester);
      expect(_storedReminder(prefs)['acknowledgedUntil'], acked,
          reason: 'saving used to drop the acknowledgement');
      expect(_storedReminder(prefs)['customSlots'], hasLength(7));
    });
  });

  testWidgets('a backup started from the Library anchors the share sheet to its button (D4)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backup = _SharedBackup();
    await tester.pumpWidget(MaterialApp(
        home: MainScreen(notificationBackend: FakeNotificationBackend(), backup: backup)));
    await _settle(tester);
    await tester.tap(find.text('Library').first);
    await _settle(tester);

    await tester.tap(find.text('Import / export'));
    await _settle(tester);
    await tester.tap(find.text('Back up everything to file…'));
    await _settle(tester);
    expect(backup.origins, [tester.getRect(find.byType(PopupMenuButton<String>))]);
  });
}
