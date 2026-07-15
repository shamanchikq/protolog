import 'package:flutter/material.dart';
import '../../models.dart';
import '../../utils.dart';
import '../theme.dart';
import 'lab_primitives.dart';

/// What the dialog pops with: a saved entry, or a delete request.
class BloodworkDialogResult {
  final BloodworkEntry? entry;
  final bool delete;
  const BloodworkDialogResult.saved(this.entry) : delete = false;
  const BloodworkDialogResult.deleted() : entry = null, delete = true;
}

/// Create/edit dialog for a lab result (F6), styled like the compound
/// editor (LabField inputs, sharp-cornered Dialog, bordered actions).
/// Owns its text controllers so they outlive the route's exit animation.
class BloodworkEditorDialog extends StatefulWidget {
  final BloodworkEntry? editing;

  /// marker name → conventional unit; tapping a chip prefills both fields.
  final Map<String, String> markerSuggestions;

  const BloodworkEditorDialog({
    super.key,
    this.editing,
    this.markerSuggestions = const {},
  });

  @override
  State<BloodworkEditorDialog> createState() => _BloodworkEditorDialogState();
}

class _BloodworkEditorDialogState extends State<BloodworkEditorDialog> {
  late final TextEditingController _marker = TextEditingController(
    text: widget.editing?.marker ?? '',
  );
  late final TextEditingController _value = TextEditingController(
    text: widget.editing != null ? _fmt(widget.editing!.value) : '',
  );
  late final TextEditingController _unit = TextEditingController(
    text: widget.editing?.unit ?? '',
  );
  late DateTime _date = widget.editing?.date ?? DateTime.now();

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _marker.dispose();
    _value.dispose();
    _unit.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _marker.text.trim().isNotEmpty &&
      (parseFlexibleDouble(_value.text) ?? 0) > 0;

  static const _fieldDecoration = InputDecoration(
    isDense: true,
    border: InputBorder.none,
    contentPadding: EdgeInsets.zero,
  );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _save() {
    final entry = BloodworkEntry(
      id:
          widget.editing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime(_date.year, _date.month, _date.day),
      marker: _marker.text.trim(),
      value: parseFlexibleDouble(_value.text)!,
      unit: _unit.text.trim(),
      notes: widget.editing?.notes,
    );
    Navigator.of(context).pop(BloodworkDialogResult.saved(entry));
  }

  Widget _button(
    String label, {
    required Color color,
    bool filled = false,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: filled && enabled ? color : Colors.transparent,
          border: Border.all(
            color: enabled ? color : AppTheme.border,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.sans(
            size: 12,
            weight: FontWeight.w600,
            letterSpacing: 0.2,
            color: !enabled
                ? AppTheme.fgDim
                : filled
                ? AppTheme.bg
                : color,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.border, width: 1),
        borderRadius: BorderRadius.zero,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.editing == null ? 'Add lab result' : 'Edit lab result',
                style: AppTheme.serif(
                  size: 20,
                  weight: FontWeight.w500,
                  color: AppTheme.fg,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in widget.markerSuggestions.entries)
                    LabPill(
                      label: e.key,
                      active: _marker.text == e.key,
                      onTap: () => setState(() {
                        _marker.text = e.key;
                        if (_unit.text.trim().isEmpty) _unit.text = e.value;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              LabField(
                label: 'Marker',
                child: TextField(
                  key: const Key('bloodwork-marker'),
                  controller: _marker,
                  onChanged: (_) => setState(() {}),
                  style: AppTheme.serif(
                    size: 18,
                    weight: FontWeight.w500,
                    color: AppTheme.fg,
                  ),
                  decoration: _fieldDecoration,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: LabField(
                      label: 'Value',
                      child: TextField(
                        key: const Key('bloodwork-value'),
                        controller: _value,
                        onChanged: (_) => setState(() {}),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: AppTheme.mono(size: 16, color: AppTheme.fg),
                        decoration: _fieldDecoration,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LabField(
                      label: 'Unit',
                      child: TextField(
                        key: const Key('bloodwork-unit'),
                        controller: _unit,
                        style: AppTheme.sans(size: 14, color: AppTheme.fg),
                        decoration: _fieldDecoration,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LabField(
                label: 'Drawn',
                hint: 'tap to change',
                onTap: _pickDate,
                child: Text(
                  formatDate(_date, 'yyyy-MM-dd'),
                  style: AppTheme.mono(size: 14, color: AppTheme.fg),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (widget.editing != null)
                    _button(
                      'Delete',
                      color: AppTheme.warn,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(const BloodworkDialogResult.deleted()),
                    ),
                  const Spacer(),
                  _button(
                    'Cancel',
                    color: AppTheme.fgMute,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  _button(
                    'Save',
                    color: AppTheme.accent,
                    filled: true,
                    onTap: _canSave ? _save : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
