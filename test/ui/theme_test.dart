import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protolog_tracker/ui/theme.dart';

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
}
