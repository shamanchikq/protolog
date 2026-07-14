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

  testWidgets('lists entries newest first with marker, value, unit', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BloodworkCard(entries: entries, onCreate: () {}, onTap: (_) {}),
      ),
    ));
    expect(find.text('Bloodwork'), findsOneWidget);
    expect(find.text('Total T'), findsNWidgets(2));
    expect(find.text('38.5 nmol/L'), findsOneWidget);
    expect(find.text('120 pmol/L'), findsOneWidget);
    // Latest Total T shows its change vs the previous draw.
    expect(find.text('↑ 8.5'), findsOneWidget);
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
    await tester.tap(find.text('Total T').first); // newest row first
    expect(tapped?.id, 'b1');
  });
}
