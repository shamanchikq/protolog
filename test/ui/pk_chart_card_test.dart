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

  group('empty state (B36)', () {
    ComputedGraphData data(List<CurveData> curves) {
      final start = DateTime(2026, 9, 5);
      final end = DateTime(2026, 11, 7);
      return ComputedGraphData(
        curves: curves,
        peptideLanes: const [],
        laneLabels: const [],
        maxMg: 11,
        maxOralMg: 6,
        startDate: start,
        endDate: end,
        totalDurationMs: end.difference(start).inMilliseconds,
        laneCount: 0,
        injectionMarkers: const [],
      );
    }

    Future<void> pumpCard(WidgetTester tester, ComputedGraphData d) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: PKChartCard(
              graphData: d,
              settings: base,
              onRangeChanged: (_) {},
              onSettingsChanged: (_) {},
            ),
          ),
        ));

    testWidgets('no curves shows a message instead of a bare grid', (tester) async {
      await pumpCard(tester, data(const []));
      expect(find.textContaining('No injectable or oral doses'), findsOneWidget);
    });

    testWidgets('with a curve there is no message', (tester) async {
      await pumpCard(tester, data([
        CurveData('Testosterone', 0xFF5DC59C, false, const [Offset(0, 0), Offset(1, 5)]),
      ]));
      expect(find.textContaining('No injectable or oral doses'), findsNothing);
    });
  });
}
