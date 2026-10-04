import 'package:flutter/material.dart';
import '../../models.dart';
import '../../engine/library_stats.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/lab_primitives.dart';
import '../widgets/library_section.dart';
import '../widgets/protolog_shell.dart';
import '../widgets/lab_tap.dart';

class CompoundDetailPage extends StatefulWidget {
  final CompoundDefinition compound;
  final List<Injection> injections;
  final void Function(ShellTab) onTabChanged;
  /// Push the editor for `compound` and resolve with the updated
  /// CompoundDefinition on save, or null on cancel/delete. The detail page
  /// updates its local state when this resolves non-null so the user sees
  /// the new values without leaving the screen.
  final Future<CompoundDefinition?> Function(CompoundDefinition compound) openEditor;
  /// Called after the user confirms deleting the (custom) compound. The host
  /// removes it — and its linked reminders, which the confirmation says go
  /// too — then pops this page.
  final VoidCallback onDelete;
  final void Function(CompoundDefinition compound) onLogInjection;

  /// Reminders for this compound's base+ester, named in the delete
  /// confirmation.
  final int linkedReminderCount;

  /// Live base → display color (MainScreen's resolver), consulted on every
  /// build so a recolor made in the editor shows on return (B26). Without
  /// one, the static palette and then the compound's stored color.
  final Color Function(String base)? colorResolver;

  const CompoundDetailPage({
    super.key,
    required this.compound,
    required this.injections,
    required this.onTabChanged,
    required this.openEditor,
    required this.onDelete,
    required this.onLogInjection,
    this.linkedReminderCount = 0,
    this.colorResolver,
  });

  @override
  State<CompoundDetailPage> createState() => _CompoundDetailPageState();
}

class _CompoundDetailPageState extends State<CompoundDetailPage> {
  late CompoundDefinition _compound;

  @override
  void initState() {
    super.initState();
    _compound = widget.compound;
  }

  Future<void> _handleEdit() async {
    final updated = await widget.openEditor(_compound);
    if (updated != null && mounted) {
      setState(() => _compound = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _compound;
    final recent = recentInjectionsFor(
      base: c.base, ester: c.ester, injections: widget.injections, limit: 5,
    );
    final total = injectionCountFor(
      base: c.base, ester: c.ester, injections: widget.injections,
    );
    final hasHistory = recent.isNotEmpty;

    return ProtoLogShell(
      activeTab: ShellTab.library,
      onTabChanged: (t) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        widget.onTabChanged(t);
      },
      onFabPressed: null,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ActionBar(
                  isCustom: c.isCustom,
                  isEdited: isEditedFromDefault(c),
                  onBack: () => Navigator.of(context).pop(),
                  onEdit: _handleEdit,
                  onDelete: () => _confirmDelete(context),
                ),
                const SizedBox(height: 22),
                _Hero(compound: c, colorResolver: widget.colorResolver),
                const SizedBox(height: 24),
                _PKSection(compound: c),
                const SizedBox(height: 22),
                _HistorySection(
                  compound: c,
                  recent: recent,
                  total: total,
                  onLogFirst: () => widget.onLogInjection(c),
                ),
              ],
            ),
          ),
          if (hasHistory)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _StickyFooter(
                label: 'Log ${displayName(c)} ${doseActionNoun(c.type)}',
                onTap: () => widget.onLogInjection(c),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final c = _compound;
    final ok = await confirmDeleteCompound(
      context,
      compound: c,
      logCount: injectionCountFor(
        base: c.base, ester: c.ester, injections: widget.injections,
      ),
      linkedReminderCount: widget.linkedReminderCount,
    );
    if (ok) widget.onDelete();
  }
}

/// "Delete compound" confirmation shared by the detail page and the Compound
/// Editor. Says what happens to the compound's [logCount] logs (kept, but
/// unlinked) and [linkedReminderCount] reminders (removed with it — the host's
/// delete handler cancels and deletes them). True when the user confirms.
Future<bool> confirmDeleteCompound(
  BuildContext context, {
  required CompoundDefinition compound,
  required int logCount,
  int linkedReminderCount = 0,
}) async {
  final noun = doseActionNoun(compound.type);
  final msg = StringBuffer('Delete ${displayName(compound)}?');
  if (logCount > 0) {
    msg.write(' $logCount $noun${logCount == 1 ? '' : 's'} of this compound '
        'will keep their logged data but will no longer link to a saved '
        'definition.');
  }
  if (linkedReminderCount > 0) {
    msg.write(linkedReminderCount == 1
        ? ' Its reminder will be removed too.'
        : ' Its $linkedReminderCount reminders will be removed too.');
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface2,
      title: Text('Delete compound',
          style: AppTheme.sans(size: 14, weight: FontWeight.w600, color: AppTheme.fg)),
      content: Text(msg.toString(),
          style: AppTheme.sans(size: 12, color: AppTheme.fgMute, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('Cancel',
              style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('Delete',
              style: AppTheme.sans(
                size: 12, weight: FontWeight.w600, color: AppTheme.warn,
              )),
        ),
      ],
    ),
  );
  return ok == true;
}

class _ActionBar extends StatelessWidget {
  final bool isCustom;
  final bool isEdited;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ActionBar({
    required this.isCustom,
    required this.isEdited,
    required this.onBack,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        LabTap(
          label: 'Back to Library',
          onTap: onBack,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(border: Border.all(color: AppTheme.border, width: 1)),
            child: Text('← Library',
                style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
          ),
        ),
        if (isCustom)
          Row(children: [
            LabPill(label: 'Edit', onTap: onEdit),
            const SizedBox(width: 6),
            LabPill(label: 'Delete', danger: true, onTap: onDelete),
          ])
        else
          // Built-ins are editable too (behind a warning), but can't be deleted.
          Row(children: [
            Text(
              isEdited ? 'BUILT-IN · EDITED' : 'BUILT-IN',
              style: AppTheme.sans(
                size: 10,
                color: isEdited ? AppTheme.warm : AppTheme.fgDimText,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 10),
            LabPill(label: 'Edit', onTap: onEdit),
          ]),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  final CompoundDefinition compound;
  final Color Function(String base)? colorResolver;
  const _Hero({required this.compound, this.colorResolver});

  @override
  Widget build(BuildContext context) {
    final c = compound;
    final color = colorResolver?.call(c.base) ??
        AppTheme.compoundColor(c.base) ??
        Color(c.colorValue);
    final hasEster = c.ester.trim().isNotEmpty && c.ester.toLowerCase() != 'none';
    final typeLabel = _typeUpper(c.type);
    final microlabel = hasEster ? '$typeLabel · ${c.ester.toUpperCase()}' : typeLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(width: 4, height: 22, color: color),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                microlabel,
                style: AppTheme.sans(
                  size: 11, color: AppTheme.fgMute, letterSpacing: 0.6,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (c.isCustom) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(border: Border.all(color: AppTheme.warm, width: 1)),
                child: Text(
                  'CUSTOM',
                  style: AppTheme.sans(
                    size: 9.5, color: AppTheme.warm, letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          displayName(c),
          style: AppTheme.serif(
            size: 30, weight: FontWeight.w500, color: AppTheme.fg,
            letterSpacing: -0.7, height: 1.1,
          ),
        ),
      ],
    );
  }

  String _typeUpper(CompoundType t) {
    switch (t) {
      case CompoundType.steroid: return 'STEROID';
      case CompoundType.oral: return 'ORAL';
      case CompoundType.peptide: return 'PEPTIDE';
      case CompoundType.ancillary: return 'ANCILLARY';
    }
  }
}

class _PKSection extends StatelessWidget {
  final CompoundDefinition compound;
  const _PKSection({required this.compound});

  @override
  Widget build(BuildContext context) {
    final c = compound;
    final isEvent = c.graphType == GraphType.event;
    // formatDose keeps short values readable: t½ 0.05 d was shown as "0.1"
    // and tmax 0.02 d as "0.0".
    final hl = isEvent ? '—' : formatDose(c.halfLife);
    final peak = isEvent ? '—' : formatDose(c.timeToPeak);
    final yield_ = formatDose(c.ratio * 100);
    return LibrarySection(
      title: 'Pharmacokinetics',
      child: Row(
        children: [
          Expanded(child: LabMetric(label: 'Half-life', value: hl, unit: isEvent ? null : 'd', compact: true)),
          const SizedBox(width: 6),
          Expanded(child: LabMetric(label: 'Peak', value: peak, unit: isEvent ? null : 'd', compact: true)),
          const SizedBox(width: 6),
          Expanded(child: LabMetric(label: 'Yield', value: yield_, unit: '%', compact: true)),
          const SizedBox(width: 6),
          Expanded(child: LabMetric(label: 'Unit', value: c.unit.name, compact: true)),
        ],
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  final CompoundDefinition compound;
  final List<Injection> recent;
  final int total;
  final VoidCallback onLogFirst;
  const _HistorySection({
    required this.compound,
    required this.recent,
    required this.total,
    required this.onLogFirst,
  });

  @override
  Widget build(BuildContext context) {
    return LibrarySection(
      title: 'Recent ${doseActionNoun(compound.type)}s',
      meta: total > 5 ? 'last 5 of $total' : null,
      child: recent.isEmpty ? _emptyHistory(context) : _recentList(),
    );
  }

  Widget _recentList() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        children: [
          for (var i = 0; i < recent.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, color: AppTheme.borderSoft),
            _historyRow(recent[i]),
          ],
        ],
      ),
    );
  }

  /// Date · site · dose. Date and dose take their natural single-line width
  /// ("1250 mcg" no longer wraps in a fixed 56 px column); the site fills
  /// what's left and ellipsizes, so a long site can't squeeze the date (B30).
  Widget _historyRow(Injection inj) {
    final date = _fmtDate(inj.date);
    final site = inj.site ?? '';
    final dose = '${formatDose(inj.dosage)} ${inj.snapshot.unit.name}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            date,
            maxLines: 1,
            softWrap: false,
            style: AppTheme.sans(size: 12.5, color: AppTheme.fg),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              site,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.sans(size: 11, color: AppTheme.fgMute),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            dose,
            maxLines: 1,
            softWrap: false,
            style: AppTheme.mono(size: 12, weight: FontWeight.w500, color: AppTheme.fg),
          ),
        ],
      ),
    );
  }

  Widget _emptyHistory(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 32, 18, 28),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        children: [
          Icon(Icons.add_circle_outline, size: 36, color: AppTheme.fgMute.withValues(alpha: 0.45)),
          const SizedBox(height: 14),
          Text('No ${doseActionNoun(compound.type)}s logged',
              style: AppTheme.serif(size: 17, weight: FontWeight.w500, color: AppTheme.fg)),
          const SizedBox(height: 6),
          SizedBox(
            width: 230,
            child: Text(
              'Log a dose to start tracking serum levels for ${compound.base}.',
              textAlign: TextAlign.center,
              style: AppTheme.sans(size: 12, color: AppTheme.fgMute, height: 1.5),
            ),
          ),
          const SizedBox(height: 18),
          LabTap(
            onTap: onLogFirst,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              color: AppTheme.accent,
              child: Text(
                'Log first dose',
                style: AppTheme.sans(
                  size: 12, weight: FontWeight.w600,
                  color: AppTheme.bg, letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "Sep 02 · Wed".
  String _fmtDate(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    return '${monthsShort[d.month - 1]} $day · ${weekdaysShort[d.weekday - 1]}';
  }
}

class _StickyFooter extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _StickyFooter({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: LabTap(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          color: AppTheme.accent,
          child: Center(
            child: Text(
              label,
              style: AppTheme.sans(
                size: 13, weight: FontWeight.w600,
                color: AppTheme.bg, letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
