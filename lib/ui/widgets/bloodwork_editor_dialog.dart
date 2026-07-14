import 'package:flutter/material.dart';
import '../../models.dart';
import '../../utils.dart';
import '../theme.dart';

/// What the dialog pops with: a saved entry, or a delete request.
class BloodworkDialogResult {
  final BloodworkEntry? entry;
  final bool delete;
  const BloodworkDialogResult.saved(this.entry) : delete = false;
  const BloodworkDialogResult.deleted()
      : entry = null,
        delete = true;
}

/// Create/edit dialog for a lab result (F6). Owns its text controllers so
/// they outlive the route's exit animation (disposing them in the caller
/// right after showDialog returns crashes the framework mid-transition).
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
  late final TextEditingController _marker =
      TextEditingController(text: widget.editing?.marker ?? '');
  late final TextEditingController _value = TextEditingController(
      text: widget.editing != null ? _fmt(widget.editing!.value) : '');
  late final TextEditingController _unit =
      TextEditingController(text: widget.editing?.unit ?? '');
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

  InputDecoration _deco(String label) => InputDecoration(
        labelText: label,
        labelStyle: AppTheme.sans(size: 11, color: AppTheme.fgDim),
        enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppTheme.border)),
        focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppTheme.accent)),
      );

  void _save() {
    final entry = BloodworkEntry(
      id: widget.editing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime(_date.year, _date.month, _date.day),
      marker: _marker.text.trim(),
      value: parseFlexibleDouble(_value.text)!,
      unit: _unit.text.trim(),
      notes: widget.editing?.notes,
    );
    Navigator.of(context).pop(BloodworkDialogResult.saved(entry));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface2,
      title: Text(widget.editing == null ? 'Add lab result' : 'Edit lab result',
          style: AppTheme.sans(size: 14, weight: FontWeight.w600, color: AppTheme.fg)),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in widget.markerSuggestions.entries)
                  GestureDetector(
                    onTap: () => setState(() {
                      _marker.text = e.key;
                      if (_unit.text.trim().isEmpty) _unit.text = e.value;
                    }),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          border: Border.all(
                              color: _marker.text == e.key
                                  ? AppTheme.accentDeep
                                  : AppTheme.border,
                              width: 1)),
                      child: Text(e.key,
                          style: AppTheme.sans(
                              size: 10,
                              color: _marker.text == e.key
                                  ? AppTheme.accent
                                  : AppTheme.fgMute)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _marker,
              onChanged: (_) => setState(() {}),
              style: AppTheme.sans(size: 13, color: AppTheme.fg),
              decoration: _deco('Marker'),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _value,
                    onChanged: (_) => setState(() {}),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: AppTheme.mono(size: 13, color: AppTheme.fg),
                    decoration: _deco('Value'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _unit,
                    style: AppTheme.sans(size: 13, color: AppTheme.fg),
                    decoration: _deco('Unit'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked != null) setState(() => _date = picked);
              },
              child: Text(
                'Drawn: ${formatDate(_date, 'yyyy-MM-dd')}  (tap to change)',
                style: AppTheme.sans(size: 12, color: AppTheme.accent),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.editing != null)
          TextButton(
            onPressed: () => Navigator.of(context)
                .pop(const BloodworkDialogResult.deleted()),
            child: Text('Delete',
                style: AppTheme.sans(size: 12, color: AppTheme.warn)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
        ),
        TextButton(
          onPressed: _canSave ? _save : null,
          child: Text('Save',
              style: AppTheme.sans(
                  size: 12,
                  weight: FontWeight.w600,
                  color: _canSave ? AppTheme.accent : AppTheme.fgDim)),
        ),
      ],
    );
  }
}
