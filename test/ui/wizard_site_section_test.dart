import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/ui/views/wizard/site_section.dart';

void main() {
  group('sitesForRoute', () {
    test('built-ins first, then customs', () {
      expect(sitesForRoute(subcutaneous: false, custom: ['Lat L']),
          [...builtInSitesIM, 'Lat L']);
      expect(sitesForRoute(subcutaneous: true, custom: ['Love handle']),
          [...builtInSitesSubQ, 'Love handle']);
    });

    test('customs that repeat a built-in or an earlier custom (any case) are dropped', () {
      expect(
        sitesForRoute(subcutaneous: false, custom: ['Quad L', 'lat l', 'quad r ', 'Lat L', 'Pec R']),
        [...builtInSitesIM, 'lat l', 'Pec R'],
      );
    });
  });

  testWidgets('long-press removes only custom tiles', (tester) async {
    final removed = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SiteSection(
          sites: sitesForRoute(subcutaneous: false, custom: ['Lat L']),
          removableSites: const {'Lat L'},
          selected: 'Vent. glute R',
          lastSite: null,
          onSelect: (_) {},
          onAddSite: () {},
          onRemoveSite: removed.add,
        ),
      ),
    ));
    await tester.longPress(find.text('Quad L'));
    await tester.longPress(find.text('Lat L'));
    expect(removed, ['Lat L']);
  });
}
