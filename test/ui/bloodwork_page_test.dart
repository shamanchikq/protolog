import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/bloodwork_page.dart';

BloodworkEntry _e(String id, String marker, DateTime date, double value, String unit) =>
    BloodworkEntry(id: id, date: date, marker: marker, value: value, unit: unit);

void main() {
  final entries = [
    _e('t1', 'Total T', DateTime(2026, 5, 1), 30, 'nmol/L'),
    _e('t2', 'Total T', DateTime(2026, 7, 1), 38.5, 'nmol/L'),
    _e('e1', 'E2', DateTime(2026, 6, 1), 120, 'pmol/L'),
  ];

  Future<void> pump(WidgetTester tester,
      {void Function(List<BloodworkEntry>)? onChanged,
      String? initialMarker,
      List<Injection> injections = const []}) async {
    await tester.pumpWidget(MaterialApp(
      home: BloodworkPage(
        initialEntries: entries,
        initialMarker: initialMarker,
        markerSuggestions: const {'Total T': 'nmol/L'},
        injections: injections,
        onChanged: onChanged ?? (_) {},
      ),
    ));
  }

  testWidgets('shows marker chips and the selected marker history with deltas', (tester) async {
    await pump(tester);
    expect(find.text('Bloodwork'), findsOneWidget);
    // Total T is most recent -> selected by default; both chips present.
    expect(find.text('Total T'), findsWidgets);
    expect(find.text('E2'), findsOneWidget);
    // History newest first with delta vs previous draw.
    expect(find.text('38.5 nmol/L'), findsWidgets);
    expect(find.textContaining('↑ 8.5'), findsOneWidget); // 38.5 vs 30
  });

  testWidgets('tapping another marker chip switches the history', (tester) async {
    await pump(tester);
    await tester.tap(find.text('E2'));
    await tester.pump();
    expect(find.text('120 pmol/L'), findsWidgets);
  });

  testWidgets('PK overlay pill appears with injections and toggles cleanly', (tester) async {
    const testE = CompoundDefinition(
      id: 'test_e', base: 'Testosterone', ester: 'Enanthate',
      type: CompoundType.steroid, graphType: GraphType.curve,
      halfLife: 4.5, timeToPeak: 1.5, ratio: 0.72,
      unit: Unit.mg, colorValue: 0xFF5DC59C,
    );
    const bpc = CompoundDefinition(
      id: 'bpc', base: 'BPC-157', ester: 'None',
      type: CompoundType.peptide, graphType: GraphType.activeWindow,
      halfLife: 0.2, timeToPeak: 0.05, ratio: 1.0,
      unit: Unit.mcg, colorValue: 0xFF8FC5A8,
    );
    final injections = [
      Injection(id: 'i1', compoundId: 'test_e',
          date: DateTime(2026, 6, 10), dosage: 250, snapshot: testE),
      Injection(id: 'i2', compoundId: 'bpc',
          date: DateTime(2026, 6, 20), dosage: 250, snapshot: bpc),
    ];
    await pump(tester, injections: injections);
    expect(find.text('PK overlay'), findsOneWidget);
    await tester.tap(find.text('PK overlay'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('PK overlay')); // toggle back off
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('initialMarker preselects; + Add saves through the dialog and fires onChanged',
      (tester) async {
    List<BloodworkEntry>? changed;
    await pump(tester, onChanged: (l) => changed = l, initialMarker: 'E2');
    expect(find.text('120 pmol/L'), findsWidgets);

    await tester.tap(find.text('+ Add'));
    await tester.pumpAndSettle();
    expect(find.text('Add lab result'), findsOneWidget);
    await tester.tap(find.text('Total T').last); // suggestion chip in dialog
    await tester.pump();
    await tester.enterText(find.byKey(const Key('bloodwork-value')), '41');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(changed, isNotNull);
    expect(changed!.length, 4);
    expect(changed!.last.value, 41.0);
  });
}
