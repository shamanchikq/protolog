import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/ui/widgets/load_hero.dart';

void main() {
  testWidgets('trend caption names the injectables-only basis', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: LoadHero(
          data: LoadHeroData(totalActiveMg: 0, delta: 0, breakdown: []),
        ),
      ),
    ));
    expect(find.textContaining('Injectables 7d'), findsOneWidget);
    expect(find.textContaining('Last 7 days'), findsNothing);
  });
}
