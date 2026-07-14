import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/engine/bloodwork_stats.dart';

BloodworkEntry _e(String id, String marker, DateTime date, double value) =>
    BloodworkEntry(id: id, date: date, marker: marker, value: value, unit: 'u');

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
}
