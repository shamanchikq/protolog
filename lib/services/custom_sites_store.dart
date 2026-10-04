import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Injection sites the user added in the log wizard, per route.
class CustomSites {
  const CustomSites({this.im = const [], this.subQ = const []});

  /// Intramuscular sites (steroids).
  final List<String> im;

  /// Subcutaneous sites (peptides, incl. HCG).
  final List<String> subQ;

  List<String> forRoute({required bool subcutaneous}) => subcutaneous ? subQ : im;

  /// These sites with [site] appended to its route's list, unless that list
  /// already holds it (ignoring case and surrounding spaces, see
  /// [matchingSite]).
  CustomSites withSite(String site, {required bool subcutaneous}) {
    final current = forRoute(subcutaneous: subcutaneous);
    if (matchingSite(site, current) != null) return this;
    return _withRoute([...current, site], subcutaneous: subcutaneous);
  }

  /// These sites without [site] — every entry of its route's list that
  /// matches it ignoring case and surrounding spaces. The same instance when
  /// nothing matches.
  CustomSites withoutSite(String site, {required bool subcutaneous}) {
    final current = forRoute(subcutaneous: subcutaneous);
    final key = _siteKey(site);
    final next = [for (final s in current) if (_siteKey(s) != key) s];
    if (next.length == current.length) return this;
    return _withRoute(next, subcutaneous: subcutaneous);
  }

  CustomSites _withRoute(List<String> sites, {required bool subcutaneous}) =>
      subcutaneous ? CustomSites(im: im, subQ: sites) : CustomSites(im: sites, subQ: subQ);
}

/// The entry of [sites] that names the same site as [name] — equal ignoring
/// case and surrounding spaces ("quad l" → "Quad L") — or null. A blank
/// [name] matches nothing.
String? matchingSite(String name, Iterable<String> sites) {
  final key = _siteKey(name);
  if (key.isEmpty) return null;
  for (final s in sites) {
    if (_siteKey(s) == key) return s;
  }
  return null;
}

String _siteKey(String site) => site.trim().toLowerCase();

/// SharedPreferences persistence for [CustomSites]: one JSON string list per
/// route under [imKey] / [subQKey].
class CustomSitesStore {
  const CustomSitesStore({Future<SharedPreferences> Function() prefs = SharedPreferences.getInstance})
      : _prefs = prefs;

  /// Test seam: the preferences instance (the app's by default).
  final Future<SharedPreferences> Function() _prefs;

  static const imKey = 'customSitesIM';
  static const subQKey = 'customSitesSubQ';

  /// Stored sites. A missing or unreadable value loads as an empty list.
  Future<CustomSites> load() async {
    final prefs = await _prefs();
    return CustomSites(
      im: decodeSiteList(prefs.get(imKey)),
      subQ: decodeSiteList(prefs.get(subQKey)),
    );
  }

  /// Writes both routes' lists. False if either write was refused or
  /// threw — callers report it like any failed save.
  Future<bool> save(CustomSites sites) async {
    try {
      final prefs = await _prefs();
      final im = await prefs.setString(imKey, jsonEncode(sites.im));
      final subQ = await prefs.setString(subQKey, jsonEncode(sites.subQ));
      return im && subQ;
    } catch (_) {
      return false;
    }
  }
}

/// Decodes one stored site list. Tolerates bad data: anything but a JSON
/// list of strings yields its string entries, or none.
List<String> decodeSiteList(Object? raw) {
  if (raw is! String) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return List<String>.unmodifiable(decoded.whereType<String>());
  } on FormatException {
    return const [];
  }
}
