import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/widgets/pk_chart_card.dart';
import 'package:protolog_tracker/ui/widgets/pk_graph_painter.dart';

import 'pk_chart_test_support.dart';

void main() {
  const base = GraphSettings(
    normalized: false,
    cumulative: false,
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
        settings: base,
        curves: curves,
        maxMg: 11,
        maxOralMg: 6,
        startDate: start,
        endDate: end,
        totalDurationMs: end.difference(start).inMilliseconds,
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
  group('while a recompute is pending (B40)', () {
    // FutureBuilder keeps the previous result until compute() finishes, so
    // the card briefly holds data computed with older settings than the
    // pills show. The chart must keep drawing it the way it was computed.
    Future<List<RecordedInvocation>> pumpPending(
      WidgetTester tester, {
      required ComputedGraphData data,
      required GraphSettings live,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PKChartCard(
            graphData: data,
            settings: live,
            onRangeChanged: (_) {},
            onSettingsChanged: (_) {},
          ),
        ),
      ));
      final chart = tester.renderObject<RenderCustomPaint>(find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is PKGraphPainter));
      return recordPaint(chart.painter!, chart.size);
    }

    Size chartSize(WidgetTester tester) => tester
        .renderObject<RenderCustomPaint>(find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is PKGraphPainter))
        .size;

    testWidgets('tapping 7d keeps the old range\'s date labels', (tester) async {
      final data = pkData(curves: [pkCurve('Testosterone', 300)], maxMg: 330);
      final calls = await pumpPending(tester, data: data, live: pkSettings(timeRange: 'zoom'));
      expectWidths(xLabelWidths(calls, chartSize(tester)), expectedXLabelWidths(data, 'MMM d'));
    });

    testWidgets('turning Σ off keeps the total its y axis was scaled to', (tester) async {
      final data = pkData(
        curves: [pkCurve('Total Androgens', 300), pkCurve('Testosterone', 200)],
        maxMg: 330,
        settings: pkSettings(cumulative: true),
      );
      final calls = await pumpPending(tester, data: data, live: pkSettings());
      expect(paintedCumulativeFill(calls), isTrue);
    });

    testWidgets('turning "% of peak" on keeps the mg scale until new data', (tester) async {
      final data = pkData(
        curves: [pkCurve('Testosterone', 300)],
        markers: [InjectionMarkerData(0.3, 150, false, 0xFF5DC59C, 'Testosterone')],
        maxMg: 330, // → axis max 400
      );
      final calls = await pumpPending(tester, data: data, live: pkSettings(normalized: true));
      final chartHeight = chartSize(tester).height - pkPaddingBottom;
      expect(paintedCircles(calls).single.dy, closeTo(chartHeight * (1 - 150 / 400), 0.01));
    });

    testWidgets('the pills already show the live selection', (tester) async {
      GraphSettings? changed;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PKChartCard(
            graphData: pkData(settings: pkSettings(cumulative: true)),
            settings: pkSettings(),
            onRangeChanged: (_) {},
            onSettingsChanged: (s) => changed = s,
          ),
        ),
      ));
      // Live Σ is off (whatever the data says), so tapping turns it on.
      await tester.tap(find.text('Σ total'));
      expect(changed!.cumulative, isTrue);
    });
  });
}
