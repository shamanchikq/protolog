import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/reminder_editor_page.dart';
import 'package:protolog_tracker/ui/views/reminders_page.dart';

import 'real_fonts.dart';

/// C1: Android "Large" (1.15×) / "Largest" (1.3×) text on a 360 dp phone
/// must not overflow the Reminders tab or the reminder editor. Measured
/// with the bundled fonts — the test font's square glyphs give false
/// results.
const _scales = [1.0, 1.15, 1.3];

final _now = DateTime(2026, 5, 18, 7, 40);

Future<void> _pumpAt(WidgetTester tester, Widget page, {required double scale, double width = 360}) async {
  tester.view.devicePixelRatio = 1;
  // Tall, so every lazily built list child is laid out and measured.
  tester.view.physicalSize = Size(width, 3000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        child: page,
      ),
    ),
  ));
  await tester.pump();
}

ReminderEditorPage _editor({Reminder? editing}) => ReminderEditorPage(
      editing: editing,
      userCompounds: const [],
      now: _now,
      onSave: (_) {},
      onDelete: editing == null ? null : () {},
    );

Reminder _interval(String base, String ester, {bool enabled = true}) => Reminder(
      id: '$base$ester', compoundBase: base, compoundEster: ester,
      scheduleMode: 'interval', intervalDays: 3.5, hour: 8, minute: 0,
      enabled: enabled, anchorDate: DateTime(2026, 5, 18, 6, 0),
    );

void main() {
  setUpAll(loadAppFonts);

  for (final scale in _scales) {
    group('text scale $scale on 360 dp', () {
      for (final cat in ['Injectable', 'Oral', 'Peptide', 'Ancillary']) {
        testWidgets('editor compound picker: $cat', (tester) async {
          await _pumpAt(tester, _editor(), scale: scale);
          await tester.tap(find.text(cat));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('editor ester drill-down', (tester) async {
        await _pumpAt(tester, _editor(), scale: scale);
        await tester.tap(find.text('Testosterone'));
        await tester.pump();
        expect(find.textContaining('select ester'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('editor: interval reminder being edited', (tester) async {
        await _pumpAt(tester, _editor(editing: _interval('Testosterone', 'Cypionate')), scale: scale);
        expect(find.text('NEXT DOSE'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('editor: custom days', (tester) async {
        await _pumpAt(
          tester,
          _editor(
            editing: Reminder(
              id: 'c', compoundBase: 'BPC-157', compoundEster: 'None',
              scheduleMode: 'custom', intervalDays: 0, hour: 8, minute: 0, enabled: true,
              customSlots: [
                for (var d = 1; d <= 7; d++) ReminderSlot(weekday: d, hour: 20, minute: 30),
              ],
            ),
          ),
          scale: scale,
        );
        expect(find.text('Sun'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Reminders tab with rows and the notifications-off banner', (tester) async {
        await _pumpAt(
          tester,
          Scaffold(
            body: RemindersPage(
              reminders: [
                _interval('Testosterone', 'Cypionate'),
                _interval('Trenbolone', 'Hexahydrobenzylcarbonate'),
                _interval('BPC-157', 'None', enabled: false),
              ],
              userCompounds: const [],
              now: _now,
              onEditReminder: (_) {},
              onToggleEnabled: (_) {},
              onLogNow: (_) {},
              onSkip: (_) {},
              notificationsDisabled: true,
              onRequestNotificationPermission: () {},
            ),
          ),
          scale: scale,
        );
        expect(find.text('Allow'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('picker cards keep their default proportions at 1.0×', (tester) async {
    await _pumpAt(tester, _editor(), scale: 1.0);
    // Three columns across 360 − 2 × 14 padding with 8 px gaps.
    final card = tester.getSize(find.ancestor(of: find.text('Boldenone'), matching: find.byType(GestureDetector)).first);
    expect(card.width, closeTo((360 - 28 - 16) / 3, 0.5));
    expect(card.height, closeTo(card.width / 1.45, 0.5));
  });
}
