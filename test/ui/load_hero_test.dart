import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/ui/widgets/load_hero.dart';

Future<void> _pump(WidgetTester tester, LoadHeroData data) => tester.pumpWidget(MaterialApp(
      home: Scaffold(body: LoadHero(data: data)),
    ));

void main() {
  testWidgets('trend caption names the injectables-only basis', (tester) async {
    await _pump(tester, const LoadHeroData(totalActiveMg: 0, delta: 0, breakdown: []));
    expect(find.textContaining('Injectables 7d'), findsOneWidget);
    expect(find.textContaining('Last 7 days'), findsNothing);
  });

  group('rounding (B37)', () {
    final totals = <double, (String, String)>{
      12.96: ('13', '.0'),
      12.94: ('12', '.9'),
      0.04: ('0', '.0'),
      0.06: ('0', '.1'),
      249.99: ('250', '.0'),
      7.0: ('7', '.0'),
    };
    totals.forEach((total, expected) {
      testWidgets('total $total renders ${expected.$1}${expected.$2}', (tester) async {
        await _pump(tester, LoadHeroData(totalActiveMg: total, delta: 0, breakdown: const []));
        expect(find.text(expected.$1), findsOneWidget);
        expect(find.text(expected.$2), findsOneWidget);
      });
    });

    final deltas = <double, (String, String)>{
      -0.03: ('→', ' +0.0'),
      -0.049: ('→', ' +0.0'),
      0.03: ('→', ' +0.0'),
      0.0: ('→', ' +0.0'),
      -0.06: ('↘', ' −0.1'),
      0.06: ('↗', ' +0.1'),
      1.96: ('↗', ' +2.0'),
      -1.96: ('↘', ' −2.0'),
    };
    deltas.forEach((delta, expected) {
      testWidgets('delta $delta renders ${expected.$1}${expected.$2}', (tester) async {
        await _pump(tester, LoadHeroData(totalActiveMg: 10, delta: delta, breakdown: const []));
        expect(find.text(expected.$1), findsOneWidget);
        expect(find.text(expected.$2), findsOneWidget);
        expect(find.textContaining('−0.0'), findsNothing);
      });
    });
  });

  group('non-finite values (A6)', () {
    for (final total in [double.infinity, double.negativeInfinity, double.nan, 1e308]) {
      testWidgets('total $total renders a dash instead of throwing', (tester) async {
        await _pump(tester, LoadHeroData(totalActiveMg: total, delta: 0, breakdown: const []));
        expect(tester.takeException(), isNull);
        expect(find.text('—'), findsOneWidget);
        expect(find.text('mg'), findsOneWidget);
      });
    }

    for (final delta in [double.infinity, double.negativeInfinity, double.nan]) {
      testWidgets('delta $delta renders a neutral dash', (tester) async {
        await _pump(tester, LoadHeroData(totalActiveMg: 12, delta: delta, breakdown: const []));
        expect(tester.takeException(), isNull);
        expect(find.text('→'), findsOneWidget);
        expect(find.text(' —'), findsOneWidget);
        expect(find.textContaining('NaN'), findsNothing);
        expect(find.textContaining('Infinity'), findsNothing);
      });
    }

    testWidgets('breakdown rows with non-finite values render a dash', (tester) async {
      await _pump(
        tester,
        const LoadHeroData(totalActiveMg: double.nan, delta: double.nan, breakdown: [
          LoadHeroRow(label: 'Testosterone', valueMg: double.infinity, shareOfTotal: double.nan, color: Colors.green),
          LoadHeroRow(label: 'Oxandrolone', valueMg: double.nan, shareOfTotal: double.infinity, color: Colors.amber),
        ]),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Testosterone'), findsOneWidget);
      expect(find.textContaining('NaN'), findsNothing);
      expect(find.textContaining('Infinity'), findsNothing);
      final bars = tester.widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox));
      expect(bars.every((b) => b.widthFactor == 0.0), isTrue);
    });
  });
}
