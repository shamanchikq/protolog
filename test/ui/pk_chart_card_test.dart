import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/widgets/pk_chart_card.dart';

void main() {
  const base = GraphSettings(
    normalized: false,
    cumulative: false,
    showPeptides: true,
    timeRange: 'standard',
  );

  Future<GraphSettings?> tapPill(WidgetTester tester, String label) async {
    GraphSettings? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PKChartCard(
          graphData: null,
          settings: base,
          onRangeChanged: (_) {},
          onSettingsChanged: (s) => changed = s,
        ),
      ),
    ));
    await tester.tap(find.text(label));
    await tester.pump();
    return changed;
  }

  testWidgets('"% of peak" pill toggles normalized only', (tester) async {
    final s = await tapPill(tester, '% of peak');
    expect(s, isNotNull);
    expect(s!.normalized, isTrue);
    expect(s.cumulative, isFalse);
    expect(s.timeRange, 'standard');
  });

  testWidgets('"Σ total" pill toggles cumulative only', (tester) async {
    final s = await tapPill(tester, 'Σ total');
    expect(s, isNotNull);
    expect(s!.cumulative, isTrue);
    expect(s.normalized, isFalse);
  });
}
