import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/widgets/swimlane_card.dart';

const _tb500 = CompoundDefinition(
  id: 'tb', base: 'TB-500', ester: 'None',
  type: CompoundType.peptide, graphType: GraphType.activeWindow,
  halfLife: 2, timeToPeak: 0.5, ratio: 1,
  unit: Unit.mg, colorValue: 0xFFB5A8E0,
);

Injection _dose(String id, DateTime date,
        {double dosage = 5, CompoundDefinition snapshot = _tb500}) =>
    Injection(id: id, compoundId: snapshot.id, date: date, dosage: dosage, snapshot: snapshot);

Future<void> _pump(WidgetTester tester, List<Injection> injections, DateTime now) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SwimlaneCard(injections: injections, now: now),
        ),
      ),
    ));

double _max(List<double> v) => v.reduce((a, b) => a > b ? a : b);

void main() {
  group('NOW tick (B38)', () {
    testWidgets('lines up with the today line late in the day', (tester) async {
      final now = DateTime(2026, 10, 3, 22, 30);
      await _pump(tester, [_dose('a', now.subtract(const Duration(days: 2)))], now);

      final line = tester.getTopLeft(find.byKey(const Key('swimlane-today-line')));
      final tick = tester.getCenter(find.text('NOW'));
      expect(tick.dx, closeTo(line.dx + 0.5, 1.0));
    });
  });

  group('lane normalization (B39)', () {
    final now = DateTime(2026, 10, 3, 12);
    final windowStart = DateTime(2026, 10, 3).subtract(const Duration(days: 21));
    final windowEnd = windowStart.add(const Duration(days: 28));

    test('a nearly-cleared compound renders faint, not saturated', () {
      // One dose 6 days (3 half-lives) before the window opens: only its
      // tail is visible, at ~1/8 of the peak.
      final v = laneIntensities(
        injections: [_dose('a', windowStart.subtract(const Duration(days: 6)))],
        windowStart: windowStart,
        windowEnd: windowEnd,
      );
      expect(_max(v), lessThan(0.2));
      expect(_max(v), greaterThan(0));
    });

    test('a dose inside the window still peaks at full intensity', () {
      final v = laneIntensities(
        injections: [_dose('a', now.subtract(const Duration(days: 3)))],
        windowStart: windowStart,
        windowEnd: windowEnd,
      );
      expect(_max(v), closeTo(1.0, 1e-9));
    });

    test('regular dosing keeps its gradient relative to its own peak', () {
      final v = laneIntensities(
        injections: [
          for (var d = 40; d >= 0; d -= 2)
            _dose('d$d', now.subtract(Duration(days: d))),
        ],
        windowStart: windowStart,
        windowEnd: windowEnd,
      );
      expect(_max(v), greaterThan(0.9));
      expect(v.every((x) => x >= 0 && x <= 1), isTrue);
    });

    test('no doses → all zero', () {
      final v = laneIntensities(
        injections: const [],
        windowStart: windowStart,
        windowEnd: windowEnd,
      );
      expect(v.every((x) => x == 0), isTrue);
    });
  });

  group('relevance window (N4)', () {
    testWidgets('a legacy infinite / NaN half-life does not throw', (tester) async {
      final now = DateTime(2026, 10, 3, 12);
      final broken = [
        for (final hl in [double.infinity, double.nan])
          _dose('x$hl', now.subtract(const Duration(days: 30)),
              snapshot: CompoundDefinition(
                id: 'x', base: 'Legacy', ester: 'None',
                type: CompoundType.peptide, graphType: GraphType.event,
                halfLife: hl, timeToPeak: 0.1, ratio: 1,
                unit: Unit.mcg, colorValue: 0xFF999999,
              )),
      ];
      await _pump(tester, broken, now);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a dose before the window still shows while active', (tester) async {
      final now = DateTime(2026, 10, 3, 12);
      // 26 days back: 5 days before the 21-day window, inside 8 × t½ = 16 d.
      await _pump(tester, [_dose('a', now.subtract(const Duration(days: 26)))], now);
      expect(find.text('TB-500'), findsOneWidget);
    });
  });

  group('frequency label', () {
    Future<void> pumpEvery(WidgetTester tester, double days, {double dosage = 5}) {
      final now = DateTime(2026, 10, 3, 12);
      return _pump(tester, [
        for (var i = 0; i < 4; i++)
          _dose('i$i', now.subtract(Duration(minutes: (i * days * 24 * 60).round())),
              dosage: dosage),
      ], now);
    }

    final cases = <double, String>{
      1: 'daily',
      3: 'every 3d',
      3.5: 'every 3.5d',
      4: 'every 4d',
      6: 'every 6d',
      7: 'weekly',
      8: 'every 8d',
    };
    cases.forEach((days, label) {
      testWidgets('every $days d reads "$label"', (tester) async {
        await pumpEvery(tester, days);
        expect(find.text('5 mg · $label'), findsOneWidget);
      });
    });

    testWidgets('fractional doses are not truncated to 2 decimals', (tester) async {
      await pumpEvery(tester, 7, dosage: 0.125);
      expect(find.text('0.125 mg · weekly'), findsOneWidget);
    });
  });
}
