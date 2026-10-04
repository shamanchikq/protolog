import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/engine/calendar.dart';
import 'package:protolog_tracker/engine/compute_engine.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/theme.dart';
import 'package:protolog_tracker/ui/widgets/load_hero.dart';
import 'package:protolog_tracker/ui/widgets/pk_chart_card.dart';
import 'package:protolog_tracker/ui/widgets/swimlane_card.dart';
import 'package:protolog_tracker/ui/widgets/tap_target.dart';

import 'real_fonts.dart';

// C2: the charts speak a short data-derived summary instead of tick labels;
// range pills say which span they cover (the PK card's and the swimlanes'
// "7d" cover different windows).

const _standard = GraphSettings(normalized: false, cumulative: false, timeRange: 'standard');

ComputedGraphData _graph({GraphSettings settings = _standard, List<CurveData>? curves}) {
  final start = DateTime(2026, 9, 5);
  final end = DateTime(2026, 11, 7, 23, 59);
  return ComputedGraphData(
    settings: settings,
    curves: curves ??
        [
          CurveData('Testosterone', 0xFF5DC59C, false, const [Offset(0, 0), Offset(0.5, 300), Offset(1, 100)]),
          CurveData('Oxandrolone', 0xFFC9B062, true, const [Offset(0, 0), Offset(0.4, 30), Offset(1, 0)]),
        ],
    maxMg: 330,
    maxOralMg: 36,
    startDate: start,
    endDate: end,
    totalDurationMs: end.difference(start).inMilliseconds,
    injectionMarkers: const [],
  );
}

Future<void> _pump(WidgetTester tester, Widget card) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 1200);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      backgroundColor: AppTheme.bg,
      body: TapTargetScope(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 90),
          child: card,
        ),
      ),
    ),
  ));
  await tester.pump();
}

SemanticsNode _pill(WidgetTester tester, String label) => tester.getSemantics(
    find.ancestor(of: find.text(label), matching: find.byType(TapTargetBox)).first);

/// Labels of [root]'s descendants in screen-reader order.
List<String> _readingOrder(SemanticsNode root) {
  final out = <String>[];
  void visit(SemanticsNode n) {
    if (n.label.isNotEmpty) out.add(n.label);
    for (final c in n.debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)) {
      visit(c);
    }
  }
  visit(root);
  return out;
}

void main() {
  setUpAll(loadAppFonts);

  group('PK chart', () {
    test('summary names the span, the compounds and the modes', () {
      expect(pkChartSemanticsLabel(_graph()),
          'Pharmacokinetics chart, 28 days back, 35 ahead. Testosterone, Oxandrolone (oral).');
      expect(
        pkChartSemanticsLabel(_graph(
          settings: const GraphSettings(normalized: true, cumulative: true, timeRange: 'zoom'),
          curves: [
            CurveData('Testosterone', 0xFF5DC59C, false, const [Offset(0, 1)]),
            CurveData(totalCurveName, 0xFFFFFFFF, false, const [Offset(0, 1)]),
          ],
        )),
        'Pharmacokinetics chart, 7 days back, 7 ahead. Testosterone. '
        'Each curve as a percentage of its peak. With the summed total.',
      );
      expect(pkChartSemanticsLabel(_graph(curves: const [])),
          'Pharmacokinetics chart, 28 days back, 35 ahead. No injectable or oral doses in this range.');
      expect(pkChartSemanticsLabel(null), 'Pharmacokinetics chart, loading');
    });

    test("pill spans are the engine's windows", () async {
      final now = DateTime(2026, 10, 3, 21);
      for (final (key, _, back, ahead) in pkChartRanges) {
        final d = await computeGraphData(
          IsolateInput(const [], GraphSettings(normalized: false, cumulative: false, timeRange: key)),
          now: now,
        );
        expect(calendarDaysBetween(d.startDate, now), back, reason: key);
        expect(calendarDaysBetween(now, d.endDate), ahead, reason: key);
      }
    });

    testWidgets('one summary node; pills say their span; title reads first', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        PKChartCard(graphData: _graph(), settings: _standard, onRangeChanged: (_) {}, onSettingsChanged: (_) {}),
      );
      expect(find.bySemanticsLabel(RegExp(r'^Pharmacokinetics chart, 28 days back')), findsOneWidget);
      // Tick labels are painted, never spoken.
      expect(find.bySemanticsLabel('Sep 5'), findsNothing);

      final p28 = _pill(tester, '28d');
      expect(p28.tooltip, '28 days back, 35 ahead');
      expect(p28.getSemanticsData().flagsCollection.isSelected.toBoolOrNull(), isTrue);
      expect(_pill(tester, '7d').tooltip, '7 days back, 7 ahead');
      expect(_pill(tester, 'Cycle').tooltip, '90 days back, 30 ahead');
      expect(_pill(tester, '1y').tooltip, '365 days back, 30 ahead');
      expect(_pill(tester, 'Σ total').label, 'Summed total');

      final order = _readingOrder(tester.getSemantics(find.byType(Scaffold)));
      expect(order.indexOf('Pharmacokinetics'), lessThan(order.indexOf('7d')));
      expect(order.indexOf('1y'), lessThan(order.indexOf('% of peak')));
      handle.dispose();
    });

    testWidgets('long-pressing a range pill shows its span', (tester) async {
      await _pump(
        tester,
        PKChartCard(graphData: _graph(), settings: _standard, onRangeChanged: (_) {}, onSettingsChanged: (_) {}),
      );
      await tester.longPress(find.text('Cycle'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('90 days back, 30 ahead'), findsOneWidget);
    });
  });

  group('swimlanes', () {
    const peptide = CompoundDefinition(
      id: 'tb', base: 'TB-500', ester: 'None',
      type: CompoundType.peptide, graphType: GraphType.activeWindow,
      halfLife: 2, timeToPeak: 0.5, ratio: 1, unit: Unit.mg, colorValue: 0xFFB5A8E0,
    );
    const ancillary = CompoundDefinition(
      id: 'ai', base: 'Anastrozole', ester: 'None',
      type: CompoundType.ancillary, graphType: GraphType.activeWindow,
      halfLife: 2, timeToPeak: 0.1, ratio: 1, unit: Unit.mg, colorValue: 0xFFD27A6B,
    );

    test('summary names the span and the lanes', () {
      expect(
        swimlaneSemanticsLabel(daysBack: 21, daysAhead: 7, peptides: ['TB-500'], ancillaries: ['Anastrozole']),
        '21 days back, 7 ahead. Peptides: TB-500. Ancillaries: Anastrozole.',
      );
      expect(swimlaneSemanticsLabel(daysBack: 5, daysAhead: 2, peptides: [], ancillaries: []),
          '5 days back, 2 ahead.');
    });

    testWidgets('summary, one node per lane, spans on the pills, no axis ticks', (tester) async {
      final handle = tester.ensureSemantics();
      final now = DateTime(2026, 10, 3, 21);
      await _pump(
        tester,
        SwimlaneCard(
          now: now,
          injections: [
            Injection(id: 'p', compoundId: 'tb', date: now.subtract(const Duration(days: 1)), dosage: 2.5, snapshot: peptide),
            Injection(id: 'a', compoundId: 'ai', date: now.subtract(const Duration(days: 2)), dosage: 0.5, snapshot: ancillary),
          ],
        ),
      );
      expect(find.bySemanticsLabel('21 days back, 7 ahead. Peptides: TB-500. Ancillaries: Anastrozole.'),
          findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^TB-500\n2\.5 mg')), findsOneWidget);
      expect(find.bySemanticsLabel('NOW'), findsNothing);
      expect(find.bySemanticsLabel('active window'), findsNothing);
      expect(_pill(tester, '7d').tooltip, '5 days back, 2 ahead');
      expect(_pill(tester, '90d').tooltip, '67 days back, 23 ahead');
      handle.dispose();
    });
  });

  testWidgets('LoadHero speaks one sentence', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const LoadHero(
        data: LoadHeroData(
          totalActiveMg: 189.46,
          delta: -12.34,
          breakdown: [LoadHeroRow(label: 'Testosterone', valueMg: 167, shareOfTotal: 0.88, color: AppTheme.accent)],
        ),
      ),
    );
    expect(find.bySemanticsLabel('Total load 189.5 mg. Injectables 7 day trend: down 12.3 mg.'), findsOneWidget);
    expect(find.bySemanticsLabel('↘'), findsNothing);
    expect(find.bySemanticsLabel('Testosterone\n167'), findsOneWidget);
    handle.dispose();
  });
}
