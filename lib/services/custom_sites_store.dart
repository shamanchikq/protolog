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
  /// already holds it.
  CustomSites withSite(String site, {required bool subcutaneous}) {
    final current = forRoute(subcutaneous: subcutaneous);
    if (current.contains(site)) return this;
    final next = [...current, site];
    return subcutaneous ? CustomSites(im: im, subQ: next) : CustomSites(im: next, subQ: subQ);
  }
}

/// SharedPreferences persistence for [CustomSites]: one JSON string list per
/// route under [imKey] / [subQKey].
class CustomSitesStore {
  const CustomSitesStore();

  static const imKey = 'customSitesIM';
  static const subQKey = 'customSitesSubQ';

  /// Stored sites. A missing or unreadable value loads as an empty list.
  Future<CustomSites> load() async {
    final prefs = await SharedPreferences.getInstance();
    return CustomSites(
      im: decodeSiteList(prefs.get(imKey)),
      subQ: decodeSiteList(prefs.get(subQKey)),
    );
  }

  /// Writes both routes' lists.
  Future<void> save(CustomSites sites) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(imKey, jsonEncode(sites.im));
    await prefs.setString(subQKey, jsonEncode(sites.subQ));
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
