import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/engine/bloodwork_stats.dart';

BloodworkEntry _e(String id, String marker, DateTime date, double value,
        [String unit = 'u']) =>
    BloodworkEntry(id: id, date: date, marker: marker, value: value, unit: unit);

const _oxandrolone = CompoundDefinition(
  id: 'anavar', base: 'Oxandrolone', ester: 'None',
  type: CompoundType.oral, graphType: GraphType.curve,
  halfLife: 0.4, timeToPeak: 0.1, ratio: 1, unit: Unit.mg,
  colorValue: 0xFFC9B062,
);

void main() {
  final entries = [
    _e('t1', 'Total T', DateTime(2026, 5, 1), 30),
    _e('t2', 'Total T', DateTime(2026, 7, 1), 38.5),
    _e('e1', 'E2', DateTime(2026, 6, 1), 120),
    _e('t3', 'Total T', DateTime(2026, 6, 1), 34),
  ];

  group('distinctMarkers', () {
    test('orders markers by most recent draw', () {
      expect(distinctMarkers(entries), ['Total T', 'E2']);
    });
    test('empty input gives empty list', () {
      expect(distinctMarkers(const []), isEmpty);
    });
  });

  group('historyFor', () {
    test('returns only the marker, oldest first', () {
      final h = historyFor('Total T', entries);
      expect(h.map((e) => e.id).toList(), ['t1', 't3', 't2']);
    });
  });

  group('deltaVsPrevious', () {
    test('difference against the previous draw of the same marker', () {
      final d = deltaVsPrevious(entries[1], entries); // t2 (38.5) vs t3 (34)
      expect(d, closeTo(4.5, 1e-9));
    });
    test('null for the first draw of a marker', () {
      expect(deltaVsPrevious(entries[0], entries), isNull); // t1
      expect(deltaVsPrevious(entries[2], entries), isNull); // only E2
    });
  });

  group('mixed units (B34)', () {
    final mixed = [
      _e('a', 'Total T', DateTime(2026, 1, 1), 30, 'nmol/L'),
      _e('b', 'Total T', DateTime(2026, 3, 1), 900, 'ng/dL'),
      _e('c', 'Total T', DateTime(2026, 5, 1), 35, 'nmol/l'), // case differs
      _e('d', 'Total T', DateTime(2026, 6, 1), 950, 'ng/dL'),
      _e('e', 'Total T', DateTime(2026, 7, 1), 37, ' nmol/L '),
    ];

    test('deltas compare only same-unit draws', () {
      expect(previousDraw(mixed[2], mixed)!.id, 'a'); // skips the ng/dL draw
      expect(deltaVsPrevious(mixed[2], mixed), closeTo(5, 1e-9));
      expect(previousDraw(mixed[3], mixed)!.id, 'b');
      expect(deltaVsPrevious(mixed[3], mixed), closeTo(50, 1e-9));
      expect(previousDraw(mixed[1], mixed), isNull); // first ng/dL draw
    });

    test('unitsFor lists units most recently used first, deduped by key', () {
      expect(unitsFor('Total T', mixed), ['nmol/L', 'ng/dL']);
      expect(unitsFor('E2', mixed), isEmpty);
    });

    test('historyFor can be restricted to one unit', () {
      expect(historyFor('Total T', mixed, unit: 'NMOL/L').map((e) => e.id),
          ['a', 'c', 'e']);
      expect(historyFor('Total T', mixed, unit: 'ng/dL').map((e) => e.id),
          ['b', 'd']);
      expect(historyFor('Total T', mixed).length, 5);
    });
  });

  group('same-day draws (B34)', () {
    final sameDay = [
      _e('1751500000002', 'E2', DateTime(2026, 7, 3), 140),
      _e('1751500000001', 'E2', DateTime(2026, 7, 3), 120),
      _e('1751400000000', 'E2', DateTime(2026, 7, 1), 100),
    ];

    test('tie-break by id gives one deterministic order', () {
      expect(historyFor('E2', sameDay).map((e) => e.id),
          ['1751400000000', '1751500000001', '1751500000002']);
      expect(historyFor('E2', sameDay.reversed.toList()).map((e) => e.id),
          ['1751400000000', '1751500000001', '1751500000002']);
    });

    test('same-day draws do not each use the other as previous', () {
      expect(previousDraw(sameDay[0], sameDay)!.id, '1751500000001');
      expect(previousDraw(sameDay[1], sameDay)!.id, '1751400000000');
      expect(deltaVsPrevious(sameDay[0], sameDay), closeTo(20, 1e-9));
      expect(deltaVsPrevious(sameDay[1], sameDay), closeTo(20, 1e-9));
    });

    test('numeric ids compare numerically, others lexically', () {
      final a = _e('999', 'X', DateTime(2026, 1, 1), 1);
      final b = _e('1000', 'X', DateTime(2026, 1, 1), 2);
      expect(compareDraws(a, b), lessThan(0));
      final c = _e('imp-a', 'X', DateTime(2026, 1, 1), 1);
      final d = _e('imp-b', 'X', DateTime(2026, 1, 1), 2);
      expect(compareDraws(c, d), lessThan(0));
    });
  });

  group('PK overlay sampling (B34)', () {
    test('sample count scales with the span, floored and capped', () {
      final t0 = DateTime(2026, 1, 1);
      expect(overlaySampleCount(t0, t0.add(const Duration(days: 2))), 80);
      expect(overlaySampleCount(t0, t0.add(const Duration(days: 200))),
          greaterThanOrEqualTo(200 * 4));
      expect(overlaySampleCount(t0, t0.add(const Duration(days: 3650))),
          lessThanOrEqualTo(3000));
    });

    test('decimatePeaks keeps each bucket\'s max and the length bound', () {
      final raw = [for (var i = 0; i < 1000; i++) i % 10 == 3 ? 5.0 : 1.0];
      final d = decimatePeaks(raw, 100);
      expect(d.length, 100);
      expect(d.every((v) => v == 5.0), isTrue);
      expect(decimatePeaks([1, 2, 3], 100), [1, 2, 3]);
    });

    test('daily short-t½ doses over a long span do not alias', () {
      // Oxandrolone (t½ 0.4 d) every morning for 200 days. A fixed 81-point
      // grid lands at a different phase of each daily peak, drawing beats.
      final start = DateTime(2026, 1, 1);
      final injections = [
        for (var d = 0; d < 200; d++)
          Injection(
            id: 'o$d', compoundId: 'anavar',
            date: start.add(Duration(days: d, hours: 8)),
            dosage: 20, snapshot: _oxandrolone,
          ),
      ];
      final end = start.add(const Duration(days: 200));
      final samples = sampleOverlay(
        injections: injections, windowStart: start, windowEnd: end,
      );
      expect(samples.length, lessThanOrEqualTo(overlayMaxPoints));
      final peak = samples.reduce((a, b) => a > b ? a : b);
      // Any run of points covering a full day must contain that day's
      // peak — no low-frequency beat pattern in the envelope.
      final daysPerPoint = 200 / samples.length;
      final perDay = daysPerPoint >= 1 ? 1 : (1 / daysPerPoint).ceil() + 1;
      for (var i = 2; i + perDay < samples.length - 2; i++) {
        final run = samples.sublist(i, i + perDay);
        expect(run.reduce((a, b) => a > b ? a : b), greaterThan(0.9 * peak),
            reason: 'bucket run at $i misses the daily peak');
      }
    });
  });
}
