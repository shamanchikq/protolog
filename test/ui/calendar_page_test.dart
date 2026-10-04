import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/calendar_page.dart';

const _test = CompoundDefinition(
  id: 'tc', base: 'Testosterone', ester: 'Cypionate',
  type: CompoundType.steroid, graphType: GraphType.curve,
  halfLife: 5, timeToPeak: 1.8, ratio: 0.69, unit: Unit.mg,
  colorValue: 0xFF5DC59C,
);

Injection _log(DateTime date, {double dose = 125}) => Injection(
      id: 'i${date.toIso8601String()}',
      compoundId: _test.id,
      date: date,
      dosage: dose,
      snapshot: _test,
    );

Future<List<DateTime>> _pump(
  WidgetTester tester, {
  required DateTime now,
  List<Injection> injections = const [],
}) async {
  final selected = <DateTime>[];
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 1400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: CalendarPage(
        injections: injections,
        now: now,
        onDeleteInjection: (_) {},
        onUpdateNotes: (_, _) {},
        onDaySelected: selected.add,
      ),
    ),
  ));
  await tester.pump(); // post-frame initial selection report
  return selected;
}

/// The selected-day header, e.g. "SUNDAY, OCT 4".
String _header(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .firstWhere((s) => RegExp(r'^[A-Z]+DAY, [A-Z]{3} \d+$').hasMatch(s));

void main() {
  group('month navigation (B31)', () {
    testWidgets('moving to another month selects its 1st and reports it', (tester) async {
      final selected = await _pump(tester, now: DateTime(2026, 10, 4, 15));
      expect(selected, [DateTime(2026, 10, 4)]);

      await tester.tap(find.text('›'));
      await tester.pump();
      expect(find.text('November 2026', findRichText: true), findsOneWidget);
      expect(_header(tester), 'SUNDAY, NOV 1');
      expect(selected.last, DateTime(2026, 11, 1));

      await tester.tap(find.text('‹'));
      await tester.tap(find.text('‹'));
      await tester.pump();
      expect(_header(tester), 'TUESDAY, SEP 1');
      expect(selected.last, DateTime(2026, 9, 1));
    });

    testWidgets('returning to the current month selects today again', (tester) async {
      final selected = await _pump(tester, now: DateTime(2026, 10, 4, 15));
      await tester.tap(find.text('›'));
      await tester.pump();
      await tester.tap(find.text('‹'));
      await tester.pump();
      expect(_header(tester), 'SUNDAY, OCT 4');
      expect(selected.last, DateTime(2026, 10, 4));
    });

    testWidgets('the day list follows the new month', (tester) async {
      await _pump(tester,
          now: DateTime(2026, 10, 4, 15),
          injections: [_log(DateTime(2026, 11, 1, 9))]);
      expect(find.text('No entries on this day'), findsOneWidget);
      await tester.tap(find.text('›'));
      await tester.pump();
      expect(find.text('Testosterone Cypionate'), findsOneWidget);
    });
  });

  group('doses (format.dart)', () {
    testWidgets('fractional doses print without float noise', (tester) async {
      await _pump(tester,
          now: DateTime(2026, 10, 4, 15),
          injections: [_log(DateTime(2026, 10, 4, 9), dose: 0.1 + 0.2)]);
      expect(find.text('0.3 mg'), findsOneWidget);
    });
  });

  // Run under TZ=Europe/Kyiv to exercise the DST switches (Oct 25 2026,
  // Mar 28 2027); in any zone these must hold.
  group('month grid and day grouping across DST (B27)', () {
    for (final (now, days) in [
      (DateTime(2026, 10, 25, 12), 31), // DST ends
      (DateTime(2027, 3, 28, 12), 31), // DST starts
    ]) {
      testWidgets('${now.year}-${now.month}: every day 1..$days appears once', (tester) async {
        await _pump(tester, now: now);
        for (var d = 1; d <= days; d++) {
          expect(find.text('$d'), findsOneWidget, reason: 'day $d');
        }
        expect(find.text('${days + 1}'), findsNothing);
      });
    }

    testWidgets('a dose just after midnight following the switch stays on its day', (tester) async {
      final selected = await _pump(tester,
          now: DateTime(2026, 10, 25, 12),
          injections: [
            _log(DateTime(2026, 10, 25, 0, 30)), // before the 04:00 switch
            _log(DateTime(2026, 10, 26, 0, 30)), // first midnight after it
          ]);
      // Oct 25 (today) lists only its own dose.
      expect(find.text('1 entry'), findsOneWidget);
      await tester.tap(find.text('26'));
      await tester.pump();
      expect(selected.last, DateTime(2026, 10, 26));
      expect(_header(tester), 'MONDAY, OCT 26');
      expect(find.text('1 entry'), findsOneWidget);
      expect(find.text('00:30'), findsOneWidget);
    });
  });
}
