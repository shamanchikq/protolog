import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/theme.dart';
import 'package:protolog_tracker/ui/views/compound_detail_page.dart';
import 'package:protolog_tracker/ui/widgets/bloodwork_card.dart';
import 'package:protolog_tracker/ui/widgets/lab_primitives.dart';
import 'package:protolog_tracker/ui/widgets/load_hero.dart';
import 'package:protolog_tracker/ui/widgets/pk_chart_card.dart';
import 'package:protolog_tracker/ui/widgets/protolog_shell.dart';
import 'package:protolog_tracker/ui/widgets/swimlane_card.dart';

import 'real_fonts.dart';

/// C1: Android "Large" (1.15×) / "Largest" (1.3×) text on a 360 dp phone
/// must not overflow the dashboard cards or the tab bar. Measured with the
/// bundled fonts — the test font's square glyphs give false results.
const _scales = [1.0, 1.15, 1.3];

Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, {
  double width = 360,
  double height = 2400,
  required double scale,
  bool dashboardPadding = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        child: dashboardPadding
            ? Scaffold(
                backgroundColor: AppTheme.bg,
                body: SingleChildScrollView(
                  // Dashboard list padding (main.dart).
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 90),
                  child: child,
                ),
              )
            : child,
      ),
    ),
  ));
  await tester.pump();
}

const _peptide = CompoundDefinition(
  id: 'tb', base: 'TB-500', ester: 'None',
  type: CompoundType.peptide, graphType: GraphType.activeWindow,
  halfLife: 2, timeToPeak: 0.5, ratio: 1, unit: Unit.mg, colorValue: 0xFFB5A8E0,
);
const _ancillary = CompoundDefinition(
  id: 'ai', base: 'Anastrozole', ester: 'None',
  type: CompoundType.ancillary, graphType: GraphType.activeWindow,
  halfLife: 2, timeToPeak: 0.1, ratio: 1, unit: Unit.mg, colorValue: 0xFFD27A6B,
);

const _mcgPeptide = CompoundDefinition(
  id: 'ipa', base: 'Ipamorelin', ester: 'None',
  type: CompoundType.peptide, graphType: GraphType.activeWindow,
  halfLife: 0.083, timeToPeak: 0.021, ratio: 1, unit: Unit.mcg, colorValue: 0xFFD27A6B,
);
const _bigYield = CompoundDefinition(
  id: 'nan', base: 'Nandrolone', ester: 'Decanoate',
  type: CompoundType.steroid, graphType: GraphType.curve,
  halfLife: 14.5, timeToPeak: 2.75, ratio: 0.643, unit: Unit.mg, colorValue: 0xFF87BFE0,
);

ComputedGraphData _graph() {
  final start = DateTime(2026, 9, 5);
  final end = DateTime(2026, 11, 7, 23, 59);
  return ComputedGraphData(
    settings: const GraphSettings(normalized: false, cumulative: false, timeRange: 'standard'),
    curves: [
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

LoadHeroData _hero(double total, int rows) => LoadHeroData(
      totalActiveMg: total,
      delta: -12.3,
      breakdown: [
        for (var i = 0; i < rows; i++)
          LoadHeroRow(
            label: ['Testosterone', 'Nandrolone', 'Masteron', 'Trenbolone', 'Primobolan', 'Oxandrolone', 'Boldenone'][i % 7],
            valueMg: total / rows,
            shareOfTotal: 1 / rows,
            color: AppTheme.accent,
          ),
      ],
    );

void main() {
  setUpAll(loadAppFonts);

  for (final scale in _scales) {
    group('text scale $scale on 360 dp', () {
      testWidgets('PK chart header', (tester) async {
        await _pumpAt(
          tester,
          PKChartCard(
            graphData: _graph(),
            settings: const GraphSettings(
              normalized: false, cumulative: false, timeRange: 'standard',
            ),
            onRangeChanged: (_) {},
            onSettingsChanged: (_) {},
          ),
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Pharmacokinetics'), findsOneWidget);
        expect(find.text('Cycle'), findsOneWidget);
      });

      testWidgets('swimlane header and lanes', (tester) async {
        final now = DateTime(2026, 10, 3, 21);
        await _pumpAt(
          tester,
          SwimlaneCard(
            now: now,
            injections: [
              for (var d = 0; d < 10; d += 2) ...[
                Injection(id: 'p$d', compoundId: 'tb', date: now.subtract(Duration(days: d)), dosage: 2.5, snapshot: _peptide),
                Injection(id: 'a$d', compoundId: 'ai', date: now.subtract(Duration(days: d)), dosage: 0.5, snapshot: _ancillary),
              ],
            ],
          ),
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Peptides & ancillaries'), findsOneWidget);
      });

      for (final rows in [1, 4, 7]) {
        for (final total in [12.34, 456.7, 1234.5]) {
          testWidgets('LoadHero total $total with $rows rows', (tester) async {
            await _pumpAt(tester, LoadHero(data: _hero(total, rows)), scale: scale);
            expect(tester.takeException(), isNull);
            expect(find.textContaining('Injectables 7d'), findsOneWidget);
          });
        }
      }

      testWidgets('bloodwork card rows', (tester) async {
        await _pumpAt(
          tester,
          BloodworkCard(
            entries: [
              BloodworkEntry(id: '1', date: DateTime(2026, 5, 30), marker: 'Total testosterone', value: 1234.5, unit: 'ng/dL'),
              BloodworkEntry(id: '2', date: DateTime(2026, 9, 30), marker: 'Total testosterone', value: 1111.9, unit: 'ng/dL'),
              BloodworkEntry(id: '3', date: DateTime(2026, 9, 28), marker: 'Estradiol (sensitive)', value: 120, unit: 'pmol/L'),
            ],
            onCreate: () {},
            onTap: (_) {},
          ),
          scale: scale,
        );
        expect(tester.takeException(), isNull);
      });

      // The PK metric tiles: four LabMetrics in a row (overflowed ~1 px at
      // 1.3× before).
      for (final c in [_mcgPeptide, _bigYield]) {
        testWidgets('compound detail metrics (${c.base})', (tester) async {
          await _pumpAt(
            tester,
            CompoundDetailPage(
              compound: c,
              injections: const [],
              onTabChanged: (_) {},
              openEditor: (_) async => null,
              onDelete: () {},
              onLogInjection: (_) {},
            ),
            scale: scale,
            dashboardPadding: false,
            height: 1400,
          );
          expect(tester.takeException(), isNull);
          expect(find.byType(LabMetric), findsNWidgets(4));
        });
      }

      testWidgets('tab bar', (tester) async {
        await _pumpAt(
          tester,
          ProtoLogShell(
            activeTab: ShellTab.reminders,
            onTabChanged: (_) {},
            onFabPressed: () {},
            fabLabel: 'New reminder',
            body: const SizedBox.expand(),
          ),
          scale: scale,
          dashboardPadding: false,
          height: 800,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Reminders'), findsOneWidget);
      });
    });
  }

  testWidgets('tab bar at 1.5× on a 320 dp phone', (tester) async {
    await _pumpAt(
      tester,
      ProtoLogShell(
        activeTab: ShellTab.today,
        onTabChanged: (_) {},
        body: const SizedBox.expand(),
      ),
      width: 320,
      height: 700,
      scale: 1.5,
      dashboardPadding: false,
    );
    expect(tester.takeException(), isNull);
  });

  group('default text size keeps the original layout', () {
    testWidgets('tabs still span the bar (spaceBetween)', (tester) async {
      await _pumpAt(
        tester,
        ProtoLogShell(activeTab: ShellTab.today, onTabChanged: (_) {}, body: const SizedBox.expand()),
        scale: 1.0,
        dashboardPadding: false,
        height: 800,
      );
      expect(tester.getTopLeft(find.text('Today')).dx, closeTo(18, 0.5));
      expect(tester.getTopRight(find.text('Reminders')).dx, closeTo(360 - 18, 0.5));
    });

    testWidgets('PK title and range pills share one row', (tester) async {
      await _pumpAt(
        tester,
        PKChartCard(
          graphData: _graph(),
          settings: const GraphSettings(
            normalized: false, cumulative: false, timeRange: 'standard',
          ),
          onRangeChanged: (_) {},
          onSettingsChanged: (_) {},
        ),
        scale: 1.0,
      );
      expect(tester.getCenter(find.text('1y')).dy,
          closeTo(tester.getCenter(find.text('Pharmacokinetics')).dy, 1));
    });

    Future<void> pumpDetail(WidgetTester tester, CompoundDefinition c, double scale) => _pumpAt(
          tester,
          CompoundDetailPage(
            compound: c,
            injections: const [],
            onTabChanged: (_) {},
            openEditor: (_) async => null,
            onDelete: () {},
            onLogInjection: (_) {},
          ),
          scale: scale,
          dashboardPadding: false,
          height: 1400,
        );

    testWidgets('LabMetric values are not scaled when they fit', (tester) async {
      await pumpDetail(tester, _bigYield, 1.0);
      for (final v in ['14.5', '2.75', '64.3', 'mg']) {
        final local = tester.getSize(find.text(v));
        final global = tester.getRect(find.text(v));
        expect(global.width, closeTo(local.width, 0.01), reason: v);
      }
    });

    testWidgets('a long LabMetric value scales down to fit its tile', (tester) async {
      await pumpDetail(tester, _mcgPeptide, 1.3);
      final local = tester.getSize(find.text('0.083'));
      final global = tester.getRect(find.text('0.083'));
      expect(global.width, lessThan(local.width));
    });

    testWidgets('LoadHero number is not scaled when it fits', (tester) async {
      await _pumpAt(tester, LoadHero(data: _hero(12.34, 2)), scale: 1.0);
      final local = tester.getSize(find.text('12'));
      final global = tester.getRect(find.text('12'));
      expect(global.width, closeTo(local.width, 0.01));
    });

    testWidgets('LoadHero number scales down instead of overflowing', (tester) async {
      await _pumpAt(tester, LoadHero(data: _hero(1234.5, 7)), scale: 1.3);
      final local = tester.getSize(find.text('1234'));
      final global = tester.getRect(find.text('1234'));
      expect(global.width, lessThan(local.width));
    });
  });
}
