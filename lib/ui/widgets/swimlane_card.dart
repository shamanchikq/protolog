import 'package:flutter/material.dart';
import '../../models.dart';
import '../../engine/dashboard_stats.dart';
import '../theme.dart';

class SwimlaneCardLane {
  final CompoundDefinition compound;
  final List<Injection> injections;
  const SwimlaneCardLane({required this.compound, required this.injections});

  bool get isWindow =>
      compound.halfLife > 0.5 &&
      compound.timeToPeak > 0 &&
      (compound.graphType == GraphType.activeWindow || compound.type == CompoundType.ancillary);
}

/// Range key + (daysBack, daysFwd). Today cursor sits at daysBack/(daysBack+daysFwd).
const _ranges = <String, (int, int, String)>{
  'zoom': (5, 2, '7d'),
  'standard': (21, 7, '28d'),
  'cycle': (67, 23, '90d'),
  'year': (273, 92, '1y'),
};

class SwimlaneCard extends StatefulWidget {
  final List<Injection> injections;
  final DateTime now;

  const SwimlaneCard({super.key, required this.injections, required this.now});

  @override
  State<SwimlaneCard> createState() => _SwimlaneCardState();
}

class _SwimlaneCardState extends State<SwimlaneCard> {
  String _range = 'standard';

  @override
  Widget build(BuildContext context) {
    final (daysBack, daysFwd, _) = _ranges[_range]!;
    final totalDays = daysBack + daysFwd;
    final windowStart = DateTime(widget.now.year, widget.now.month, widget.now.day)
        .subtract(Duration(days: daysBack));
    final windowEnd = windowStart.add(Duration(days: totalDays));

    final relevant = widget.injections
        .where((i) => i.snapshot.type == CompoundType.peptide || i.snapshot.type == CompoundType.ancillary)
        .where((i) {
          final earliestRelevant = windowStart.subtract(Duration(days: (i.snapshot.halfLife * 8).round()));
          return i.date.isAfter(earliestRelevant) && i.date.isBefore(windowEnd);
        })
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final Map<String, SwimlaneCardLane> laneMap = {};
    for (final inj in relevant) {
      final key = '${inj.snapshot.base}::${inj.snapshot.ester}';
      final existing = laneMap[key];
      if (existing == null) {
        laneMap[key] = SwimlaneCardLane(compound: inj.snapshot, injections: [inj]);
      } else {
        existing.injections.add(inj);
      }
    }
    final lanes = laneMap.values.toList();
    final peptides = lanes.where((l) => l.compound.type == CompoundType.peptide).toList();
    final ancillaries = lanes.where((l) => l.compound.type == CompoundType.ancillary).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            range: _range,
            onRangeChanged: (r) => setState(() => _range = r),
            daysBack: daysBack,
            daysFwd: daysFwd,
          ),
          _AxisRow(daysBack: daysBack, daysFwd: daysFwd),
          if (peptides.isNotEmpty)
            _Group(
              label: 'Peptides',
              lanes: peptides,
              windowStart: windowStart,
              windowEnd: windowEnd,
              totalDays: totalDays,
              now: widget.now,
              showTopDivider: false,
            ),
          if (ancillaries.isNotEmpty)
            _Group(
              label: 'Ancillaries',
              lanes: ancillaries,
              windowStart: windowStart,
              windowEnd: windowEnd,
              totalDays: totalDays,
              now: widget.now,
              showTopDivider: peptides.isNotEmpty,
            ),
          if (peptides.isEmpty && ancillaries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              child: Text(
                'No peptide or ancillary activity in this window',
                style: AppTheme.sans(size: 11, color: AppTheme.fgMute),
              ),
            ),
          const _Legend(),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String range;
  final ValueChanged<String> onRangeChanged;
  final int daysBack;
  final int daysFwd;
  const _Header({
    required this.range,
    required this.onRangeChanged,
    required this.daysBack,
    required this.daysFwd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.borderSoft, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('Peptides & ancillaries', style: AppTheme.sans(size: 13, weight: FontWeight.w600)),
              _RangePills(active: range, onChange: onRangeChanged),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${daysBack}d back · ${daysFwd}d ahead',
            style: AppTheme.mono(size: 10, color: AppTheme.fgMute, letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }
}

class _RangePills extends StatelessWidget {
  final String active;
  final ValueChanged<String> onChange;
  const _RangePills({required this.active, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in _ranges.entries) ...[
          GestureDetector(
            onTap: () => onChange(entry.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: active == entry.key ? AppTheme.surface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.value.$3,
                style: AppTheme.sans(
                  size: 11,
                  color: active == entry.key ? AppTheme.fg : AppTheme.fgMute,
                  weight: active == entry.key ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
        ],
      ],
    );
  }
}

class _AxisRow extends StatelessWidget {
  final int daysBack;
  final int daysFwd;
  const _AxisRow({required this.daysBack, required this.daysFwd});

  List<({double posPct, String label, bool now})> _computeTicks() {
    final total = daysBack + daysFwd;
    final todayFrac = daysBack / total;
    final pastMid = todayFrac / 2;
    // Skip the future-mid tick — the future window is short and the end-tick
    // is close enough that two labels would overlap on long ranges.
    return [
      (posPct: 0.0, label: '−${daysBack}d', now: false),
      (posPct: pastMid, label: '−${(daysBack / 2).round()}d', now: false),
      (posPct: todayFrac, label: 'NOW', now: true),
      (posPct: 1.0, label: '+${daysFwd}d', now: false),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ticks = _computeTicks();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.borderSoft, width: 1)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 94),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 12,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final tk in ticks)
                        Positioned(
                          left: (constraints.maxWidth * tk.posPct).clamp(0.0, constraints.maxWidth),
                          top: 0,
                          child: FractionalTranslation(
                            translation: Offset(
                              tk.posPct == 0
                                  ? 0
                                  : tk.posPct == 1
                                      ? -1
                                      : -0.5,
                              0,
                            ),
                            child: Text(
                              tk.label,
                              style: AppTheme.mono(
                                size: 8.5,
                                color: tk.now ? AppTheme.accent : AppTheme.fgMute,
                                weight: tk.now ? FontWeight.w600 : FontWeight.w400,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          const SizedBox(width: 42),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String label;
  final List<SwimlaneCardLane> lanes;
  final DateTime windowStart;
  final DateTime windowEnd;
  final int totalDays;
  final DateTime now;
  final bool showTopDivider;

  const _Group({
    required this.label,
    required this.lanes,
    required this.windowStart,
    required this.windowEnd,
    required this.totalDays,
    required this.now,
    required this.showTopDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: showTopDivider ? const BorderSide(color: AppTheme.borderSoft, width: 1) : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Text(
              label.toUpperCase(),
              style: AppTheme.sans(
                size: 9.5,
                color: AppTheme.fgDim,
                weight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
          for (final lane in lanes)
            _LaneRow(
              lane: lane,
              windowStart: windowStart,
              windowEnd: windowEnd,
              totalDays: totalDays,
              now: now,
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _LaneRow extends StatelessWidget {
  final SwimlaneCardLane lane;
  final DateTime windowStart;
  final DateTime windowEnd;
  final int totalDays;
  final DateTime now;

  const _LaneRow({
    required this.lane,
    required this.windowStart,
    required this.windowEnd,
    required this.totalDays,
    required this.now,
  });

  static const _laneH = 26.0;
  static const _trackH = 14.0;

  String get _subText {
    if (lane.injections.isEmpty) return '';
    final last = lane.injections.first;
    final unit = last.snapshot.unit.toString().split('.').last;
    final dose = last.dosage.toStringAsFixed(last.dosage == last.dosage.truncate() ? 0 : 2);
    if (lane.injections.length >= 2) {
      final sortedAsc = [...lane.injections]..sort((a, b) => a.date.compareTo(b.date));
      double sum = 0;
      for (int i = 1; i < sortedAsc.length; i++) {
        sum += sortedAsc[i].date.difference(sortedAsc[i - 1].date).inHours / 24.0;
      }
      final avg = sum / (sortedAsc.length - 1);
      if (avg < 1.5) return '$dose $unit · daily';
      if ((avg - 3.5).abs() < 1.0) return '$dose $unit · every 3.5d';
      if ((avg - 7.0).abs() < 1.5) return '$dose $unit · weekly';
      return '$dose $unit · every ${avg.toStringAsFixed(1)}d';
    }
    return '$dose $unit';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.compoundColor(lane.compound.base) ?? Color(lane.compound.colorValue);
    final isWindow = lane.isWindow;
    final todayFrac = now.difference(windowStart).inMilliseconds /
        windowEnd.difference(windowStart).inMilliseconds;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 94, child: _Label(lane: lane, color: c, sub: _subText)),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: _laneH,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (isWindow) ...[
                        Positioned(
                          left: 0,
                          right: 0,
                          top: (_laneH - _trackH) / 2,
                          height: _trackH,
                          child: Container(color: AppTheme.bg.withValues(alpha: 0.5)),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: (_laneH - _trackH) / 2,
                          height: _trackH,
                          child: CustomPaint(
                            painter: _GradientStripPainter(
                              color: c,
                              samples: sampleLaneIntensity(
                                injections: lane.injections,
                                windowStart: windowStart,
                                windowEnd: windowEnd,
                                sampleCount: 80,
                              ),
                            ),
                          ),
                        ),
                      ] else
                        Positioned(
                          left: 0,
                          right: 0,
                          top: _laneH / 2 - 0.5,
                          height: 1,
                          child: Container(color: AppTheme.borderSoft),
                        ),
                      for (final dose in lane.injections)
                        _DoseMarker(
                          dose: dose,
                          color: c,
                          isWindow: isWindow,
                          windowStart: windowStart,
                          windowEnd: windowEnd,
                          now: now,
                          laneH: _laneH,
                          trackH: _trackH,
                          maxWidth: constraints.maxWidth,
                        ),
                      Positioned(
                        left: constraints.maxWidth * todayFrac.clamp(0.0, 1.0),
                        top: -3,
                        bottom: -3,
                        child: Container(width: 1, color: AppTheme.fg.withValues(alpha: 0.55)),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 42,
            child: _ValueColumn(lane: lane, now: now, isWindow: isWindow),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final SwimlaneCardLane lane;
  final Color color;
  final String sub;
  const _Label({required this.lane, required this.color, required this.sub});

  @override
  Widget build(BuildContext context) {
    final ester = lane.compound.ester;
    final name = (ester.isEmpty || ester.toLowerCase() == 'none')
        ? lane.compound.base
        : '${lane.compound.base} $ester';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (lane.isWindow)
              Container(width: 9, height: 3, color: color)
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: AppTheme.sans(size: 11.5, weight: FontWeight.w500, height: 1.15),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 15),
          child: Text(
            sub,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: AppTheme.sans(size: 9.5, color: AppTheme.fgDim, height: 1.1),
          ),
        ),
      ],
    );
  }
}

class _ValueColumn extends StatelessWidget {
  final SwimlaneCardLane lane;
  final DateTime now;
  final bool isWindow;
  const _ValueColumn({required this.lane, required this.now, required this.isWindow});

  @override
  Widget build(BuildContext context) {
    String value = '';
    String unit = '';
    if (isWindow) {
      final samples = sampleLaneIntensity(
        injections: lane.injections,
        windowStart: now.subtract(const Duration(seconds: 1)),
        windowEnd: now.add(const Duration(seconds: 1)),
        sampleCount: 2,
      );
      final cur = samples.isNotEmpty ? samples[1] : 0.0;
      value = cur >= 100 ? cur.toStringAsFixed(0) : cur.toStringAsFixed(1);
      unit = lane.compound.unit.toString().split('.').last;
    } else {
      if (lane.injections.isEmpty) {
        value = '—';
      } else {
        final last = lane.injections.first;
        final diff = now.difference(last.date);
        if (diff.inDays >= 1) {
          value = '${diff.inDays}d';
        } else if (diff.inHours >= 0) {
          value = '${diff.inHours}h';
        } else {
          value = 'soon';
        }
        unit = diff.isNegative ? '' : 'ago';
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(value, style: AppTheme.mono(size: 11, weight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(unit, style: AppTheme.sans(size: 8.5, color: AppTheme.fgDim, letterSpacing: 0.3)),
      ],
    );
  }
}

class _DoseMarker extends StatelessWidget {
  final Injection dose;
  final Color color;
  final bool isWindow;
  final DateTime windowStart;
  final DateTime windowEnd;
  final DateTime now;
  final double laneH;
  final double trackH;
  final double maxWidth;

  const _DoseMarker({
    required this.dose,
    required this.color,
    required this.isWindow,
    required this.windowStart,
    required this.windowEnd,
    required this.now,
    required this.laneH,
    required this.trackH,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final totalMs = windowEnd.difference(windowStart).inMilliseconds;
    final pos = dose.date.difference(windowStart).inMilliseconds / totalMs;
    if (pos < -0.02 || pos > 1.02) return const SizedBox.shrink();
    final isFuture = dose.date.isAfter(now);
    final leftPx = maxWidth * pos;

    if (isWindow) {
      return Positioned(
        left: leftPx - 0.5,
        top: (laneH - trackH) / 2 - 4,
        width: 1,
        height: 4,
        child: Container(color: color.withValues(alpha: isFuture ? 0.5 : 1.0)),
      );
    }
    return Positioned(
      left: leftPx - 3,
      top: laneH / 2 - 3,
      width: 6,
      height: 6,
      child: isFuture
          ? Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 1),
              ),
            )
          : Container(decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    );
  }
}

class _GradientStripPainter extends CustomPainter {
  final Color color;
  final List<double> samples;

  _GradientStripPainter({required this.color, required this.samples});

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final maxV = samples.reduce((a, b) => a > b ? a : b);
    if (maxV <= 0) return;
    final stops = <double>[];
    final colors = <Color>[];
    final n = samples.length;
    for (int i = 0; i < n; i++) {
      stops.add(i / (n - 1));
      final intensity = (samples[i] / maxV).clamp(0.0, 1.0);
      colors.add(color.withValues(alpha: intensity));
    }
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(colors: colors, stops: stops).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _GradientStripPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.samples != samples;
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.borderSoft, width: 1)),
      ),
      child: DefaultTextStyle(
        style: AppTheme.sans(size: 10, color: AppTheme.fgMute),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 6,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.fg.withValues(alpha: 0),
                    AppTheme.fg.withValues(alpha: 0.9),
                    AppTheme.fg.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.3, 1],
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Text('active window'),
            const SizedBox(width: 14),
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(color: AppTheme.fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            const Text('event'),
            const Spacer(),
            Container(width: 1, height: 10, color: AppTheme.fg.withValues(alpha: 0.55)),
            const SizedBox(width: 5),
            const Text('today'),
          ],
        ),
      ),
    );
  }
}
