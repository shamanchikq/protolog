import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/engine/compute_engine.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/theme.dart';
import 'package:protolog_tracker/ui/views/add_injection_wizard.dart';
import 'package:protolog_tracker/ui/views/bloodwork_page.dart';
import 'package:protolog_tracker/ui/views/calendar_page.dart';
import 'package:protolog_tracker/ui/views/compound_detail_page.dart';
import 'package:protolog_tracker/ui/views/compound_editor_page.dart';
import 'package:protolog_tracker/ui/views/dashboard_view.dart';
import 'package:protolog_tracker/ui/views/library_page.dart';
import 'package:protolog_tracker/ui/views/reminder_editor_page.dart';
import 'package:protolog_tracker/ui/views/reminders_page.dart';
import 'package:protolog_tracker/ui/widgets/bloodwork_editor_dialog.dart';
import 'package:protolog_tracker/ui/widgets/protolog_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The app's main screens with realistic data, for the accessibility
// guideline tests (test/ui/accessibility_*_test.dart).

final a11yNow = DateTime(2026, 10, 3, 21);

const _testE = CompoundDefinition(
  id: 'test_e', base: 'Testosterone', ester: 'Enanthate',
  type: CompoundType.steroid, graphType: GraphType.curve,
  halfLife: 4.5, timeToPeak: 1.5, ratio: 0.72, unit: Unit.mg,
  colorValue: 0xFF5DC59C,
);
const _anavar = CompoundDefinition(
  id: 'var', base: 'Oxandrolone', ester: 'None',
  type: CompoundType.oral, graphType: GraphType.curve,
  halfLife: 0.4, timeToPeak: 0.05, ratio: 1, unit: Unit.mg,
  colorValue: 0xFFC9B062,
);
const _bpc = CompoundDefinition(
  id: 'bpc', base: 'BPC-157', ester: 'None',
  type: CompoundType.peptide, graphType: GraphType.event,
  halfLife: 0.2, timeToPeak: 0.05, ratio: 1, unit: Unit.mcg,
  colorValue: 0xFF8FC5A8,
);
const _ai = CompoundDefinition(
  id: 'ai', base: 'Anastrozole', ester: 'None',
  type: CompoundType.ancillary, graphType: GraphType.activeWindow,
  halfLife: 2, timeToPeak: 0.1, ratio: 1, unit: Unit.mg,
  colorValue: 0xFFD27A6B,
);

final a11yInjections = <Injection>[
  for (var d = 0; d < 21; d += 3)
    Injection(
      id: 't$d', compoundId: 'test_e', dosage: 125, snapshot: _testE,
      date: a11yNow.subtract(Duration(days: d, hours: 2)),
      site: 'Vent. glute R', notes: d == 0 ? 'Felt fine' : null,
    ),
  for (var d = 0; d < 6; d++)
    Injection(id: 'v$d', compoundId: 'var', dosage: 20, snapshot: _anavar,
        date: a11yNow.subtract(Duration(days: d, hours: 1))),
  for (var d = 0; d < 6; d += 2)
    Injection(id: 'b$d', compoundId: 'bpc', dosage: 250, snapshot: _bpc,
        date: a11yNow.subtract(Duration(days: d, hours: 3))),
  for (var d = 0; d < 9; d += 3)
    Injection(id: 'a$d', compoundId: 'ai', dosage: 0.5, snapshot: _ai,
        date: a11yNow.subtract(Duration(days: d, hours: 4))),
];

final _bloodwork = [
  BloodworkEntry(id: '1', date: DateTime(2026, 5, 30), marker: 'Total T', value: 30, unit: 'nmol/L'),
  BloodworkEntry(id: '2', date: DateTime(2026, 9, 1), marker: 'Total T', value: 38.5, unit: 'nmol/L'),
  BloodworkEntry(id: '3', date: DateTime(2026, 9, 1), marker: 'E2', value: 120, unit: 'pmol/L'),
];

final _reminders = [
  Reminder(
    id: 'r1', compoundBase: 'Testosterone', compoundEster: 'Enanthate',
    scheduleMode: 'interval', intervalDays: 3.5, hour: 8, minute: 0,
    enabled: true, anchorDate: a11yNow.add(const Duration(hours: 4)), notificationSeed: 1,
  ),
  Reminder(
    id: 'r2', compoundBase: 'Anastrozole', compoundEster: 'None',
    scheduleMode: 'custom', intervalDays: 0, hour: 8, minute: 0,
    customSlots: const [
      ReminderSlot(weekday: 1, hour: 8, minute: 0),
      ReminderSlot(weekday: 4, hour: 8, minute: 0),
    ],
    enabled: false, notificationSeed: 2,
  ),
];

Widget _shell(ShellTab tab, Widget body, {String? fab}) => ProtoLogShell(
      activeTab: tab,
      onTabChanged: (_) {},
      onFabPressed: fab == null ? null : () {},
      fabLabel: fab,
      body: body,
    );

Widget _wizard({CompoundDefinition? prefill}) => Scaffold(
      body: AddInjectionWizard(
        onAdd: (_, _) {},
        reminders: _reminders,
        onCancel: () {},
        onSuccess: () {},
        userCompounds: const [],
        addUserCompound: (_) {},
        injections: a11yInjections,
        prefillCompound: prefill,
      ),
    );

/// A screen: its name and how to show it (built and settled by [pumpScreen]).
typedef A11yScreen = ({String name, Future<Widget> Function() build, Future<void> Function(WidgetTester)? then});

final a11yScreens = <A11yScreen>[
  (
    name: 'Today',
    build: () async {
      const settings = GraphSettings(normalized: false, cumulative: false, timeRange: 'standard');
      final data = await computeGraphData(IsolateInput(a11yInjections, settings), now: a11yNow);
      return _shell(
        ShellTab.today,
        DashboardView(
          injections: a11yInjections,
          bloodwork: _bloodwork,
          graphData: Future.value(data),
          settings: settings,
          colorResolver: (b) => AppTheme.compoundColor(b) ?? AppTheme.fgMute,
          now: a11yNow,
          onSettingsChanged: (_) {},
          onAddBloodwork: () {},
          onOpenBloodwork: (_) {},
        ),
        fab: 'Log dose',
      );
    },
    then: null,
  ),
  (
    name: 'Calendar',
    build: () async => _shell(
          ShellTab.calendar,
          CalendarPage(
            injections: a11yInjections,
            now: a11yNow,
            onDeleteInjection: (_) {},
            onUpdateNotes: (_, _) {},
            onEditInjection: (_) {},
          ),
          fab: 'Log dose',
        ),
    then: null,
  ),
  (
    name: 'Library',
    build: () async => _shell(
          ShellTab.library,
          LibraryPage(
            userCompounds: const [],
            injections: a11yInjections,
            now: a11yNow,
            onExport: () {},
            onImport: () {},
            onBackup: (_) {},
            onRestore: () {},
            onOpenDetail: (_) {},
            onOpenCreate: () {},
          ),
        ),
    then: null,
  ),
  (
    name: 'Reminders',
    build: () async => _shell(
          ShellTab.reminders,
          RemindersPage(
            reminders: _reminders,
            userCompounds: const [],
            now: a11yNow,
            onEditReminder: (_) {},
            onToggleEnabled: (_) {},
            onLogNow: (_) {},
            onSkip: (_) {},
            notificationsDisabled: true,
            onRequestNotificationPermission: () {},
          ),
          fab: 'New reminder',
        ),
    then: null,
  ),
  (
    name: 'Reminders (empty)',
    build: () async => _shell(
          ShellTab.reminders,
          RemindersPage(
            reminders: const [],
            userCompounds: const [],
            now: a11yNow,
            onEditReminder: (_) {},
            onToggleEnabled: (_) {},
            onLogNow: (_) {},
            onSkip: (_) {},
          ),
          fab: 'New reminder',
        ),
    then: null,
  ),
  (name: 'Wizard step 1', build: () async => _wizard(), then: null),
  (name: 'Wizard step 2', build: () async => _wizard(prefill: _testE), then: null),
  (
    name: 'Wizard step 2, peptide by volume',
    build: () async => _wizard(prefill: _bpc.copyWith(graphType: GraphType.activeWindow)),
    then: (tester) async {
      await tester.tap(find.text('By volume'));
      await tester.pumpAndSettle();
    },
  ),
  (
    name: 'Compound detail',
    build: () async => CompoundDetailPage(
          compound: _testE,
          injections: a11yInjections,
          linkedReminderCount: 1,
          onTabChanged: (_) {},
          openEditor: (_) async => null,
          onDelete: () {},
          onLogInjection: (_) {},
        ),
    then: null,
  ),
  (
    name: 'Compound editor (built-in)',
    build: () async => CompoundEditorPage(
          editing: BASE_LIBRARY.values.first,
          onTabChanged: (_) {},
          onUpdate: (_) {},
        ),
    then: null,
  ),
  (
    name: 'Compound editor (new)',
    build: () async => CompoundEditorPage(onTabChanged: (_) {}, onCreate: (_) {}),
    then: null,
  ),
  (
    name: 'Reminder editor',
    build: () async => ReminderEditorPage(
          editing: _reminders.first,
          userCompounds: const [],
          now: a11yNow,
          onSave: (_) {},
          onDelete: () {},
        ),
    then: null,
  ),
  (
    name: 'Reminder editor, custom days',
    build: () async => ReminderEditorPage(
          editing: _reminders.last,
          userCompounds: const [],
          now: a11yNow,
          onSave: (_) {},
          onDelete: () {},
        ),
    then: null,
  ),
  (
    name: 'Reminder editor, compound picker',
    build: () async => ReminderEditorPage(userCompounds: const [], now: a11yNow, onSave: (_) {}),
    then: null,
  ),
  (
    name: 'Bloodwork page',
    build: () async => BloodworkPage(
          initialEntries: _bloodwork,
          injections: a11yInjections,
          onChanged: (_) {},
        ),
    then: (tester) async {
      await tester.tap(find.text('PK overlay'));
      await tester.pumpAndSettle();
    },
  ),
  (
    name: 'Bloodwork editor dialog',
    build: () async => Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => BloodworkEditorDialog(
                    editing: _bloodwork.first,
                    markerSuggestions: const {'Total T': 'nmol/L', 'E2': 'pmol/L'},
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
    then: (tester) async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    },
  ),
];

/// Pumps [screen] on a [size] phone (1 dp per pixel) and settles it.
Future<void> pumpScreen(WidgetTester tester, A11yScreen screen, {required Size size}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final home = await screen.build();
  await tester.pumpWidget(MaterialApp(theme: AppTheme.materialTheme, home: home));
  await tester.pumpAndSettle();
  await screen.then?.call(tester);
}
