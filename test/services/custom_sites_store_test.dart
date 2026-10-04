import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/services/custom_sites_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const store = CustomSitesStore();

  test('keys are unchanged', () {
    expect(CustomSitesStore.imKey, 'customSitesIM');
    expect(CustomSitesStore.subQKey, 'customSitesSubQ');
  });

  test('nothing stored loads as empty lists', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await store.load();
    expect(s.im, isEmpty);
    expect(s.subQ, isEmpty);
  });

  test('loads the stored JSON lists', () async {
    SharedPreferences.setMockInitialValues({
      'customSitesIM': '["Lat L","Pec R"]',
      'customSitesSubQ': '["Love handle"]',
    });
    final s = await store.load();
    expect(s.im, ['Lat L', 'Pec R']);
    expect(s.subQ, ['Love handle']);
    expect(s.forRoute(subcutaneous: false), ['Lat L', 'Pec R']);
    expect(s.forRoute(subcutaneous: true), ['Love handle']);
  });

  test('a corrupt value loads as empty without affecting the other route', () async {
    SharedPreferences.setMockInitialValues({
      'customSitesIM': 'not json',
      'customSitesSubQ': '["Love handle"]',
    });
    final s = await store.load();
    expect(s.im, isEmpty);
    expect(s.subQ, ['Love handle']);
  });

  test('a value stored with the wrong preference type loads as empty', () async {
    SharedPreferences.setMockInitialValues({
      'customSitesIM': <String>['Lat L'], // a StringList, not a JSON string
      'customSitesSubQ': 42,
    });
    final s = await store.load();
    expect(s.im, isEmpty);
    expect(s.subQ, isEmpty);
  });

  test('decodeSiteList tolerates non-list JSON and non-string entries', () {
    expect(decodeSiteList(null), isEmpty);
    expect(decodeSiteList(''), isEmpty);
    expect(decodeSiteList('null'), isEmpty);
    expect(decodeSiteList('"Lat L"'), isEmpty);
    expect(decodeSiteList('{"a":1}'), isEmpty);
    expect(decodeSiteList('["Lat L", 3, null, "Pec R"]'), ['Lat L', 'Pec R']);
    expect(decodeSiteList('[]'), isEmpty);
  });

  test('save writes both routes as JSON string lists', () async {
    SharedPreferences.setMockInitialValues({});
    await store.save(const CustomSites(im: ['Lat L'], subQ: ['Love handle', 'Arm L']));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('customSitesIM'), '["Lat L"]');
    expect(prefs.getString('customSitesSubQ'), '["Love handle","Arm L"]');
    final back = await store.load();
    expect(back.im, ['Lat L']);
    expect(back.subQ, ['Love handle', 'Arm L']);
  });

  test('withSite appends to the route once', () {
    const s = CustomSites(im: ['Lat L'], subQ: ['Love handle']);
    final a = s.withSite('Pec R', subcutaneous: false);
    expect(a.im, ['Lat L', 'Pec R']);
    expect(a.subQ, ['Love handle']);
    final b = s.withSite('Arm L', subcutaneous: true);
    expect(b.im, ['Lat L']);
    expect(b.subQ, ['Love handle', 'Arm L']);
    expect(s.withSite('Lat L', subcutaneous: false), same(s));
  });

  test('withSite ignores case and surrounding spaces when checking for a duplicate', () {
    const s = CustomSites(im: ['Lat L']);
    expect(s.withSite('lat l', subcutaneous: false), same(s));
    expect(s.withSite(' LAT L ', subcutaneous: false), same(s));
  });

  test('withoutSite removes every case-insensitive match from that route only', () {
    const s = CustomSites(im: ['Lat L', 'Pec R', 'lat l'], subQ: ['Lat L']);
    final r = s.withoutSite('Lat L', subcutaneous: false);
    expect(r.im, ['Pec R']);
    expect(r.subQ, ['Lat L']);
    final q = s.withoutSite('lat l', subcutaneous: true);
    expect(q.im, ['Lat L', 'Pec R', 'lat l']);
    expect(q.subQ, isEmpty);
    expect(s.withoutSite('Nope', subcutaneous: false), same(s));
  });

  test('matchingSite finds an existing site ignoring case and surrounding spaces', () {
    const sites = ['Vent. glute L', 'Quad L', 'Lat L'];
    expect(matchingSite('quad l', sites), 'Quad L');
    expect(matchingSite('  QUAD L ', sites), 'Quad L');
    expect(matchingSite('Lat L', sites), 'Lat L');
    expect(matchingSite('Quad', sites), isNull);
    expect(matchingSite('', sites), isNull);
  });
}
