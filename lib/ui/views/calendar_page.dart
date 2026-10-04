import 'package:flutter/material.dart';

import '../../engine/calendar.dart';
import '../../models.dart';
import '../format.dart';
import '../theme.dart';

class CalendarPage extends StatefulWidget {
  final List<Injection> injections;
  final void Function(String injectionId) onDeleteInjection;
  final void Function(String injectionId, String? notes) onUpdateNotes;

  /// F2: tapping a day-detail row opens the wizard in edit mode.
  final void Function(Injection injection)? onEditInjection;
  final ValueChanged<DateTime>? onDaySelected;

  /// Live base→color resolver. Falls back to the static palette + snapshot
  /// color when not supplied (e.g. in widget tests).
  final Color Function(String baseName)? colorResolver;

  /// "Now" for today's highlight and the initial selection; the real clock
  /// when null (tests pin it).
  final DateTime? now;

  const CalendarPage({
    super.key,
    required this.injections,
    required this.onDeleteInjection,
    required this.onUpdateNotes,
    this.onEditInjection,
    this.onDaySelected,
    this.colorResolver,
    this.now,
  });

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

/// "0.25 mg": amount without float noise or truncation + unit name.
String _doseText(Injection inj) =>
    '${formatDose(inj.dosage)} ${inj.snapshot.unit.name}';

class _CalendarPageState extends State<CalendarPage> {
  // All date logic below works on calendar fields (DateTime(y, m, d),
  // isSameCalendarDay) — never Duration(days:) — so the grid and day
  // grouping stay right across DST switches (B27).
  late DateTime _month;
  late DateTime _selectedDay;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final now = _now;
    _month = DateTime(now.year, now.month);
    _selectedDay = dateOnly(now);
    // Report the initial (today) selection so the host can pre-fill the
    // "Log dose" FAB with the calendar's current day.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onDaySelected?.call(_selectedDay),
    );
  }

  Map<int, List<Color>> _dayBarColors() {
    final Map<int, List<Color>> out = {};
    final year = _month.year;
    final month = _month.month;
    final sorted = List<Injection>.from(widget.injections)
      ..sort((a, b) => a.date.compareTo(b.date));
    for (final inj in sorted) {
      if (inj.date.year == year && inj.date.month == month) {
        final color =
            widget.colorResolver?.call(inj.snapshot.base) ??
            AppTheme.compoundColor(inj.snapshot.base) ??
            Color(inj.snapshot.colorValue);
        final list = out.putIfAbsent(inj.date.day, () => []);
        if (!list.contains(color)) list.add(color);
      }
    }
    return out;
  }

  List<Injection> _entriesForSelectedDay() {
    final d = _selectedDay;
    final list =
        widget.injections.where((i) => isSameCalendarDay(i.date, d)).toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// Moves the grid by [delta] months and moves the selection with it —
  /// today when it falls in the new month, else the 1st — so the day list
  /// and the "Log dose" FAB pre-fill never point at a day off-screen (B31).
  void _changeMonth(int delta) {
    final month = DateTime(_month.year, _month.month + delta);
    final today = dateOnly(_now);
    final selected =
        (today.year == month.year && today.month == month.month) ? today : month;
    setState(() {
      _month = month;
      _selectedDay = selected;
    });
    widget.onDaySelected?.call(selected);
  }

  void _selectDay(int day) {
    setState(() {
      _selectedDay = DateTime(_month.year, _month.month, day);
    });
    widget.onDaySelected?.call(_selectedDay);
  }

  Future<bool> _confirmDelete(Injection inj) async {
    final esterRaw = inj.snapshot.ester;
    final hasEster = esterRaw.isNotEmpty && esterRaw.toLowerCase() != 'none';
    final description =
        "${inj.snapshot.base}${hasEster ? ' $esterRaw' : ''} — ${_doseText(inj)}";

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: AppTheme.border, width: 1),
          borderRadius: BorderRadius.zero,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Delete entry?',
                style: AppTheme.serif(
                  size: 18,
                  weight: FontWeight.w500,
                  color: AppTheme.fg,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                style: AppTheme.sans(size: 13, color: AppTheme.fgMute),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(
                      'Cancel',
                      style: AppTheme.sans(
                        size: 13,
                        weight: FontWeight.w500,
                        color: AppTheme.fgMute,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(
                      'Delete',
                      style: AppTheme.sans(
                        size: 13,
                        weight: FontWeight.w500,
                        color: AppTheme.warn,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final dayBars = _dayBarColors();
    final entries = _entriesForSelectedDay();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        _MonthHeader(
          month: _month,
          onPrev: () => _changeMonth(-1),
          onNext: () => _changeMonth(1),
        ),
        const SizedBox(height: 18),
        const _WeekdayStrip(),
        const SizedBox(height: 8),
        _MonthGrid(
          month: _month,
          today: _now,
          selectedDay: _selectedDay,
          dayBars: dayBars,
          onDayTap: _selectDay,
          onSwipeLeft: () => _changeMonth(1),
          onSwipeRight: () => _changeMonth(-1),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: _SelectedDaySection(
            selectedDay: _selectedDay,
            entries: entries,
            onDeleteConfirm: _confirmDelete,
            onDelete: widget.onDeleteInjection,
            onEditNotes: widget.onUpdateNotes,
            onEditInjection: widget.onEditInjection,
            colorResolver: widget.colorResolver,
          ),
        ),
      ],
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _MonthHeader({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: RichText(
              text: TextSpan(
                style: AppTheme.serif(
                  size: 26,
                  weight: FontWeight.w500,
                  color: AppTheme.fg,
                  letterSpacing: -0.5,
                ),
                children: [
                  TextSpan(text: '${monthsLong[month.month - 1]} '),
                  TextSpan(
                    text: '${month.year}',
                    style: AppTheme.serif(
                      size: 26,
                      weight: FontWeight.w300,
                      color: AppTheme.fgMute,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _ChevronButton(glyph: '‹', onTap: onPrev),
          const SizedBox(width: 4),
          _ChevronButton(glyph: '›', onTap: onNext),
        ],
      ),
    );
  }
}

class _ChevronButton extends StatelessWidget {
  final String glyph;
  final VoidCallback onTap;

  const _ChevronButton({required this.glyph, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.border, width: 1),
        ),
        child: Text(
          glyph,
          style: AppTheme.sans(size: 14, color: AppTheme.fgMute),
        ),
      ),
    );
  }
}

class _WeekdayStrip extends StatelessWidget {
  const _WeekdayStrip();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        // M T W T F S S
        children: weekdaysShort
            .map((d) => d[0])
            .map(
              (d) => Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: AppTheme.sans(
                      size: 10,
                      weight: FontWeight.w500,
                      color: AppTheme.fgDim,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final DateTime today;
  final DateTime selectedDay;
  final Map<int, List<Color>> dayBars;
  final void Function(int day) onDayTap;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;

  const _MonthGrid({
    required this.month,
    required this.today,
    required this.selectedDay,
    required this.dayBars,
    required this.onDayTap,
    required this.onSwipeLeft,
    required this.onSwipeRight,
  });

  @override
  Widget build(BuildContext context) {
    final year = month.year;
    final m = month.month;
    // Day 0 of next month = last day of this one (calendar fields, DST-safe).
    final daysInMonth = DateTime(year, m + 1, 0).day;
    final firstWeekday = DateTime(year, m, 1).weekday; // 1=Mon
    final leading = firstWeekday - 1;
    final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity;
          if (v == null) return;
          if (v < -200) onSwipeLeft();
          if (v > 200) onSwipeRight();
        },
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            mainAxisExtent: 50,
          ),
          itemCount: totalCells,
          itemBuilder: (context, index) {
            if (index < leading || index >= leading + daysInMonth) {
              return const SizedBox.shrink();
            }
            final day = index - leading + 1;
            final date = DateTime(year, m, day);
            final isToday = isSameCalendarDay(today, date);
            final isSelected = isSameCalendarDay(selectedDay, date);
            final bars = dayBars[day] ?? const <Color>[];
            return _DayCell(
              day: day,
              isToday: isToday,
              isSelected: isSelected,
              bars: bars,
              onTap: () => onDayTap(day),
            );
          },
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final bool isToday;
  final bool isSelected;
  final List<Color> bars;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.bars,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color borderColor = isToday
        ? AppTheme.paperInk
        : (isSelected ? AppTheme.fg : Colors.transparent);
    final Color bg = isToday ? AppTheme.paper : Colors.transparent;
    final Color textColor = isToday ? AppTheme.paperInk : AppTheme.fg;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Text(
                '$day',
                style: AppTheme.sans(
                  size: 12,
                  weight: isToday ? FontWeight.w700 : FontWeight.w400,
                  color: textColor,
                ),
              ),
            ),
            if (bars.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Row(
                  children: [
                    for (int i = 0; i < bars.length; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(child: Container(height: 2, color: bars[i])),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SelectedDaySection extends StatelessWidget {
  final DateTime selectedDay;
  final List<Injection> entries;
  final Future<bool> Function(Injection inj) onDeleteConfirm;
  final void Function(String injectionId) onDelete;
  final void Function(String injectionId, String? notes) onEditNotes;
  final void Function(Injection injection)? onEditInjection;
  final Color Function(String baseName)? colorResolver;

  const _SelectedDaySection({
    required this.selectedDay,
    required this.entries,
    required this.onDeleteConfirm,
    required this.onDelete,
    required this.onEditNotes,
    this.onEditInjection,
    this.colorResolver,
  });

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    // "SUNDAY, OCT 4"
    final header = '${weekdaysLong[selectedDay.weekday - 1].toUpperCase()}, '
        '${monthsShort[selectedDay.month - 1].toUpperCase()} ${selectedDay.day}';
    final count = entries.length;
    final countStr = '$count ${count == 1 ? 'entry' : 'entries'}';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  header,
                  style: AppTheme.sans(
                    size: 11,
                    weight: FontWeight.w500,
                    color: AppTheme.fgDim,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Text(
                countStr,
                style: AppTheme.mono(size: 11, color: AppTheme.fgMute),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No entries on this day',
                style: AppTheme.sans(size: 12, color: AppTheme.fgDim),
              ),
            )
          else
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border.all(color: AppTheme.border, width: 1),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < entries.length; i++)
                    Dismissible(
                      key: ValueKey(entries[i].id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: AppTheme.warn,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Delete',
                          style: AppTheme.sans(
                            size: 13,
                            weight: FontWeight.w500,
                            color: AppTheme.paper,
                          ),
                        ),
                      ),
                      confirmDismiss: (_) => onDeleteConfirm(entries[i]),
                      onDismissed: (_) => onDelete(entries[i].id),
                      child: _EntryRow(
                        injection: entries[i],
                        showTopBorder: i > 0,
                        twoDigits: _twoDigits,
                        onEditNotes: onEditNotes,
                        onEditInjection: onEditInjection,
                        colorResolver: colorResolver,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final Injection injection;
  final bool showTopBorder;
  final String Function(int) twoDigits;
  final void Function(String injectionId, String? notes) onEditNotes;
  final void Function(Injection injection)? onEditInjection;
  final Color Function(String baseName)? colorResolver;

  const _EntryRow({
    required this.injection,
    required this.showTopBorder,
    required this.twoDigits,
    required this.onEditNotes,
    this.onEditInjection,
    this.colorResolver,
  });

  Future<void> _editNotes(BuildContext context) async {
    final result = await showDialog<String?>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => _EditNotesDialog(initial: injection.notes ?? ''),
    );
    // result == null → user cancelled. Otherwise we got the new value (may be empty).
    if (result == null) return;
    onEditNotes(injection.id, result.trim().isEmpty ? null : result.trim());
  }

  @override
  Widget build(BuildContext context) {
    final esterRaw = injection.snapshot.ester;
    final hasEster = esterRaw.isNotEmpty && esterRaw.toLowerCase() != 'none';
    final name = hasEster
        ? '${injection.snapshot.base} $esterRaw'
        : injection.snapshot.base;
    final time =
        '${twoDigits(injection.date.hour)}:${twoDigits(injection.date.minute)}';
    final color =
        colorResolver?.call(injection.snapshot.base) ??
        AppTheme.compoundColor(injection.snapshot.base) ??
        Color(injection.snapshot.colorValue);
    final hasNotes =
        injection.notes != null && injection.notes!.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: showTopBorder
            ? const Border(
                top: BorderSide(color: AppTheme.borderSoft, width: 1),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Row tap opens the full edit flow; the notes icon inside keeps
            // its own handler and wins hit-testing over this one.
            onTap: onEditInjection != null
                ? () => onEditInjection!(injection)
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(
                      time,
                      style: AppTheme.mono(size: 11, color: AppTheme.fgMute),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(width: 3, height: 18, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    // Site sits outside the name's ellipsis scope so a long
                    // compound name truncates instead of hiding the site.
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.sans(size: 13, color: AppTheme.fg),
                          ),
                        ),
                        if (injection.site != null &&
                            injection.site!.isNotEmpty)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 110),
                            child: Text(
                              ' · ${injection.site}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.sans(
                                size: 11,
                                color: AppTheme.fgDim,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _editNotes(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Icon(
                        hasNotes
                            ? Icons.sticky_note_2_outlined
                            : Icons.add_comment_outlined,
                        size: 14,
                        color: hasNotes ? AppTheme.accent : AppTheme.fgDim,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _doseText(injection),
                    style: AppTheme.mono(size: 12, color: AppTheme.fg),
                  ),
                ],
              ),
            ),
          ),
          if (hasNotes)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _editNotes(context),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(
                      width: 48 + 12 + 3 + 12,
                    ), // align with name column
                    Expanded(
                      child: Text(
                        injection.notes!,
                        style: AppTheme.sans(
                          size: 11,
                          color: AppTheme.fgMute,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EditNotesDialog extends StatefulWidget {
  final String initial;
  const _EditNotesDialog({required this.initial});

  @override
  State<_EditNotesDialog> createState() => _EditNotesDialogState();
}

class _EditNotesDialogState extends State<_EditNotesDialog> {
  late final TextEditingController _ctl = TextEditingController(
    text: widget.initial,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_ctl.text);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(color: AppTheme.border, width: 1),
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Notes',
              style: AppTheme.serif(
                size: 18,
                weight: FontWeight.w500,
                color: AppTheme.fg,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.bg,
                border: Border.all(color: AppTheme.border, width: 1),
              ),
              child: TextField(
                controller: _ctl,
                focusNode: _focus,
                minLines: 3,
                maxLines: 6,
                cursorColor: AppTheme.accent,
                style: AppTheme.sans(size: 14, color: AppTheme.fg),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  hintText: 'Add a note…',
                  hintStyle: AppTheme.sans(size: 14, color: AppTheme.fgDim),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(null),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Text(
                      'Cancel',
                      style: AppTheme.sans(size: 13, color: AppTheme.fgMute),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _save,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    color: AppTheme.accent,
                    child: Text(
                      'Save',
                      style: AppTheme.sans(
                        size: 13,
                        weight: FontWeight.w600,
                        color: AppTheme.bg,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
