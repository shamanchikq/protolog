import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/a11y_screens.dart';
import 'real_fonts.dart';

/// C2: every tappable control on the main screens is at least 48 × 48 dp
/// (Android's guideline) and has a spoken label, on a 360 dp phone with the
/// bundled fonts. Small controls reach 48 dp through TapTarget without
/// changing the layout.
void main() {
  setUpAll(loadAppFonts);

  for (final screen in a11yScreens) {
    testWidgets('${screen.name}: 48 dp, labeled tap targets', (tester) async {
      final handle = tester.ensureSemantics();
      // Tall enough that nothing scrolls out of view (an off-screen node
      // is skipped by the guideline).
      await pumpScreen(tester, screen, size: const Size(360, 2600));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  }
}
