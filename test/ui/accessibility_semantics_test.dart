import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/calendar_page.dart';
import 'package:protolog_tracker/ui/views/reminders_page.dart';
import 'package:protolog_tracker/ui/widgets/protolog_shell.dart';
import 'package:protolog_tracker/ui/widgets/tap_target.dart';

import 'real_fonts.dart';

const _test = CompoundDefinition(
  id: 'tc', base: 'Testosterone', ester: 'Cypionate',
  type: CompoundType.steroid, graphType: GraphType.curve,
  halfLife: 5, timeToPeak: 1.8, ratio: 0.69, unit: Unit.mg,
  colorValue: 0xFF5DC59C,
);

Future<void> _pumpPhone(WidgetTester tester, Widget home) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: home));
  await tester.pumpAndSettle();
}

/// The semantics node of the TapTarget around [finder].
SemanticsNode _targetOf(WidgetTester tester, Finder finder) => tester.getSemantics(
    find.ancestor(of: finder, matching: find.byType(TapTargetBox)).first);

void main() {
  setUpAll(loadAppFonts);

  group('calendar day list', () {
    final now = DateTime(2026, 10, 3, 21);
    final dose = Injection(
      id: 'i1', compoundId: 'tc', date: DateTime(2026, 10, 3, 9), dosage: 125, snapshot: _test,
    );

    Future<({List<Injection> edited, List<String> deleted})> pump(WidgetTester tester) async {
      final edited = <Injection>[];
      final deleted = <String>[];
      await _pumpPhone(
        tester,
        ProtoLogShell(
          activeTab: ShellTab.calendar,
          onTabChanged: (_) {},
          body: CalendarPage(
            injections: [dose],
            now: now,
            onDeleteInjection: deleted.add,
            onUpdateNotes: (_, _) {},
            onEditInjection: edited.add,
          ),
        ),
      );
      return (edited: edited, deleted: deleted);
    }

    testWidgets('a near miss on the notes icon opens notes, not the dose editor', (tester) async {
      final host = await pump(tester);
      final icon = tester.getRect(find.byIcon(Icons.add_comment_outlined));
      // The icon box is 22 × 18; 10 px left of it is still inside the row.
      await tester.tapAt(Offset(icon.left - 10, icon.center.dy));
      await tester.pumpAndSettle();
      expect(find.text('Notes'), findsOneWidget);
      expect(host.edited, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      // Further away the row keeps its own tap.
      await tester.tapAt(Offset(icon.left - 60, icon.center.dy));
      await tester.pumpAndSettle();
      expect(host.edited, [dose]);
    });

    testWidgets('icon, chevrons and day cells are labeled buttons', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      expect(_targetOf(tester, find.byIcon(Icons.add_comment_outlined)),
          matchesSemantics(label: 'Add a note', isButton: true, hasTapAction: true,
              hasEnabledState: true, isEnabled: true));
      expect(_targetOf(tester, find.text('‹')).label, 'Previous month');
      expect(_targetOf(tester, find.text('›')).label, 'Next month');
      final today = _targetOf(tester, find.text('3'));
      expect(today.label, 'Saturday, October 3, today, 1 compound logged');
      expect(today.flagsCollection.isSelected, Tristate.isTrue);
      expect(today.rect.width, greaterThanOrEqualTo(48));
      handle.dispose();
    });

    testWidgets('the entry row offers a spoken Delete action', (tester) async {
      final handle = tester.ensureSemantics();
      final host = await pump(tester);
      final row = _targetOf(tester, find.text('Testosterone Cypionate'));
      expect(row.getSemanticsData().hint, 'Edit dose');
      final delete = row.getSemanticsData().customSemanticsActionIds!
          .map(CustomSemanticsAction.getAction)
          .single;
      expect(delete!.label, 'Delete entry');
      row.owner!.performAction(
          row.id, SemanticsAction.customAction, CustomSemanticsAction.getIdentifier(delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(host.deleted, ['i1']);
      handle.dispose();
    });
  });

  group('reminders', () {
    final now = DateTime(2026, 5, 18, 7, 40);
    final r = Reminder(
      id: 'r', compoundBase: 'Testosterone', compoundEster: 'Cypionate',
      scheduleMode: 'interval', intervalDays: 3.5, hour: 8, minute: 0,
      enabled: true, anchorDate: DateTime(2026, 5, 20, 6, 0),
    );

    testWidgets('the pause switch: toggled state, label, and near misses toggle it', (tester) async {
      final handle = tester.ensureSemantics();
      final toggled = <Reminder>[];
      final edited = <Reminder?>[];
      await _pumpPhone(
        tester,
        Scaffold(
          body: TapTargetScope(
            child: RemindersPage(
              reminders: [r], userCompounds: const [], now: now,
              onEditReminder: edited.add, onToggleEnabled: toggled.add,
              onLogNow: (_) {}, onSkip: (_) {},
            ),
          ),
        ),
      );
      final toggle = find.byKey(const ValueKey('reminder-toggle-r'));
      expect(
        tester.getSemantics(find.descendant(of: toggle, matching: find.byType(TapTargetBox))),
        matchesSemantics(
          label: 'Testosterone Cypionate reminder',
          isButton: true, hasToggledState: true, isToggled: true,
          hasEnabledState: true, isEnabled: true, hasTapAction: true,
        ),
      );
      final box = tester.getRect(toggle); // 34 × 19
      await tester.tapAt(Offset(box.center.dx, box.top - 10));
      await tester.tapAt(Offset(box.left - 5, box.center.dy));
      expect(toggled, [r, r]);
      expect(edited, isEmpty);
      handle.dispose();
    });
  });

  testWidgets('shell tabs are a selectable group; the FAB speaks its label', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpPhone(
      tester,
      ProtoLogShell(
        activeTab: ShellTab.library,
        onTabChanged: (_) {},
        onFabPressed: () {},
        fabLabel: 'Log dose',
        body: const SizedBox.expand(),
      ),
    );
    final library = _targetOf(tester, find.text('Library'));
    expect(library.flagsCollection.isSelected, Tristate.isTrue);
    expect(library.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    expect(_targetOf(tester, find.text('Today')).flagsCollection.isSelected, Tristate.isFalse);
    expect(_targetOf(tester, find.text('Log dose')).label, 'Log dose');
    handle.dispose();
  });
}
