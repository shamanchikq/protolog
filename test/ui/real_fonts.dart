import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the app's bundled TTFs (assets/fonts, as declared in pubspec.yaml)
/// so layout tests measure real glyph widths. flutter_test's default font
/// renders every glyph as a 1 em square, which over- or under-reports
/// overflow. Call from `setUpAll` (outside the fake-async zone).
Future<void> loadAppFonts() async {
  const families = {
    'Inter': 'Inter',
    'Fraunces': 'Fraunces',
    'JetBrainsMono': 'JetBrainsMono',
  };
  const weights = [300, 400, 500, 600, 700];
  for (final MapEntry(key: family, value: filePrefix) in families.entries) {
    final loader = FontLoader(family);
    for (final w in weights) {
      final bytes = File('assets/fonts/$filePrefix-$w.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
    }
    await loader.load();
  }
}
