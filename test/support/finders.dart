import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A display color no palette or library entry uses, for "the user's color
/// shows here" checks.
const userColor = Color(0xFF123456);

/// Containers drawn in [color]: their fill, their decoration's fill or any
/// side of their border (stripes, swatch dots, card top rules).
Finder coloredWith(Color color) => find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      if (w.color == color) return true;
      final d = w.decoration;
      if (d is! BoxDecoration) return false;
      if (d.color == color) return true;
      final b = d.border;
      return b is Border &&
          [b.top, b.left, b.right, b.bottom]
              .any((s) => s.style != BorderStyle.none && s.color == color);
    });
