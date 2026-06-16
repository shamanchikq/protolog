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
    final whole = total.floor();
    final frac = ((total - whole) * 10).round().clamp(0, 9);

    String arrow;
    Color arrowColor;
    if (delta >= 0.05) {
      arrow = '↗';
      arrowColor = AppTheme.accentDeep;
    } else if (delta <= -0.05) {
      arrow = '↘';
      arrowColor = AppTheme.warn;
    } else {
      arrow = '→';
      arrowColor = AppTheme.paperInk.withValues(alpha: 0.55);
    }
    final deltaStr = '${delta >= 0 ? '+' : '−'}${delta.abs().toStringAsFixed(1)}';

    // Padding grows a little with scale so the content breathes inside a taller card.
    final padV = 16.0 + (scale - 1.0) * 10.0;
    final padH = 18.0 + (scale - 1.0) * 6.0;

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
                  color: AppTheme.paperInk.withValues(alpha: 0.6),
                ),
              ),
              SizedBox(height: 6 * scale),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$whole',
                    style: AppTheme.serif(
                      size: 48 * scale,
                      weight: FontWeight.w500,
                      color: AppTheme.paperInk,
                      letterSpacing: -1.5,
                      height: 1,
                    ),
                  ),
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
                      color: AppTheme.paperInk.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12 * scale),
              Row(
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
                    _BreakdownRow(row: rows[i]),
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
            Text(row.valueMg.toStringAsFixed(0), style: AppTheme.mono(size: 11)),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 2,
          child: Stack(
            children: [
              Container(color: AppTheme.surface2),
              FractionallySizedBox(
                widthFactor: row.shareOfTotal.clamp(0.0, 1.0),
                child: Container(color: row.color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
