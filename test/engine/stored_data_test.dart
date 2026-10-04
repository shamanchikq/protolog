import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/engine/record_validation.dart';
import 'package:protolog_tracker/engine/stored_data.dart';

final _good = Reminder(
  id: 'ok', compoundBase: 'Testosterone', compoundEster: 'Cypionate',
  intervalDays: 3.5, hour: 8, minute: 0, enabled: true,
  anchorDate: DateTime(2026, 5, 18, 8, 0), notificationSeed: 7,
);

Map<String, dynamic> _json(Reminder r) => jsonDecode(jsonEncode(r.toJson()));

void main() {
  group('decodeStoredList', () {
    test('never-saved key is an empty, lossless result', () {
      final res = decodeStoredList(null, Reminder.fromJson);
      expect(res.items, isEmpty);
      expect(res.lossy, isFalse);
    });

    test('empty list is fine', () {
      final res = decodeStoredList('[]', Reminder.fromJson);
      expect(res.items, isEmpty);
      expect(res.lossy, isFalse);
    });

    test('a clean list round-trips', () {
      final res = decodeStoredList(jsonEncode([_good.toJson()]), Reminder.fromJson);
      expect(res.items.single.id, 'ok');
      expect(res.lossy, isFalse);
    });

    test('garbage text is unreadable, not an exception', () {
      final res = decodeStoredList('{{ not json', Reminder.fromJson);
      expect(res.unreadable, isTrue);
      expect(res.items, isEmpty);
      expect(res.lossy, isTrue);
    });

    test('valid JSON that is not a list is unreadable', () {
      for (final raw in ['{"id": "x"}', '42', '"text"', 'null']) {
        expect(decodeStoredList(raw, Reminder.fromJson).unreadable, isTrue, reason: raw);
      }
    });

    test('a partly bad list keeps every good record and counts the rest', () {
      final raw = jsonEncode([
        _good.toJson(),
        'not an object',
        42,
        null,
        {'id': 'missing-everything'},
        _json(_good)..['intervalDays'] = 'three', // wrong type
        _json(_good)..['anchorDate'] = 'not a date',
        _json(_good)..['id'] = 'ok2',
      ]);
      final res = decodeStoredList(raw, Reminder.fromJson);
      expect(res.items.map((r) => r.id), ['ok', 'ok2']);
      expect(res.skipped, 6);
      expect(res.unreadable, isFalse);
      expect(res.lossy, isTrue);
    });

    test('records that parse but fail validation are skipped too', () {
      final raw = jsonEncode([
        _good.toJson(),
        // weekday 0 used to spin the launch-time slot loop forever
        _json(_good)
          ..['id'] = 'bad-slot'
          ..['scheduleMode'] = 'custom'
          ..['customSlots'] = [{'weekday': 0, 'hour': 8, 'minute': 0}],
        _json(_good)..['id'] = 'zero-interval'..['intervalDays'] = 0,
      ]);
      final res = decodeStoredList(raw, Reminder.fromJson, isValid: isValidReminder);
      expect(res.items.map((r) => r.id), ['ok']);
      expect(res.skipped, 2);
    });

    test('non-finite numbers in stored text are rejected', () {
      // 1e999 decodes to Infinity, which every later jsonEncode refuses.
      final raw = jsonEncode([_good.toJson()]).replaceFirst('3.5', '1e999');
      final res = decodeStoredList(raw, Reminder.fromJson, isValid: isValidReminder);
      expect(res.items, isEmpty);
      expect(res.skipped, 1);
    });
  });

  group('results are growable (adopted as live app state)', () {
    // A fresh install's never-saved collections used to come back as
    // `const []`, so the first logged dose / reminder / lab result threw
    // inside setState and was silently lost.
    for (final (label, raw) in [
      ('never saved', null),
      ('empty list', '[]'),
      ('garbage', 'not json {'),
      ('not a list', '{"a": 1}'),
    ]) {
      test(label, () {
        final res = decodeStoredList(raw, Reminder.fromJson);
        expect(() => res.items.add(_good), returnsNormally);
        expect(res.items, [_good]);
      });
    }

    test('decodeRecords on a non-list', () {
      final res = decodeRecords(42, Reminder.fromJson);
      expect(() => res.items.add(_good), returnsNormally);
    });
  });

  group('unreadable keys', () {
    test('format is <key>_unreadable_<millis>', () {
      final at = DateTime.fromMillisecondsSinceEpoch(1759500000000);
      expect(unreadableKey('reminders', at), 'reminders_unreadable_1759500000000');
      expect(unreadableKey('reminders', at), startsWith(unreadableKeyPrefix('reminders')));
    });
  });
}
