import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/ui/widgets/protolog_shell.dart';

void main() {
  testWidgets('shell renders brand, tabs, body, and FAB; reports tab taps',
      (tester) async {
    ShellTab? tapped;
    var fabPressed = false;

    await tester.pumpWidget(MaterialApp(
      home: ProtoLogShell(
        activeTab: ShellTab.today,
        onTabChanged: (t) => tapped = t,
        onFabPressed: () => fabPressed = true,
        fabLabel: 'Log dose',
        body: const Text('dashboard body'),
      ),
    ));

    expect(find.text('protolog'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Reminders'), findsOneWidget);
    expect(find.text('dashboard body'), findsOneWidget);
    expect(find.text('Log dose'), findsOneWidget);

    await tester.tap(find.text('Library'));
    expect(tapped, ShellTab.library);

    await tester.tap(find.text('Log dose'));
    expect(fabPressed, isTrue);
  });
}
