import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/models.dart';
import 'package:protolog_tracker/ui/views/dashboard_view.dart';

void main() {
  const settings = GraphSettings(
    normalized: true,
    cumulative: false,
    showPeptides: true,
    timeRange: 'standard',
  );

  testWidgets('a range pill reports the current settings with the new range', (tester) async {
    final changes = <GraphSettings>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardView(
          injections: const [],
          bloodwork: const [],
          graphData: null,
          settings: settings,
          colorResolver: (_) => Colors.grey,
          now: DateTime(2026, 10, 3, 12),
          onSettingsChanged: changes.add,
          onAddBloodwork: () {},
          onOpenBloodwork: (_) {},
        ),
      ),
    ));

    await tester.tap(find.text('1y').first);
    await tester.pump();

    expect(changes, hasLength(1));
    expect(changes.single.timeRange, 'year');
    expect(changes.single.normalized, isTrue, reason: 'other settings carry over');
  });
}
