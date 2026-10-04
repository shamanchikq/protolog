import 'package:flutter/material.dart';
import '../../models.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/lab_pickers.dart';
import '../widgets/lab_primitives.dart';
import '../../engine/calendar.dart';
import '../../engine/reminder_schedule.dart';
import '../../engine/library_stats.dart';

class ReminderEditorPage extends StatefulWidget {
  final Reminder? editing;
  final List<CompoundDefinition> userCompounds;
  final DateTime now;
  final void Function(Reminder) onSave;
  final VoidCallback? onDelete;

  const ReminderEditorPage({
    super.key,
    this.editing,
    required this.userCompounds,
    required this.onSave,
    this.onDelete,
    required this.now,
  });

  @override
  State<ReminderEditorPage> createState() => _ReminderEditorPageState();
}

class _ReminderEditorPageState extends State<ReminderEditorPage> {
  // selected compound
  String? _base;
  String? _ester; // 'None' for non-injectables
  Color _color = AppTheme.fgMute;

  String _mode = 'Interval'; // 'Interval' | 'Custom days'

  // interval
  double _interval = 3.5;
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);
  late DateTime _anchorDay;

  // custom: weekday(1-7) -> time
  final Map<int, TimeOfDay> _dayTimes = {};

  // picker state
  String _cat = 'Injectable'; // Injectable | Oral | Peptide | Ancillary
  String? _drillBase;

  bool get _editing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _anchorDay = dateOnly(widget.now);
    final e = widget.editing;
    if (e != null) {
      _base = e.compoundBase;
      _ester = e.compoundEster;
      _color = AppTheme.compoundColor(e.compoundBase) ?? AppTheme.fgMute;
      if (e.scheduleMode == 'custom') {
        _mode = 'Custom days';
        for (final s in e.customSlots) {
          _dayTimes[s.weekday] = TimeOfDay(hour: s.hour, minute: s.minute);
        }
      } else {
        _mode = 'Interval';
        _interval = e.intervalDays;
        final a = e.anchorDate ?? DateTime(widget.now.year, widget.now.month, widget.now.day, e.hour, e.minute);
        _time = TimeOfDay(hour: a.hour, minute: a.minute);
        _anchorDay = dateOnly(a);
      }
    } else {
      _dayTimes.addAll({1: const TimeOfDay(hour: 8, minute: 0), 3: const TimeOfDay(hour: 8, minute: 0), 5: const TimeOfDay(hour: 8, minute: 0)});
    }
  }

  bool get _canSave => _base != null && (_mode == 'Interval' || _dayTimes.isNotEmpty);

  Reminder _buildReminder() {
    final id = widget.editing?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    if (_mode == 'Interval') {
      final anchor = DateTime(_anchorDay.year, _anchorDay.month, _anchorDay.day, _time.hour, _time.minute);
      return Reminder(
        id: id, compoundBase: _base!, compoundEster: _ester ?? 'None',
        scheduleMode: 'interval', intervalDays: _interval,
        hour: _time.hour, minute: _time.minute, enabled: widget.editing?.enabled ?? true,
        anchorDate: anchor,
        notificationSeed: widget.editing?.notificationSeed,
      );
    }
    final slots = (_dayTimes.keys.toList()..sort())
        .map((d) => ReminderSlot(weekday: d, hour: _dayTimes[d]!.hour, minute: _dayTimes[d]!.minute))
        .toList();
    return Reminder(
      id: id, compoundBase: _base!, compoundEster: _ester ?? 'None',
      scheduleMode: 'custom', intervalDays: 0, hour: 8, minute: 0,
      customSlots: slots, enabled: widget.editing?.enabled ?? true,
      notificationSeed: widget.editing?.notificationSeed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                children: [
                  _label('Compound'),
                  const SizedBox(height: 8),
                  _base == null ? _compoundPicker() : _compoundChip(),
                  const SizedBox(height: 18),
                  LabSegmented<String>(
                    value: _mode, options: const ['Interval', 'Custom days'],
                    labelFor: (s) => s, onChange: (m) => setState(() => _mode = m),
                  ),
                  const SizedBox(height: 18),
                  if (_mode == 'Interval') ..._intervalControls() else ..._customControls(),
                  if (_base != null) ...[
                    const SizedBox(height: 18),
                    _preview(),
                  ],
                ],
              ),
            ),
            _saveBar(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(border: Border.all(color: AppTheme.border, width: 1)),
                  child: Center(child: Text('←', style: AppTheme.sans(size: 17))),
                ),
              ),
              if (_editing && widget.onDelete != null)
                GestureDetector(
                  onTap: _confirmDelete,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(border: Border.all(color: AppTheme.warn, width: 1)),
                    child: Text('Delete', style: AppTheme.sans(size: 11.5, weight: FontWeight.w600, color: AppTheme.warn, letterSpacing: 0.2)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Reminders · ${_editing ? 'edit' : 'new'}', style: AppTheme.sans(size: 11, color: AppTheme.fgDim)),
          const SizedBox(height: 3),
          Text(_editing ? 'Edit reminder' : 'New reminder', style: AppTheme.serif(size: 24, weight: FontWeight.w500, letterSpacing: -0.5)),
        ],
      ),
    );
  }

  Widget _label(String s) => Text(s.toUpperCase(), style: AppTheme.sans(size: 9.5, color: AppTheme.fgDim, letterSpacing: 0.9));

  // ---- compound picker ----
  // The catalogue is cataloguedCompounds (same set and order as the Library
  // and wizard); the picker only groups it, one card per base, with a
  // steroid base's esters behind a drill-down.
  List<CompoundDefinition> _catalogFor(String cat, List<CompoundDefinition> catalogue) {
    final type = switch (cat) {
      'Injectable' => CompoundType.steroid,
      'Oral' => CompoundType.oral,
      'Peptide' => CompoundType.peptide,
      _ => CompoundType.ancillary,
    };
    final ofType = catalogue.where((c) => c.type == type);
    if (type == CompoundType.steroid && _drillBase != null) {
      return ofType.where((c) => c.base == _drillBase).toList();
    }
    final byBase = <String, CompoundDefinition>{};
    for (final c in ofType) {
      byBase.putIfAbsent(c.base, () => c);
    }
    return byBase.values.toList();
  }

  static int _esterCount(String base, List<CompoundDefinition> catalogue) => catalogue
      .where((c) => c.type == CompoundType.steroid && c.base == base)
      .map((c) => c.ester)
      .toSet()
      .length;

  void _select(CompoundDefinition c) {
    setState(() {
      _base = c.base;
      _ester = c.ester;
      _color = AppTheme.compoundColor(c.base) ?? Color(c.colorValue);
      _drillBase = null;
    });
  }

  Widget _compoundPicker() {
    final catalogue = cataloguedCompounds(userCompounds: widget.userCompounds);
    if (_drillBase != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _drillBase = null),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(border: Border.all(color: AppTheme.border, width: 1)),
                  child: Text('‹', style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
                ),
              ),
              const SizedBox(width: 10),
              Text('$_drillBase · select ester', style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(color: AppTheme.surface, border: Border.all(color: AppTheme.border, width: 1)),
            child: Column(
              children: [
                for (final c in _catalogFor('Injectable', catalogue))
                  GestureDetector(
                    onTap: () => _select(c),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(c.ester, style: AppTheme.sans(size: 13, weight: FontWeight.w500)),
                          Text('›', style: AppTheme.sans(size: 16, color: AppTheme.fgDim)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    const cats = ['Injectable', 'Oral', 'Peptide', 'Ancillary'];
    final items = _catalogFor(_cat, catalogue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final ct in cats) ...[
                LabPill(label: ct, active: ct == _cat, onTap: () => setState(() { _cat = ct; _drillBase = null; })),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _pickerGrid(items, catalogue),
      ],
    );
  }

  /// Three cards per row. The original 1.45 aspect ratio is only a minimum:
  /// a row grows to fit large text or a wrapped name instead of overflowing
  /// a fixed-ratio grid cell (C1).
  Widget _pickerGrid(List<CompoundDefinition> items, List<CompoundDefinition> catalogue) {
    const columns = 3;
    const gap = 8.0;
    return LayoutBuilder(builder: (context, constraints) {
      final minHeight = (constraints.maxWidth - gap * (columns - 1)) / columns / 1.45;
      return Column(
        children: [
          for (var i = 0; i < items.length; i += columns) ...[
            if (i > 0) const SizedBox(height: gap),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = i; j < i + columns; j++) ...[
                    if (j > i) const SizedBox(width: gap),
                    Expanded(
                      child: j < items.length
                          ? ConstrainedBox(
                              constraints: BoxConstraints(minHeight: minHeight),
                              child: _pickerCard(items[j], catalogue),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    });
  }

  Widget _pickerCard(CompoundDefinition c, List<CompoundDefinition> catalogue) {
    final isInjectable = c.type == CompoundType.steroid;
    final esters = isInjectable ? _esterCount(c.base, catalogue) : 1;
    final multi = isInjectable && _drillBase == null && esters > 1;
    final color = AppTheme.compoundColor(c.base) ?? Color(c.colorValue);
    return GestureDetector(
      onTap: () {
        if (multi) {
          setState(() => _drillBase = c.base);
        } else {
          _select(c);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border(
            top: BorderSide(color: color, width: 2),
            left: const BorderSide(color: AppTheme.border, width: 1),
            right: const BorderSide(color: AppTheme.border, width: 1),
            bottom: const BorderSide(color: AppTheme.border, width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(isInjectable && _drillBase == null ? c.base : (isInjectable ? c.ester : c.base),
                style: AppTheme.sans(size: 12.5, weight: FontWeight.w600, height: 1.15)),
            Text(
              multi ? '$esters esters ›' : (isInjectable ? c.ester : c.type.name),
              style: AppTheme.sans(size: 10, color: AppTheme.fgMute),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compoundChip() {
    final esterShown = _ester != null && _ester!.isNotEmpty && _ester!.toLowerCase() != 'none';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          left: BorderSide(color: _color, width: 3),
          top: const BorderSide(color: AppTheme.border, width: 1),
          right: const BorderSide(color: AppTheme.border, width: 1),
          bottom: const BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              esterShown ? '$_base · $_ester' : '$_base',
              style: AppTheme.sans(size: 14, weight: FontWeight.w600, letterSpacing: -0.2),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() { _base = null; _ester = null; _drillBase = null; }),
            behavior: HitTestBehavior.opaque,
            child: Text('Change', style: AppTheme.sans(size: 11, color: AppTheme.accent)),
          ),
        ],
      ),
    );
  }

  // ---- interval controls ----
  List<Widget> _intervalControls() {
    final numStr = _interval == _interval.roundToDouble() ? _interval.toInt().toString() : _interval.toString();
    return [
      _label('Every'),
      const SizedBox(height: 6),
      Container(
        height: 56,
        decoration: BoxDecoration(color: AppTheme.surface, border: Border.all(color: AppTheme.border, width: 1)),
        child: Row(
          children: [
            _stepBtn('−', () => setState(() => _interval = (_interval - 0.5).clamp(0.5, 90))),
            Expanded(
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(numStr, style: AppTheme.serif(size: 30, weight: FontWeight.w500, letterSpacing: -0.6)),
                    const SizedBox(width: 6),
                    Text(_interval == 1.0 ? 'day' : 'days', style: AppTheme.sans(size: 13, color: AppTheme.fgMute)),
                  ],
                ),
              ),
            ),
            _stepBtn('+', () => setState(() => _interval = (_interval + 0.5).clamp(0.5, 90))),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LabField(
              label: 'Time',
              onTap: _pickIntervalTime,
              child: Text(formatHourMinute(_time.hour, _time.minute), style: AppTheme.mono(size: 16, weight: FontWeight.w500)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LabField(
              label: 'First dose',
              hint: 'anchor',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Calendar days: a 24 h step loses or skips a date at DST.
                  GestureDetector(onTap: () => setState(() => _anchorDay = addCalendarDays(_anchorDay, -1)), child: Text('‹', style: AppTheme.sans(size: 16, color: AppTheme.fgMute))),
                  Expanded(child: Center(child: Text(relativeDayLabel(_anchorDay, widget.now), style: AppTheme.sans(size: 13, weight: FontWeight.w500)))),
                  GestureDetector(onTap: () => setState(() => _anchorDay = addCalendarDays(_anchorDay, 1)), child: Text('›', style: AppTheme.sans(size: 16, color: AppTheme.fgMute))),
                ],
              ),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _stepBtn(String s, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 46,
          color: AppTheme.surface2,
          child: Center(child: Text(s, style: AppTheme.sans(size: 22, weight: FontWeight.w300))),
        ),
      );

  /// The Lab Sheet picker with a 24-hour dial, matching how times read.
  static Widget _picker24h(BuildContext ctx, Widget? child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: labPickerTheme(child!),
      );

  Future<void> _pickIntervalTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: _picker24h,
    );
    if (t != null && mounted) setState(() => _time = t);
  }

  // ---- custom controls ----
  List<Widget> _customControls() {
    return [
      _label('Days'),
      const SizedBox(height: 8),
      Row(
        children: [
          LabPill(label: 'Weekdays', onTap: () => _setDays([1, 2, 3, 4, 5])),
          const SizedBox(width: 6),
          LabPill(label: 'MWF', onTap: () => _setDays([1, 3, 5])),
          const SizedBox(width: 6),
          LabPill(label: 'TTS', onTap: () => _setDays([2, 4, 6])),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          for (var i = 0; i < 7; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(child: _dayToggle(i + 1, weekdayLetter(i + 1))),
          ],
        ],
      ),
      if (_dayTimes.isNotEmpty) ...[
        const SizedBox(height: 14),
        _label('Time per day'),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(color: AppTheme.surface, border: Border.all(color: AppTheme.border, width: 1)),
          child: Column(
            children: [
              for (final d in _dayTimes.keys.toList()..sort()) _dayTimeRow(d),
            ],
          ),
        ),
      ],
    ];
  }

  void _setDays(List<int> days) {
    setState(() {
      _dayTimes.clear();
      for (final d in days) {
        _dayTimes[d] = const TimeOfDay(hour: 8, minute: 0);
      }
    });
  }

  Widget _dayToggle(int weekday, String letter) {
    final on = _dayTimes.containsKey(weekday);
    return GestureDetector(
      onTap: () => setState(() {
        if (on) {
          _dayTimes.remove(weekday);
        } else {
          _dayTimes[weekday] = const TimeOfDay(hour: 8, minute: 0);
        }
      }),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: on ? AppTheme.fg : Colors.transparent,
          border: Border.all(color: on ? AppTheme.fg : AppTheme.border, width: 1),
        ),
        child: Center(child: Text(letter, style: AppTheme.sans(size: 11, weight: on ? FontWeight.w600 : FontWeight.w400, color: on ? AppTheme.bg : AppTheme.fgMute))),
      ),
    );
  }

  Widget _dayTimeRow(int weekday) {
    final t = _dayTimes[weekday]!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          SizedBox(width: 44, child: Text(weekdaysShort[weekday - 1], style: AppTheme.sans(size: 12.5, weight: FontWeight.w500))),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              key: ValueKey('slot-time-$weekday'),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: t,
                  builder: _picker24h,
                );
                if (picked != null && mounted) setState(() => _dayTimes[weekday] = picked);
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(border: Border.all(color: AppTheme.border, width: 1)),
                child: Text(formatHourMinute(t.hour, t.minute), style: AppTheme.mono(size: 13, weight: FontWeight.w500)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- preview ----
  Widget _preview() {
    final r = _buildReminder();
    final dose = expectedDose(r, widget.now);
    final state = reminderState(r, widget.now);
    final (color, label) = switch (state) {
      ReminderState.overdue => (AppTheme.warn, 'Overdue'),
      ReminderState.due => (AppTheme.warm, 'Due'),
      ReminderState.on => (AppTheme.accent, 'On'),
      ReminderState.paused => (AppTheme.fgDim, 'Paused'),
    };
    final doseLabel = '${relativeDayLabel(dose, widget.now)} · ${formatHourMinute(dose.hour, dose.minute)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: AppTheme.surface, border: Border.all(color: AppTheme.border, width: 1)),
      child: Row(
        children: [
          Container(width: 3, height: 32, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Next dose'),
                const SizedBox(height: 4),
                Text(doseLabel, style: AppTheme.mono(size: 16, weight: FontWeight.w500, letterSpacing: -0.3)),
              ],
            ),
          ),
          Text(label, style: AppTheme.sans(size: 11, weight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  // ---- save / delete ----
  Widget _saveBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: GestureDetector(
        onTap: _canSave
            ? () {
                widget.onSave(_buildReminder());
                Navigator.of(context).pop();
              }
            : null,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: _canSave ? 1 : 0.75,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            color: _canSave ? AppTheme.accent : AppTheme.surface2,
            child: Center(child: Text('Save reminder', style: AppTheme.sans(size: 13, weight: FontWeight.w600, color: _canSave ? AppTheme.bg : AppTheme.fgDim, letterSpacing: 0.3))),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        title: Text('Delete reminder?', style: AppTheme.sans(size: 15, weight: FontWeight.w600)),
        content: Text('This removes the reminder and cancels its notifications.', style: AppTheme.sans(size: 13, color: AppTheme.fgMute)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('Cancel', style: AppTheme.sans(color: AppTheme.fgMute))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('Delete', style: AppTheme.sans(color: AppTheme.warn, weight: FontWeight.w600))),
        ],
      ),
    );
    if (ok == true && widget.onDelete != null) {
      widget.onDelete!();
      if (mounted) Navigator.of(context).pop();
    }
  }
}
