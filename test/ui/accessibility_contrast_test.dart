import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/ui/theme.dart';

import '../support/a11y_screens.dart';

/// C3: text on the main screens meets WCAG AA contrast (4.5:1, 3:1 for
/// large text), measured from the rendered pixels.
///
/// Deliberately with flutter_test's box font, not the bundled fonts: the
/// guideline takes the most frequent light and dark pixel colors around
/// each text, and thin anti-aliased 9–13 px glyphs rarely reach their full
/// color — real fonts report e.g. fgMute on surface (6.9:1) as ~2:1. Solid
/// boxes measure the true colors. (theme_test checks the token pairs
/// numerically; the tap-target test uses the real fonts for layout.)
void main() {
  testWidgets('the check catches dim text (fgDim fails, fgDimText passes)', (tester) async {
    final handle = tester.ensureSemantics();
    Widget sample(Color color) => MaterialApp(
          home: Scaffold(
            backgroundColor: AppTheme.surface2,
            body: Text('MICROLABEL', style: AppTheme.sans(size: 9.5, color: color)),
          ),
        );
    await tester.pumpWidget(sample(AppTheme.fgDim));
    expect((await textContrastGuideline.evaluate(tester)).passed, isFalse);
    await tester.pumpWidget(sample(AppTheme.fgDimText));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  for (final screen in a11yScreens) {
    testWidgets('${screen.name}: text contrast', (tester) async {
      final handle = tester.ensureSemantics();
      // Wide: the box font is wider than Inter, and layout isn't under test.
      await pumpScreen(tester, screen, size: const Size(800, 2600));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }
}
