import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

class LoadHeroData {
  final double totalActiveMg;
  final double delta;
  final List<LoadHeroRow> breakdown;
  const LoadHeroData({required this.totalActiveMg, required this.delta, required this.breakdown});
}

class LoadHeroRow {
  final String label;
  final double valueMg;
  final double shareOfTotal;
  final Color color;
  const LoadHeroRow({
    required this.label,
    required this.valueMg,
    required this.shareOfTotal,
    required this.color,
  });
}

class LoadHero extends StatelessWidget {
  final LoadHeroData data;
  const LoadHero({super.key, required this.data});

  // Scale derived from breakdown-row count: each extra row past the 2nd
  // bumps the paper-panel typography by 8%, capped at 1.7x. Matches the
  // visual goal of the big number growing as the card stretches.
  double _scaleFor(int rowCount) {
    final extra = math.max(0, rowCount - 2);
    return (1.0 + extra * 0.08).clamp(1.0, 1.7);
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scaleFor(data.breakdown.length);
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppTheme.border, width: 1)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 13,
              child: _PaperPanel(
                total: data.totalActiveMg,
                delta: data.delta,
                scale: scale,
              ),
            ),
            Expanded(flex: 10, child: _BreakdownPanel(rows: data.breakdown)),
          ],
        ),
      ),
    );
  }
}

class _PaperPanel extends StatelessWidget {
  final double total;
  final double delta;
  final double scale;
  const _PaperPanel({required this.total, required this.delta, required this.scale});

  @override
  Widget build(BuildContext context) {
    // Non-finite values (legacy bad data) render as "—" rather than throwing
    // in floor()/round() during build. total * 10 must be finite too.
    final showTotal = total.isFinite && (total * 10).isFinite;
    // Round once to tenths, then split, so 12.96 reads 13.0 (not 12.9).
    final totalTenths = showTotal ? (total * 10).round() : 0;
    final whole = totalTenths ~/ 10;
    final frac = totalTenths.remainder(10).abs();
    final showDelta = delta.isFinite && (delta * 10).isFinite;
    // Arrow and sign follow the displayed (rounded) delta, so a value in
    // (−0.05, 0) reads "→ +0.0" rather than "−0.0".
    final deltaTenths = showDelta ? (delta * 10).round() : 0;

    String arrow;
    Color arrowColor;
    if (deltaTenths > 0) {
      arrow = '↗';
      arrowColor = AppTheme.accentDeep;
    } else if (deltaTenths < 0) {
      arrow = '↘';
      arrowColor = AppTheme.warnOnPaper;
    } else {
      arrow = '→';
      arrowColor = AppTheme.paperInkMute;
    }
    final deltaStr = showDelta
        ? '${deltaTenths < 0 ? '−' : '+'}${(deltaTenths.abs() / 10).toStringAsFixed(1)}'
        : '—';

    // Padding grows a little with scale so the content breathes inside a taller card.
    final padV = 16.0 + (scale - 1.0) * 10.0;
    final padH = 18.0 + (scale - 1.0) * 6.0;

    // One spoken sentence instead of number fragments and an arrow glyph.
    final trend = !showDelta
        ? 'unknown'
        : deltaTenths > 0
            ? 'up ${deltaStr.substring(1)} mg'
            : deltaTenths < 0
                ? 'down ${deltaStr.substring(1)} mg'
                : 'flat';
    final label = showTotal
        ? 'Total load $whole.$frac mg. Injectables 7 day trend: $trend.'
        : 'Total load unavailable.';

    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: _paper(
          padH: padH, padV: padV, showTotal: showTotal, whole: whole, frac: frac,
          arrow: arrow, arrowColor: arrowColor, deltaStr: deltaStr,
        ),
      ),
    );
  }

  Widget _paper({
    required double padH,
    required double padV,
    required bool showTotal,
    required int whole,
    required int frac,
    required String arrow,
    required Color arrowColor,
    required String deltaStr,
  }) {
    return Stack(
      children: [
        Container(color: AppTheme.paper),
        Positioned.fill(child: CustomPaint(painter: _PaperGridPainter())),
        Padding(
          padding: EdgeInsets.fromLTRB(padH, padV, padH, padV),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total load',
                style: AppTheme.sans(
                  size: 11 * scale,
                  color: AppTheme.paperInkMute,
                ),
              ),
              SizedBox(height: 6 * scale),
              // Scales down (never up) when a 4-digit total, a tall card's
              // typography scale or large system text would overflow (C1).
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      showTotal ? '$whole' : '—',
                      style: AppTheme.serif(
                        size: 48 * scale,
                        weight: FontWeight.w500,
                        color: AppTheme.paperInk,
                        letterSpacing: -1.5,
                        height: 1,
                      ),
                    ),
                    if (showTotal)
                      Text(
                        '.$frac',
                        style: AppTheme.serif(
                          size: 28 * scale,
                          weight: FontWeight.w400,
                          color: AppTheme.paperInk.withValues(alpha: 0.5),
                          height: 1,
                        ),
                      ),
                    SizedBox(width: 4 * scale),
                    Text(
                      'mg',
                      style: AppTheme.sans(
                        size: 12 * scale,
                        color: AppTheme.paperInkMute,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12 * scale),
              // Wraps onto a second line rather than overflowing.
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Injectables 7d · ',
                      style: AppTheme.sans(size: 11 * scale, color: AppTheme.paperInk.withValues(alpha: 0.7))),
                  Text(arrow,
                      style: AppTheme.sans(size: 11 * scale, color: arrowColor, weight: FontWeight.w600)),
                  Text(' $deltaStr',
                      style: AppTheme.sans(size: 11 * scale, color: AppTheme.paperInk.withValues(alpha: 0.85))),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaperGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.paperInk.withValues(alpha: 0.05)
      ..strokeWidth = 0.3;
    final stepX = size.width / 20;
    final stepY = size.height / 20;
    for (int i = 0; i <= 20; i++) {
      canvas.drawLine(Offset(0, i * stepY), Offset(size.width, i * stepY), paint);
      canvas.drawLine(Offset(i * stepX, 0), Offset(i * stepX, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BreakdownPanel extends StatelessWidget {
  final List<LoadHeroRow> rows;
  const _BreakdownPanel({required this.rows});

  // Per-row gap shrinks once the list gets long so the panel fits inside the
  // card without overflowing — 12px default, 8px from 5 rows on, 6px from 7+.
  double _gapFor(int n) {
    if (n >= 7) return 6.0;
    if (n >= 5) return 8.0;
    return 12.0;
  }

  double _padVFor(int n) => n >= 6 ? 12.0 : 16.0;

  @override
  Widget build(BuildContext context) {
    final gap = _gapFor(rows.length);
    final padV = _padVFor(rows.length);
    return Container(
      color: AppTheme.surface,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: padV),
      // Scrollable so a long list never overflows its allocated height.
      // ClampingScrollPhysics prevents bounce in the tiny side panel.
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: rows.isEmpty
              ? [Text('No active compounds', style: AppTheme.sans(size: 11, color: AppTheme.fgMute))]
              : [
                  for (int i = 0; i < rows.length; i++) ...[
                    if (i > 0) SizedBox(height: gap),
                    // "Testosterone 167" as one node.
                    MergeSemantics(child: _BreakdownRow(row: rows[i])),
                  ],
                ],
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final LoadHeroRow row;
  const _BreakdownRow({required this.row});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                row.label,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.sans(size: 11),
              ),
            ),
            Text(row.valueMg.isFinite ? row.valueMg.toStringAsFixed(0) : '—',
                style: AppTheme.mono(size: 11)),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 2,
          child: Stack(
            children: [
              Container(color: AppTheme.surface2),
              FractionallySizedBox(
                // NaN.clamp() yields 1.0 — a non-finite share draws no bar.
                widthFactor: row.shareOfTotal.isFinite ? row.shareOfTotal.clamp(0.0, 1.0) : 0.0,
                child: Container(color: row.color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
