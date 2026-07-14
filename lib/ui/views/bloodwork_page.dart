import 'package:flutter/material.dart';
import '../../models.dart';
import '../../engine/bloodwork_stats.dart';
import '../theme.dart';
import '../widgets/lab_primitives.dart';
import '../widgets/bloodwork_editor_dialog.dart';

/// Full bloodwork page (F6 rework): per-marker trend chart in the marker's
/// own units plus the complete history with deltas. Owns a working copy of
/// the entries; every mutation is reported through [onChanged] so the host
/// can persist.
class BloodworkPage extends StatefulWidget {
  final List<BloodworkEntry> initialEntries;
  final String? initialMarker;
  final Map<String, String> markerSuggestions;
  final void Function(List<BloodworkEntry> entries) onChanged;

  const BloodworkPage({
    super.key,
    required this.initialEntries,
    this.initialMarker,
    this.markerSuggestions = const {},
    required this.onChanged,
  });

  @override
  State<BloodworkPage> createState() => _BloodworkPageState();
}

class _BloodworkPageState extends State<BloodworkPage> {
  late final List<BloodworkEntry> _entries = List.of(widget.initialEntries);
  String? _selected;

  static const _monthsShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    final markers = distinctMarkers(_entries);
    _selected =
        (widget.initialMarker != null && markers.contains(widget.initialMarker))
        ? widget.initialMarker
        : (markers.isNotEmpty ? markers.first : null);
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  String _fmtDate(DateTime d) => '${_monthsShort[d.month - 1]} ${d.day}';

  Future<void> _openEditor({BloodworkEntry? editing}) async {
    final result = await showDialog<BloodworkDialogResult>(
      context: context,
      builder: (_) => BloodworkEditorDialog(
        editing: editing,
        markerSuggestions: widget.markerSuggestions,
      ),
    );
    if (result == null) return;
    setState(() {
      if (result.delete) {
        _entries.removeWhere((b) => b.id == editing!.id);
      } else {
        final entry = result.entry!;
        final i = _entries.indexWhere((b) => b.id == entry.id);
        if (i >= 0) {
          _entries[i] = entry;
        } else {
          _entries.add(entry);
        }
      }
      final markers = distinctMarkers(_entries);
      if (_selected == null || !markers.contains(_selected)) {
        _selected = markers.isNotEmpty ? markers.first : null;
      }
    });
    widget.onChanged(_entries);
  }

  @override
  Widget build(BuildContext context) {
    final markers = distinctMarkers(_entries);
    final history = _selected != null
        ? historyFor(_selected!, _entries)
        : <BloodworkEntry>[];
    final unit = history.isNotEmpty ? history.last.unit : '';

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bloodwork',
                          style: AppTheme.serif(
                            size: 26,
                            weight: FontWeight.w500,
                            color: AppTheme.fg,
                            letterSpacing: -0.5,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_entries.length} result${_entries.length == 1 ? '' : 's'}'
                          '${markers.isNotEmpty ? ' · ${markers.length} marker${markers.length == 1 ? '' : 's'}' : ''}',
                          style: AppTheme.sans(
                            size: 11,
                            color: AppTheme.fgMute,
                          ),
                        ),
                      ],
                    ),
                  ),
                  LabPill(
                    label: '+ Add',
                    primary: true,
                    onTap: () => _openEditor(),
                  ),
                  const SizedBox(width: 6),
                  LabPill(
                    label: 'Close',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  for (final m in markers) ...[
                    LabPill(
                      label: m,
                      active: m == _selected,
                      onTap: () => setState(() => _selected = m),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _entries.isEmpty
                  ? Center(
                      child: Text(
                        'No lab results yet.',
                        style: AppTheme.sans(size: 12, color: AppTheme.fgDim),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                      children: [
                        // Trend chart in the marker's own units.
                        Container(
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            border: Border.all(
                              color: AppTheme.border,
                              width: 1,
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_selected ?? ''}  ·  $unit',
                                style: AppTheme.sans(
                                  size: 11,
                                  color: AppTheme.fgMute,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 160,
                                width: double.infinity,
                                child: history.length < 2
                                    ? Center(
                                        child: Text(
                                          history.length == 1
                                              ? '${_fmt(history.first.value)} $unit — one draw so far; trends appear with the next one.'
                                              : 'No draws for this marker.',
                                          style: AppTheme.sans(
                                            size: 11,
                                            color: AppTheme.fgDim,
                                          ),
                                        ),
                                      )
                                    : CustomPaint(
                                        painter: _TrendPainter(
                                          history: history,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        // Full history for the selected marker, newest first.
                        Container(
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            border: Border.all(
                              color: AppTheme.border,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              for (int i = history.length - 1; i >= 0; i--)
                                _historyRow(
                                  history[i],
                                  first: i == history.length - 1,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyRow(BloodworkEntry e, {required bool first}) {
    final delta = deltaVsPrevious(e, _entries);
    String deltaStr = '';
    Color deltaColor = AppTheme.fgDim;
    if (delta != null && delta != 0) {
      deltaStr = '${delta > 0 ? '↑' : '↓'} ${_fmt(delta.abs())}';
      deltaColor = delta > 0 ? AppTheme.accent : AppTheme.warn;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openEditor(editing: e),
      child: Container(
        decoration: BoxDecoration(
          border: first
              ? null
              : const Border(
                  top: BorderSide(color: AppTheme.borderSoft, width: 1),
                ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                _fmtDate(e.date),
                style: AppTheme.mono(size: 11, color: AppTheme.fgMute),
              ),
            ),
            Expanded(
              child: Text(
                '${_fmt(e.value)} ${e.unit}'.trim(),
                style: AppTheme.mono(size: 13, color: AppTheme.fg),
              ),
            ),
            Text(deltaStr, style: AppTheme.mono(size: 11, color: deltaColor)),
          ],
        ),
      ),
    );
  }
}

/// Time-proportional line chart of one marker's history in its own units.
class _TrendPainter extends CustomPainter {
  final List<BloodworkEntry> history; // oldest first, length >= 2
  _TrendPainter({required this.history});

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 8.0, padR = 26.0, padT = 14.0, padB = 18.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;

    var minV = history.first.value, maxV = history.first.value;
    for (final e in history) {
      if (e.value < minV) minV = e.value;
      if (e.value > maxV) maxV = e.value;
    }
    var span = maxV - minV;
    if (span <= 0) span = maxV == 0 ? 1 : maxV.abs() * 0.2;
    final lo = minV - span * 0.15, hi = maxV + span * 0.15;

    final t0 = history.first.date.millisecondsSinceEpoch;
    final t1 = history.last.date.millisecondsSinceEpoch;
    final tSpan = (t1 - t0) == 0 ? 1 : (t1 - t0);

    Offset pos(BloodworkEntry e) => Offset(
      padL + w * ((e.date.millisecondsSinceEpoch - t0) / tSpan),
      padT + h * (1 - (e.value - lo) / (hi - lo)),
    );

    // Dashed grid: top / mid / bottom.
    final grid = Paint()
      ..color = AppTheme.border
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = padT + h * f;
      var x = padL;
      while (x < padL + w) {
        canvas.drawLine(Offset(x, y), Offset(x + 2, y), grid);
        x += 5;
      }
    }

    final line = Paint()
      ..color = AppTheme.warm
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(pos(history.first).dx, pos(history.first).dy);
    for (final e in history.skip(1)) {
      final p = pos(e);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, line);

    final dot = Paint()..color = AppTheme.warm;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    String fmt(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
    for (final e in history) {
      final p = pos(e);
      canvas.drawCircle(p, 3, dot);
      tp.text = TextSpan(
        text: fmt(e.value),
        style: AppTheme.mono(size: 9, color: AppTheme.fg),
      );
      tp.layout();
      tp.paint(
        canvas,
        Offset(
          (p.dx - tp.width / 2).clamp(0, size.width - tp.width),
          p.dy - 14,
        ),
      );
    }

    // First/last date labels.
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    for (final e in [history.first, history.last]) {
      final p = pos(e);
      tp.text = TextSpan(
        text: '${months[e.date.month - 1]} ${e.date.day}',
        style: AppTheme.mono(size: 8, color: AppTheme.fgDim),
      );
      tp.layout();
      tp.paint(
        canvas,
        Offset(
          (p.dx - tp.width / 2).clamp(0, size.width - tp.width),
          size.height - 11,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => old.history != history;
}
