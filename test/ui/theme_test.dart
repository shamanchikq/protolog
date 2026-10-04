import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/ui/theme.dart';

/// WCAG 2.x contrast ratio of two opaque colors.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [c] at [alpha] composited over [over].
Color _over(Color c, double alpha, Color over) =>
    Color.alphaBlend(c.withValues(alpha: alpha), over);

void main() {
  group('AppTheme.compoundColor', () {
    test('exact base names, case-insensitive and trimmed', () {
      expect(AppTheme.compoundColor('Testosterone'), const Color(0xFF5DC59C));
      expect(AppTheme.compoundColor('  primobolan '), const Color(0xFF5FA8E0));
    });
    test('falls back to the first word', () {
      expect(AppTheme.compoundColor('Sustanon 250'), const Color(0xFF5DC59C));
      expect(AppTheme.compoundColor('Trenbolone\tMix'), const Color(0xFFD27A6B));
    });
    test('unknown names give null', () {
      expect(AppTheme.compoundColor('Unobtainium'), isNull);
      expect(AppTheme.compoundColor(''), isNull);
    });
  });

  // C3: WCAG AA is 4.5:1 for normal text, 3:1 for large text (≥ 18 px, or
  // ≥ 14 px bold) and for non-text glyphs.
  group('text contrast (WCAG AA)', () {
    const darkSurfaces = {
      'bg': AppTheme.bg,
      'surface': AppTheme.surface,
      'surface2': AppTheme.surface2,
    };

    for (final MapEntry(key: name, value: surface) in darkSurfaces.entries) {
      test('text colors on $name reach 4.5:1', () {
        for (final (label, color) in [
          ('fg', AppTheme.fg),
          ('fgMute', AppTheme.fgMute),
          ('fgDimText', AppTheme.fgDimText),
          ('accent', AppTheme.accent),
          ('warm', AppTheme.warm),
          ('warn', AppTheme.warn),
        ]) {
          expect(_contrast(color, surface), greaterThanOrEqualTo(4.5),
              reason: '$label on $name');
        }
      });
    }

    test('fgDim stays decorative: it is below text contrast', () {
      // Documents why fgDimText exists; fgDim is for borders and glyphs.
      expect(_contrast(AppTheme.fgDim, AppTheme.surface2), lessThan(4.5));
    });

    test('fgDimText measured ratios', () {
      expect(_contrast(AppTheme.fgDimText, AppTheme.surface2), closeTo(4.65, 0.01));
      expect(_contrast(AppTheme.fgDimText, AppTheme.surface), closeTo(4.98, 0.01));
      expect(_contrast(AppTheme.fgDimText, AppTheme.bg), closeTo(5.33, 0.01));
    });

    test('inverted controls: dark text on accent and on fg', () {
      expect(_contrast(AppTheme.bg, AppTheme.accent), greaterThanOrEqualTo(4.5));
      expect(_contrast(AppTheme.bg, AppTheme.fg), greaterThanOrEqualTo(4.5));
    });

    test('swipe-to-delete label: dark ink on warn (paper would be 2.5:1)', () {
      expect(_contrast(AppTheme.paperInk, AppTheme.warn), greaterThanOrEqualTo(4.5));
      expect(_contrast(AppTheme.paper, AppTheme.warn), lessThan(4.5));
    });

    test('LoadHero paper panel', () {
      const paper = AppTheme.paper;
      // "Total load", "mg", the flat-trend arrow.
      expect(_contrast(AppTheme.paperInkMute, paper), greaterThanOrEqualTo(4.5));
      // Falling-trend arrow (was warn: 2.56:1).
      expect(_contrast(AppTheme.warnOnPaper, paper), greaterThanOrEqualTo(4.5));
      // Rising-trend arrow.
      expect(_contrast(AppTheme.accentDeep, paper), greaterThanOrEqualTo(4.5));
      // "Injectables 7d ·" and the delta value.
      expect(_contrast(_over(AppTheme.paperInk, 0.7, paper), paper), greaterThanOrEqualTo(4.5));
      expect(_contrast(_over(AppTheme.paperInk, 0.85, paper), paper), greaterThanOrEqualTo(4.5));
      // The total's ".3" decimals are large (28 px serif): 3:1.
      expect(_contrast(_over(AppTheme.paperInk, 0.5, paper), paper), greaterThanOrEqualTo(3.0));
      expect(_contrast(AppTheme.paperInk, paper), greaterThanOrEqualTo(4.5));
    });

    test('paper tokens keep the paper look (same hue family)', () {
      // paperInkMute is paperInk at ~65 % over paper.
      final blended = _over(AppTheme.paperInk, 0.65, AppTheme.paper);
      expect((blended.r - AppTheme.paperInkMute.r).abs(), lessThan(2 / 255));
      expect((blended.g - AppTheme.paperInkMute.g).abs(), lessThan(2 / 255));
      expect((blended.b - AppTheme.paperInkMute.b).abs(), lessThan(2 / 255));
      final warn = HSLColor.fromColor(AppTheme.warn);
      final dark = HSLColor.fromColor(AppTheme.warnOnPaper);
      expect((warn.hue - dark.hue).abs(), lessThan(1));
      expect((warn.saturation - dark.saturation).abs(), lessThan(0.02));
    });
  });
}
