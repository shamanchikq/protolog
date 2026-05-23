import 'package:flutter/material.dart';
import '../../models.dart';
import '../theme.dart';
import '../widgets/lab_primitives.dart';
import '../widgets/library_section.dart';
import '../widgets/protolog_shell.dart';

class CompoundEditorPage extends StatefulWidget {
  /// Null = create mode. Non-null = edit mode (preserves id + isCustom).
  final CompoundDefinition? editing;
  final void Function(ShellTab) onTabChanged;

  /// Called with the new compound on save (create mode).
  final void Function(CompoundDefinition created)? onCreate;

  /// Called with the updated compound on save (edit mode).
  final void Function(CompoundDefinition updated)? onUpdate;

  /// Called on delete (edit mode). Should also pop the page.
  final VoidCallback? onDelete;

  const CompoundEditorPage({
    super.key,
    this.editing,
    required this.onTabChanged,
    this.onCreate,
    this.onUpdate,
    this.onDelete,
  });

  @override
  State<CompoundEditorPage> createState() => _CompoundEditorPageState();
}

class _CompoundEditorPageState extends State<CompoundEditorPage> {
  late TextEditingController _name;
  late TextEditingController _ester;
  late TextEditingController _hl;
  late TextEditingController _tp;
  late TextEditingController _yld;
  late CompoundType _type;
  late GraphType _visMode;
  late Unit _unit;
  late int _colorValue;
  bool _dirty = false;

  // Swatch palette — pulled from AppTheme overrides; ordered + deduplicated.
  static const _swatches = <int>[
    0xFF5DC59C, // testosterone mint
    0xFFE0B870, // masteron gold
    0xFF5FA8E0, // primobolan blue
    0xFFD27A6B, // trenbolone coral
    0xFFC9B062, // anavar ochre
    0xFF8FC5A8, // hcg mint pastel
    0xFFB5A8E0, // boldenone lavender
    0xFF87BFE0, // nandrolone light blue
    0xFF7DD3D0, // accent teal
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _name = TextEditingController(text: e?.base ?? '');
    _ester = TextEditingController(text: e?.ester == 'None' ? '' : (e?.ester ?? ''));
    _hl = TextEditingController(text: e?.halfLife.toString() ?? '');
    _tp = TextEditingController(text: e?.timeToPeak.toString() ?? '');
    _yld = TextEditingController(text: e == null ? '100' : (e.ratio * 100).round().toString());
    _type = e?.type ?? CompoundType.steroid;
    _visMode = e?.graphType ?? GraphType.curve;
    _unit = e?.unit ?? Unit.mg;
    _colorValue = e?.colorValue ?? _swatches.first;
    for (final ctrl in [_name, _ester, _hl, _tp, _yld]) {
      ctrl.addListener(() => setState(() => _dirty = true));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _ester.dispose();
    _hl.dispose();
    _tp.dispose();
    _yld.dispose();
    super.dispose();
  }

  bool get _canSave {
    if (_name.text.trim().isEmpty) return false;
    if (_type == CompoundType.steroid && _ester.text.trim().isEmpty) return false;
    return true;
  }

  bool get _editing => widget.editing != null;
  bool get _showsVisMode =>
      _type == CompoundType.peptide || _type == CompoundType.ancillary;

  @override
  Widget build(BuildContext context) {
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
                _header(),
                const SizedBox(height: 18),
                _identitySection(),
                const SizedBox(height: 18),
                _pkSection(),
                const SizedBox(height: 18),
                _colorSection(),
              ],
            ),
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _footer(),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Library · ${_editing ? "edit" : "new"}',
                  style: AppTheme.sans(size: 11, color: AppTheme.fgDim)),
              const SizedBox(height: 4),
              Text(
                _editing ? 'Edit compound' : 'Custom compound',
                style: AppTheme.serif(
                  size: 22, weight: FontWeight.w500,
                  color: AppTheme.fg, letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => _cancel(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(border: Border.all(color: AppTheme.border, width: 1)),
            child: Text('Cancel', style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
          ),
        ),
      ],
    );
  }

  Future<void> _cancel() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        title: Text('Discard changes?',
            style: AppTheme.sans(size: 14, weight: FontWeight.w600, color: AppTheme.fg)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Keep editing',
                style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Discard',
                style: AppTheme.sans(
                  size: 12, weight: FontWeight.w600, color: AppTheme.warn,
                )),
          ),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  Widget _identitySection() {
    final needsEster = _type == CompoundType.steroid;
    return LibrarySection(
      title: 'Identity',
      child: Column(
        children: [
          LabField(
            label: 'Base name',
            hint: 'required',
            focused: true,
            child: TextField(
              controller: _name,
              style: AppTheme.serif(size: 22, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.4),
              decoration: const InputDecoration(
                isDense: true, border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 8),
          LabField(
            label: 'Ester',
            disabled: !needsEster,
            hint: needsEster ? null : 'steroids only',
            child: needsEster
                ? TextField(
                    controller: _ester,
                    style: AppTheme.serif(size: 18, weight: FontWeight.w500, color: AppTheme.fg),
                    decoration: const InputDecoration(
                      isDense: true, border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                : Text('—',
                    style: AppTheme.serif(size: 18, weight: FontWeight.w500, color: AppTheme.fgDim)),
          ),
          const SizedBox(height: 8),
          _label('Type'),
          const SizedBox(height: 6),
          LabSegmented<CompoundType>(
            value: _type,
            options: CompoundType.values,
            labelFor: (t) {
              switch (t) {
                case CompoundType.steroid: return 'Steroid';
                case CompoundType.oral: return 'Oral';
                case CompoundType.peptide: return 'Peptide';
                case CompoundType.ancillary: return 'Ancillary';
              }
            },
            onChange: (t) => setState(() {
              _type = t;
              _dirty = true;
              if (t == CompoundType.steroid || t == CompoundType.oral) {
                _visMode = GraphType.curve;
              }
            }),
          ),
          if (_showsVisMode) ...[
            const SizedBox(height: 8),
            _label('Visual mode'),
            const SizedBox(height: 6),
            LabSegmented<GraphType>(
              value: _visMode,
              options: const [GraphType.curve, GraphType.activeWindow, GraphType.event],
              labelFor: (g) {
                switch (g) {
                  case GraphType.curve: return 'Curve';
                  case GraphType.activeWindow: return 'Window';
                  case GraphType.event: return 'Event';
                }
              },
              onChange: (g) => setState(() { _visMode = g; _dirty = true; }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pkSection() {
    return LibrarySection(
      title: 'Pharmacokinetics',
      child: Column(
        children: [
          Row(children: [
            Expanded(child: _numField(label: 'Half-life', suffix: 'd', controller: _hl)),
            const SizedBox(width: 8),
            Expanded(child: _numField(label: 'Time to peak', suffix: 'd', controller: _tp)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _numField(label: 'Yield', suffix: '%', controller: _yld, hint: 'bioavailability')),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Dose unit'),
                  const SizedBox(height: 6),
                  LabSegmented<Unit>(
                    value: _unit,
                    options: Unit.values,
                    mono: true,
                    labelFor: (u) {
                      switch (u) {
                        case Unit.mg: return 'mg';
                        case Unit.mcg: return 'mcg';
                        case Unit.iu: return 'IU';
                      }
                    },
                    onChange: (u) => setState(() { _unit = u; _dirty = true; }),
                  ),
                ],
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _numField({
    required String label,
    required String suffix,
    required TextEditingController controller,
    String? hint,
  }) {
    return LabField(
      label: label,
      hint: hint ?? suffix,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppTheme.serif(size: 22, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.4),
              decoration: const InputDecoration(
                isDense: true, border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(suffix, style: AppTheme.sans(size: 11, color: AppTheme.fgMute)),
        ],
      ),
    );
  }

  Widget _colorSection() {
    return LibrarySection(
      title: 'Lane color',
      meta: 'for the swimlane + calendar dots',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final hex in _swatches)
            GestureDetector(
              onTap: () => setState(() { _colorValue = hex; _dirty = true; }),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Color(hex),
                  border: Border.all(
                    color: _colorValue == hex ? AppTheme.fg : AppTheme.border,
                    width: _colorValue == hex ? 2 : 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text.toUpperCase(),
      style: AppTheme.sans(size: 9.5, color: AppTheme.fgDim, letterSpacing: 0.9),
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: Row(
        children: [
          if (_editing) ...[
            GestureDetector(
              onTap: widget.onDelete,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(border: Border.all(color: AppTheme.warn, width: 1)),
                child: Text(
                  'Delete',
                  style: AppTheme.sans(
                    size: 13, weight: FontWeight.w600,
                    color: AppTheme.warn, letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: GestureDetector(
              onTap: _canSave ? _save : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _canSave ? AppTheme.accent : AppTheme.surface2,
                  border: Border.all(
                    color: _canSave ? AppTheme.accent : AppTheme.border, width: 1,
                  ),
                ),
                child: Center(
                  child: Opacity(
                    opacity: _canSave ? 1 : 0.7,
                    child: Text(
                      _editing ? 'Save changes' : 'Add to library',
                      style: AppTheme.sans(
                        size: 13, weight: FontWeight.w600,
                        color: _canSave ? AppTheme.bg : AppTheme.fgDim,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    final name = _name.text.trim();
    final esterText = _ester.text.trim();
    final ester = (_type == CompoundType.steroid && esterText.isNotEmpty)
        ? esterText
        : 'None';
    final halfLife = double.tryParse(_hl.text) ?? 0;
    final timeToPeak = double.tryParse(_tp.text) ?? 0;
    final ratio = (double.tryParse(_yld.text) ?? 100) / 100;
    final graphType = (_type == CompoundType.steroid || _type == CompoundType.oral)
        ? GraphType.curve
        : _visMode;

    if (_editing) {
      final updated = widget.editing!.copyWith(
        base: name, ester: ester, type: _type, graphType: graphType,
        halfLife: halfLife, timeToPeak: timeToPeak, ratio: ratio,
        unit: _unit, colorValue: _colorValue,
      );
      widget.onUpdate?.call(updated);
      Navigator.of(context).pop(updated);
    } else {
      final created = CompoundDefinition(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        base: name, ester: ester, type: _type, graphType: graphType,
        halfLife: halfLife, timeToPeak: timeToPeak, ratio: ratio,
        unit: _unit, colorValue: _colorValue, isCustom: true,
      );
      widget.onCreate?.call(created);
      Navigator.of(context).pop(created);
    }
  }
}
