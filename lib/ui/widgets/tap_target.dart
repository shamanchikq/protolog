import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Minimum touch-target edge (Android's 48 dp guideline).
const double kMinTapTarget = kMinInteractiveDimension;

/// Lets small Lab Sheet controls be touched — and found by a screen reader —
/// over at least 48 × 48 dp without taking that much room in the layout,
/// like Android's TouchDelegate.
///
/// A [TapTarget] lays out and paints exactly like its child. Inside a
/// [TapTargetScope], a touch that lands in the target's 48 × 48 dp area
/// (centred on the child) but outside the child is moved onto the child's
/// nearest edge, so it reaches the child's gesture detector (and every
/// ancestor, scrollables included) as a normal hit. The target's semantics
/// node reports that same area.
///
/// When a touch is near several targets, the closest one gets it. A touch on
/// another target's own box keeps going there, unless that target encloses
/// the near one — so a near-miss on an icon button inside a tappable row
/// opens the icon's action, not the row's.
///
/// Screen readers walk nodes in reading order by their rectangles, so the
/// grown area would put a pill ahead of the title it sits beside; an outer
/// container node with the drawn box keeps the target in its visual place.
///
/// Without a scope the target is inert: same hit area, same semantics as
/// the child.
class TapTarget extends StatelessWidget {
  const TapTarget({
    super.key,
    this.minSize = kMinTapTarget,
    this.mergeSemantics = true,
    required this.child,
  });

  /// The smallest width and height the touch area grows to.
  final double minSize;

  /// Whether the child's semantics merge into one node (a pill, a button),
  /// or stay separate below it (a row holding its own buttons).
  final bool mergeSemantics;

  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        explicitChildNodes: true,
        child: TapTargetBox(minSize: minSize, mergeSemantics: mergeSemantics, child: child),
      );
}

/// The render widget under [TapTarget]: the grown hit area and the node that
/// reports it. Use [TapTarget].
class TapTargetBox extends SingleChildRenderObjectWidget {
  const TapTargetBox({
    super.key,
    this.minSize = kMinTapTarget,
    this.mergeSemantics = true,
    required Widget super.child,
  });

  final double minSize;
  final bool mergeSemantics;

  @override
  RenderTapTarget createRenderObject(BuildContext context) =>
      RenderTapTarget(minSize: minSize, mergeSemantics: mergeSemantics);

  @override
  void updateRenderObject(BuildContext context, RenderTapTarget renderObject) {
    renderObject
      ..minSize = minSize
      ..mergeSemantics = mergeSemantics;
  }
}

/// The region in which [TapTarget]s accept near-miss touches. Place one at
/// the root of each page, dialog and sheet; it must cover the grown areas.
class TapTargetScope extends SingleChildRenderObjectWidget {
  const TapTargetScope({super.key, required Widget super.child});

  @override
  RenderTapTargetScope createRenderObject(BuildContext context) => RenderTapTargetScope();
}

class RenderTapTarget extends RenderProxyBox {
  RenderTapTarget({required double minSize, required bool mergeSemantics})
      : _minSize = minSize,
        _mergeSemantics = mergeSemantics;

  double get minSize => _minSize;
  double _minSize;
  set minSize(double value) {
    if (value == _minSize) return;
    _minSize = value;
    markNeedsSemanticsUpdate();
  }

  bool get mergeSemantics => _mergeSemantics;
  bool _mergeSemantics;
  set mergeSemantics(bool value) {
    if (value == _mergeSemantics) return;
    _mergeSemantics = value;
    markNeedsSemanticsUpdate();
  }

  RenderTapTargetScope? _scope;

  /// The touch area in local coordinates: the box grown to [minSize] in
  /// each direction it falls short, around its centre.
  Rect get touchRect {
    final s = size;
    return Rect.fromCenter(
      center: s.center(Offset.zero),
      width: math.max(s.width, _minSize),
      height: math.max(s.height, _minSize),
    );
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    for (var p = parent; p != null; p = p.parent) {
      if (p is RenderTapTargetScope) {
        _scope = p.._targets.add(this);
        break;
      }
    }
  }

  @override
  void detach() {
    _scope?._targets.remove(this);
    _scope = null;
    super.detach();
  }

  @override
  Rect get semanticBounds => _scope != null ? touchRect : super.semanticBounds;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
    config.isMergingSemanticsOfDescendants = _mergeSemantics;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('minSize', _minSize));
    properties.add(FlagProperty('scoped', value: _scope != null, ifTrue: 'scoped'));
  }
}

class RenderTapTargetScope extends RenderProxyBox {
  final Set<RenderTapTarget> _targets = {};

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_targets.isNotEmpty && size.contains(position)) {
      final moved = _nearMiss(position);
      if (moved != null) return super.hitTest(result, position: moved);
    }
    return super.hitTest(result, position: position);
  }

  /// Where a touch at [position] should land instead: a point just inside
  /// the closest target whose touch area (but not box) contains it, or null
  /// to hit-test normally.
  Offset? _nearMiss(Offset position) {
    RenderTapTarget? best;
    Offset? bestPoint;
    var bestDistance = double.infinity;
    final onTargets = <RenderTapTarget>[];
    for (final t in _targets) {
      if (!t.attached || !t.hasSize) continue;
      final toScope = t.getTransformTo(this);
      final fromScope = Matrix4.tryInvert(toScope);
      if (fromScope == null) continue;
      final local = MatrixUtils.transformPoint(fromScope, position);
      final box = Offset.zero & t.size;
      if (box.contains(local)) {
        onTargets.add(t);
        continue;
      }
      if (!t.touchRect.contains(local)) continue;
      final insetX = math.min(1.0, box.width / 2);
      final insetY = math.min(1.0, box.height / 2);
      final inside = Offset(
        local.dx.clamp(box.left + insetX, box.right - insetX),
        local.dy.clamp(box.top + insetY, box.bottom - insetY),
      );
      final distance = (inside - local).distance;
      if (distance < bestDistance) {
        best = t;
        bestDistance = distance;
        bestPoint = MatrixUtils.transformPoint(toScope, inside);
      }
    }
    if (best == null) return null;
    // The touch is on another control's own box: it stays there, unless
    // that control contains the near one (a row around its icon button).
    for (final t in onTargets) {
      if (!_contains(t, best)) return null;
    }
    // Only when the moved touch really reaches the target — not one clipped
    // away, scrolled out of view or covered by something else.
    final probe = BoxHitTestResult();
    super.hitTest(probe, position: bestPoint!);
    for (final entry in probe.path) {
      if (identical(entry.target, best)) return bestPoint;
    }
    return null;
  }

  static bool _contains(RenderObject outer, RenderObject inner) {
    for (RenderObject? p = inner.parent; p != null; p = p.parent) {
      if (identical(p, outer)) return true;
    }
    return false;
  }
}
