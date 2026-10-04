import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/widgets/bloodwork_card.dart';

void main() {
  final entries = [
    BloodworkEntry(
      id: 'b1', date: DateTime(2026, 7, 1), marker: 'Total T',
      value: 38.5, unit: 'nmol/L',
    ),
    BloodworkEntry(
      id: 'b2', date: DateTime(2026, 6, 2), marker: 'E2',
      value: 120, unit: 'pmol/L',
    ),
    BloodworkEntry(
      id: 'b0', date: DateTime(2026, 5, 1), marker: 'Total T',
      value: 30, unit: 'nmol/L',
    ),
  ];

  testWidgets('lists only the latest draw per marker, with its delta', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BloodworkCard(entries: entries, onCreate: () {}, onTap: (_) {}),
      ),
    ));
    expect(find.text('Bloodwork'), findsOneWidget);
    // One row per marker — older Total T draw is not listed.
    expect(find.text('Total T'), findsOneWidget);
    expect(find.text('38.5 nmol/L'), findsOneWidget);
    expect(find.text('30 nmol/L'), findsNothing);
    expect(find.text('120 pmol/L'), findsOneWidget);
    // Latest Total T still shows its change vs the previous draw.
    expect(find.text('↑ 8.5'), findsOneWidget);
  });

  testWidgets('delta has no float noise (B32)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BloodworkCard(
          entries: [
            BloodworkEntry(
              id: 'a', date: DateTime(2026, 5, 1), marker: 'Total T',
              value: 37.9, unit: 'nmol/L',
            ),
            BloodworkEntry(
              id: 'b', date: DateTime(2026, 6, 1), marker: 'Total T',
              value: 32.1, unit: 'nmol/L',
            ),
          ],
          onCreate: () {},
          onTap: (_) {},
        ),
      ),
    ));
    expect(find.text('↓ 5.8'), findsOneWidget);
    expect(find.textContaining('5.79999'), findsNothing);
  });

  group('hidden-marker badge', () {
    Future<void> pumpCard(WidgetTester tester, List<BloodworkEntry> e) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BloodworkCard(entries: e, onCreate: () {}, onTap: (_) {}),
            ),
          ),
        ));

    testWidgets('counts markers that did not fit, not draws', (tester) async {
      await pumpCard(tester, [
        for (var m = 0; m < 8; m++)
          BloodworkEntry(
            id: 'm$m', date: DateTime(2026, 6, 1 + m), marker: 'M$m',
            value: 1, unit: 'u',
          ),
      ]);
      expect(find.text('+2 more'), findsOneWidget);
      expect(find.textContaining('total'), findsNothing);
    });

    testWidgets('many draws of few markers show no badge', (tester) async {
      await pumpCard(tester, [
        for (var d = 0; d < 10; d++)
          BloodworkEntry(
            id: 'd$d', date: DateTime(2026, 1, 1 + d), marker: 'E2',
            value: 100.0 + d, unit: 'pmol/L',
          ),
      ]);
      expect(find.textContaining('more'), findsNothing);
      expect(find.textContaining('total'), findsNothing);
    });
  });

  testWidgets('empty state invites the first entry', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BloodworkCard(entries: const [], onCreate: () {}, onTap: (_) {}),
      ),
    ));
    expect(find.textContaining('No lab results'), findsOneWidget);
  });

  testWidgets('+ Add fires onCreate; row tap fires onTap with the entry', (tester) async {
    var created = false;
    BloodworkEntry? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BloodworkCard(
          entries: entries,
          onCreate: () => created = true,
          onTap: (e) => tapped = e,
        ),
      ),
    ));
    await tester.tap(find.text('+ Add'));
    expect(created, isTrue);
    await tester.tap(find.text('Total T')); // one row per marker now
    expect(tapped?.id, 'b1'); // the latest draw
  });
}
