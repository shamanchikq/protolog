import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';

void main() {
  group('BloodworkEntry serde', () {
    test('round-trips all fields', () {
      final e = BloodworkEntry(
        id: 'b1',
        date: DateTime(2026, 7, 1, 9, 30),
        marker: 'Total T',
        value: 38.5,
        unit: 'nmol/L',
        notes: 'trough, 84h post-pin',
      );
      final back = BloodworkEntry.fromJson(e.toJson());
      expect(back.id, 'b1');
      expect(back.date, DateTime(2026, 7, 1, 9, 30));
      expect(back.marker, 'Total T');
      expect(back.value, 38.5);
      expect(back.unit, 'nmol/L');
      expect(back.notes, 'trough, 84h post-pin');
    });

    test('notes are optional and integer values parse as double', () {
      final back = BloodworkEntry.fromJson({
        'id': 'b2',
        'date': '2026-07-01T09:30:00.000',
        'marker': 'E2',
        'value': 120, // int in stored JSON
        'unit': 'pmol/L',
      });
      expect(back.notes, isNull);
      expect(back.value, 120.0);
      expect(back.value, isA<double>());
    });

    test('copyWith replaces only the given fields', () {
      final e = BloodworkEntry(
        id: 'b3', date: DateTime(2026, 7, 1), marker: 'SHBG',
        value: 30, unit: 'nmol/L',
      );
      final e2 = e.copyWith(value: 28);
      expect(e2.id, 'b3');
      expect(e2.marker, 'SHBG');
      expect(e2.value, 28.0);
    });
  });
}
