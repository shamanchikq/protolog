import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/ui/views/wizard/when_section.dart';

void main() {
  group('formatRelativeDate', () {
    final now = DateTime(2026, 5, 18, 9, 30);

    test('today / yesterday / tomorrow / this year / other year', () {
      expect(formatRelativeDate(DateTime(2026, 5, 18, 23, 59), now: now), 'Today, May 18');
      expect(formatRelativeDate(DateTime(2026, 5, 17, 0, 1), now: now), 'Yesterday, May 17');
      expect(formatRelativeDate(DateTime(2026, 5, 19), now: now), 'Tomorrow, May 19');
      expect(formatRelativeDate(DateTime(2026, 5, 10), now: now), 'May 10');
      expect(formatRelativeDate(DateTime(2025, 5, 10), now: now), 'May 10, 2025');
    });

    // B27: across a DST switch a calendar day is 23 h or 25 h long, so
    // Duration.inDays between local midnights miscounts. Europe/Kyiv springs
    // forward on 2026-03-29 and falls back on 2026-10-25 (run the suite with
    // TZ=Europe/Kyiv to exercise these).
    test('B27: the day after spring-forward still reads yesterday as "Yesterday"', () {
      final after = DateTime(2026, 3, 30, 10);
      expect(formatRelativeDate(DateTime(2026, 3, 29, 20), now: after), 'Yesterday, Mar 29');
      expect(formatRelativeDate(DateTime(2026, 3, 30, 0, 5), now: after), 'Today, Mar 30');
      final before = DateTime(2026, 3, 28, 22);
      expect(formatRelativeDate(DateTime(2026, 3, 29, 8), now: before), 'Tomorrow, Mar 29');
    });

    test('B27: fall-back day boundaries', () {
      final after = DateTime(2026, 10, 26, 0, 30);
      expect(formatRelativeDate(DateTime(2026, 10, 25, 23), now: after), 'Yesterday, Oct 25');
      final before = DateTime(2026, 10, 24, 23, 30);
      expect(formatRelativeDate(DateTime(2026, 10, 25, 1), now: before), 'Tomorrow, Oct 25');
    });
  });
}
