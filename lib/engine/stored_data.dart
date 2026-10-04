import 'dart:convert';

/// Tolerant decoding of the JSON record lists the app persists and restores
/// (A7). One bad record costs only itself — never the rest of the collection
/// or the launch — and a source that can't be read at all is reported rather
/// than silently replaced, so the caller can set the raw text aside before
/// anything overwrites it.
class DecodedRecords<T> {
  /// Always a growable list — callers adopt it as live app state, so an
  /// empty result must not be a `const []` (the first add would throw).
  final List<T> items;

  /// Entries in the source that failed to parse or validate.
  final int skipped;

  /// The source wasn't a JSON list at all, so nothing could be read.
  final bool unreadable;

  const DecodedRecords(this.items, {this.skipped = 0, this.unreadable = false});

  /// Something in the source didn't make it into [items].
  bool get lossy => skipped > 0 || unreadable;
}

/// Decodes an already-parsed JSON value expected to be a list of objects,
/// one record at a time. [isValid] rejects records that parse but can't be
/// right (see record_validation.dart).
DecodedRecords<T> decodeRecords<T>(
  Object? source,
  T Function(Map<String, dynamic>) fromJson, {
  bool Function(T)? isValid,
}) {
  if (source is! List) return DecodedRecords<T>(<T>[], unreadable: true);
  final items = <T>[];
  var skipped = 0;
  for (final e in source) {
    try {
      if (e is Map<String, dynamic>) {
        final item = fromJson(e);
        if (isValid == null || isValid(item)) {
          items.add(item);
          continue;
        }
      }
    } catch (_) {
      // Wrong types / missing fields / unparseable dates: counted below.
    }
    skipped++;
  }
  return DecodedRecords<T>(items, skipped: skipped);
}

/// [decodeRecords] for a raw SharedPreferences string. `null` (never saved)
/// is an empty, lossless result.
DecodedRecords<T> decodeStoredList<T>(
  String? raw,
  T Function(Map<String, dynamic>) fromJson, {
  bool Function(T)? isValid,
}) {
  if (raw == null) return DecodedRecords<T>(<T>[]);
  final Object? parsed;
  try {
    parsed = jsonDecode(raw);
  } catch (_) {
    return DecodedRecords<T>(<T>[], unreadable: true);
  }
  return decodeRecords(parsed, fromJson, isValid: isValid);
}

/// Prefix of the keys that hold a stored collection's raw text after a lossy
/// load: `'<key>_unreadable_<millisSinceEpoch>'`. The app never reads these
/// back; they exist so a bad load can never destroy data, and full backups
/// carry them out for manual recovery.
String unreadableKeyPrefix(String key) => '${key}_unreadable_';

String unreadableKey(String key, DateTime at) =>
    '${unreadableKeyPrefix(key)}${at.millisecondsSinceEpoch}';
