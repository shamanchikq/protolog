import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/data.dart';
import 'package:protolog_tracker/ui/views/dashboard_view.dart';
import 'package:protolog_tracker/ui/widgets/pk_chart_card.dart';
import 'package:protolog_tracker/ui/widgets/swimlane_card.dart';

void main() {
  const settings = GraphSettings(
    normalized: true,
    cumulative: false,
    timeRange: 'standard',
  );

  testWidgets('a range pill reports the current settings with the new range', (tester) async {
    final changes = <GraphSettings>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardView(
          injections: const [],
          bloodwork: const [],
          graphData: null,
          settings: settings,
          colorResolver: (_) => Colors.grey,
          now: DateTime(2026, 10, 3, 12),
          onSettingsChanged: changes.add,
          onAddBloodwork: () {},
          onOpenBloodwork: (_) {},
        ),
      ),
    ));

    await tester.tap(find.text('1y').first);
    await tester.pump();

    expect(changes, hasLength(1));
    expect(changes.single.timeRange, 'year');
    expect(changes.single.normalized, isTrue, reason: 'other settings carry over');
  });

  group('swimlane memo (E2)', () {
    final now = DateTime(2026, 10, 3, 12);
    final bpc = BASE_LIBRARY['BPC-157']!;
    Injection dose(int daysAgo) => Injection(
          id: 'i$daysAgo', compoundId: bpc.id,
          date: now.subtract(Duration(days: daysAgo)), dosage: 250, snapshot: bpc,
        );
    Color grey(String _) => Colors.grey;
    Color black(String _) => Colors.black;

    Future<SwimlaneCard> pump(
      WidgetTester tester, {
      required List<Injection> injections,
      int revision = 0,
      DateTime? at,
      Color Function(String base)? resolver,
      GraphSettings graphSettings = settings,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DashboardView(
            injections: injections,
            injectionsRevision: revision,
            bloodwork: const [],
            graphData: null,
            settings: graphSettings,
            colorResolver: resolver ?? grey,
            now: at ?? now,
            onSettingsChanged: (_) {},
            onAddBloodwork: () {},
            onOpenBloodwork: (_) {},
          ),
        ),
      ));
      return tester.widget<SwimlaneCard>(find.byType(SwimlaneCard));
    }

    testWidgets('an unrelated rebuild reuses the card, so lanes are not resampled',
        (tester) async {
      final logs = [dose(1), dose(3)];
      final first = await pump(tester, injections: logs);
      expect(find.text('BPC-157'), findsOneWidget);
      const zoom = GraphSettings(
          normalized: false, cumulative: true, timeRange: 'zoom');
      expect(await pump(tester, injections: logs, graphSettings: zoom), same(first));
      expect(await pump(tester, injections: logs, at: now.add(const Duration(seconds: 30))),
          same(first), reason: 'now moved less than a minute');
      // The chart gets the same resolver too, so its painter needn't repaint.
      expect(tester.widget<PKChartCard>(find.byType(PKChartCard)).colorResolver, same(grey));
    });

    testWidgets('a change to the logs, the resolver or the minute rebuilds it', (tester) async {
      final logs = [dose(1), dose(3)];
      var card = await pump(tester, injections: logs);

      Future<void> expectNew(Future<SwimlaneCard> next, String reason) async {
        final c = await next;
        expect(c, isNot(same(card)), reason: reason);
        card = c;
      }

      await expectNew(pump(tester, injections: logs, revision: 1), 'edited in place');
      logs.add(dose(5));
      await expectNew(pump(tester, injections: logs, revision: 1), 'grew in place');
      await expectNew(pump(tester, injections: [...logs], revision: 1), 'another list');
      await expectNew(pump(tester, injections: card.injections, revision: 1, resolver: black),
          'a recolor');
      await expectNew(
          pump(tester, injections: card.injections, revision: 1, resolver: black,
              at: now.add(const Duration(minutes: 2))),
          'now moved on');
      expect(card.now, now.add(const Duration(minutes: 2)));
    });
  });
}
