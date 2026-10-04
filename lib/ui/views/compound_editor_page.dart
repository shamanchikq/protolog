import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../models.dart';
import '../../engine/compute_engine.dart' show blendComponentsFor;
import '../../engine/dose_math.dart' show doseUnitOptions;
import '../../engine/library_stats.dart';
import '../../utils.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/lab_primitives.dart';
import '../widgets/library_section.dart';
import '../widgets/protolog_shell.dart';
import 'compound_detail_page.dart' show confirmDeleteCompound;

/// Upper bounds for typed PK values (N5). Huge finite input ("1e308") parses
/// fine but overflows chart scaling; these are generous for any real
/// compound (the longest built-in t½ is 35 d).
const double _kMaxHalfLifeDays = 365;
const double _kMaxTimeToPeakDays = 60;

class CompoundEditorPage extends StatefulWidget {
  /// Null = create mode. Non-null = edit mode (preserves id + isCustom).
  final CompoundDefinition? editing;
  final void Function(ShellTab) onTabChanged;

  /// Called with the new compound on save (create mode).
  final void Function(CompoundDefinition created)? onCreate;

  /// Called with the updated compound on save (edit mode).
  final void Function(CompoundDefinition updated)? onUpdate;

  /// Called on delete (edit mode), after the user confirms. Should remove
  /// the compound and its linked reminders, and pop the page.
  final VoidCallback? onDelete;

  /// Logs (injections) recorded for [editing]'s base+ester. Logs, protocol
  /// membership and reminders all match a compound by base+ester, so a
  /// custom that has any keeps its name, ester and type locked (B10).
  final int logCount;

  /// Reminders for [editing]'s base+ester. They also lock a custom's
  /// identity, and the delete confirmation says they'll be removed.
  final int linkedReminderCount;

  /// The stored user compounds; with BASE_LIBRARY they form the catalogue a
  /// new or renamed custom must not collide with (one compound per
  /// base+ester).
  final List<CompoundDefinition> userCompounds;

  const CompoundEditorPage({
    super.key,
    this.editing,
    required this.onTabChanged,
    this.onCreate,
    this.onUpdate,
    this.onDelete,
    this.logCount = 0,
    this.linkedReminderCount = 0,
    this.userCompounds = const [],
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
  late final String _initialYieldText;
  late CompoundType _type;
  late GraphType _visMode;
  late Unit _unit;
  late int _colorValue;

  /// Source of a blend's stored PK (see [_blendPk]): the compound being
  /// edited, or its library default after Reset; null when creating.
  CompoundDefinition? _blendPkSource;

  /// Values the editor opened with (after legacy coercions), so only a real
  /// change counts as unsaved — not merely focusing or tapping a field.
  late final ({
    String name,
    String ester,
    String halfLife,
    String timeToPeak,
    String yield,
    CompoundType type,
    GraphType visMode,
    Unit unit,
    int color,
  }) _initial;

  /// True when any value differs from what the editor opened with. Numbers
  /// compare by value ("4.5" = "4,5"), names ignore surrounding spaces —
  /// the same normalisation Save applies (B25).
  bool get _dirty {
    final i = _initial;
    return _name.text.trim() != i.name ||
        _ester.text.trim() != i.ester ||
        _numberChanged(_hl.text, i.halfLife) ||
        _numberChanged(_tp.text, i.timeToPeak) ||
        _numberChanged(_yld.text, i.yield) ||
        _type != i.type ||
        _visMode != i.visMode ||
        _unit != i.unit ||
        _colorValue != i.color;
  }

  static bool _numberChanged(String now, String initial) {
    if (now.trim() == initial.trim()) return false;
    final a = parseFlexibleDouble(now);
    final b = parseFlexibleDouble(initial);
    return a == null || b == null || a != b;
  }

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
    _yld = TextEditingController(text: e == null ? '100' : _yieldText(e.ratio));
    _initialYieldText = _yld.text;
    _type = e?.type ?? CompoundType.steroid;
    _visMode = e?.graphType ?? GraphType.curve;
    // The visual-mode control omits Curve for peptides/ancillaries; coerce so
    // its `value` is always one of the offered options.
    if ((_type == CompoundType.peptide || _type == CompoundType.ancillary) &&
        _visMode == GraphType.curve) {
      _visMode = GraphType.activeWindow;
    }
    _unit = e?.unit ?? Unit.mg;
    // A legacy record can hold a unit that is no longer offered (HCG stored
    // as mg); show — and save — the native unit instead.
    final native = _nativeUnit;
    if (native != null && !_unitOptions.contains(_unit)) _unit = native;
    _colorValue = e?.colorValue ?? _swatches.first;
    _blendPkSource = e;
    _initial = (
      name: _name.text.trim(),
      ester: _ester.text.trim(),
      halfLife: _hl.text,
      timeToPeak: _tp.text,
      yield: _yld.text,
      type: _type,
      visMode: _visMode,
      unit: _unit,
      color: _colorValue,
    );
    // Rebuild on edits: validation, the clash check and PopScope.canPop all
    // read the fields. (These also fire on selection changes — harmless now
    // that "dirty" compares values.)
    for (final ctrl in [_name, _ester, _hl, _tp, _yld]) {
      ctrl.addListener(() => setState(() {}));
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

  /// Yield as a ratio (0 < r ≤ 1), or null when the field is empty, not a
  /// number, or outside 0 < yield ≤ 100 %. A 0 % yield flattens the curve;
  /// more than 100 % invents drug.
  double? get _ratio {
    final y = parseFlexibleDouble(_yld.text);
    if (y == null || y <= 0 || y > 100) return null;
    // Untouched field: keep the stored ratio exactly. The displayed
    // percentage is formatted, so re-parsing it could nudge the value and
    // make an unchanged compound look PK-edited.
    final e = widget.editing;
    if (e != null && _yld.text == _initialYieldText) return e.ratio;
    return y / 100;
  }

  static String _yieldText(double ratio) => formatDose(ratio * 100);

  /// Half-life in days, or null unless 0 < t½ ≤ [_kMaxHalfLifeDays]. A
  /// non-positive half-life has no elimination rate (ke = ln2/0).
  double? get _halfLife {
    final v = parseFlexibleDouble(_hl.text);
    if (v == null || v <= 0 || v > _kMaxHalfLifeDays) return null;
    return v;
  }

  /// Time to peak in days (empty = 0, instant absorption), or null when not
  /// a number, outside 0 ≤ tmax ≤ [_kMaxTimeToPeakDays], or unreachable for
  /// the half-life (see [_maxReachableTimeToPeak]).
  double? get _timeToPeak {
    if (_tp.text.trim().isEmpty) return 0;
    final v = parseFlexibleDouble(_tp.text);
    if (v == null || v < 0 || v > _kMaxTimeToPeakDays) return null;
    final hl = _halfLife;
    if (hl != null && v >= _maxReachableTimeToPeak(hl)) return null;
    return v;
  }

  /// The Bateman peak time ln(ka/ke)/(ka−ke) only approaches 1/ke = t½/ln 2
  /// as ka → ke, and the engine's ka solver searches ka > ke — so a tmax at
  /// or past t½/ln 2 can't be modelled (the curve would silently peak
  /// earlier than entered).
  static double _maxReachableTimeToPeak(double halfLife) => halfLife / math.ln2;

  /// The ester as it will be saved: the locked one for built-ins, otherwise
  /// the typed one (steroids only — everything else stores 'None').
  String get _effectiveEster {
    if (_identityLocked) return widget.editing!.ester;
    final typed = _ester.text.trim();
    return (_type == CompoundType.steroid && typed.isNotEmpty) ? typed : 'None';
  }

  /// Components of a blend ester (Sustanon / Tri-Tren), else null. The engine
  /// models a blend from these and ignores the compound's own t½ / tmax /
  /// yield, so the editor shows those read-only instead of offering edits
  /// (and an "apply to past logs") that change nothing (B9).
  List<Map<String, double>>? get _blend => blendComponentsFor(_effectiveEster);
  bool get _isBlend => _blend != null;

  /// What a blend stores as its (display-only) PK. Edits keep the values
  /// they opened with, so saving a blend never reports a PK change — except
  /// after Reset to default, which restores the library values (only differs
  /// for an override edited before blends were locked). A new blend custom
  /// takes its longest-lasting component's values.
  ({double halfLife, double timeToPeak, double ratio}) get _blendPk {
    final src = _blendPkSource;
    if (src != null) {
      return (halfLife: src.halfLife, timeToPeak: src.timeToPeak, ratio: src.ratio);
    }
    final longest =
        _blend!.reduce((a, b) => b['halfLife']! > a['halfLife']! ? b : a);
    return (
      halfLife: longest['halfLife']!,
      timeToPeak: longest['timeToPeak']!,
      ratio: longest['ratio']!,
    );
  }

  /// Inline messages for PK input that is present but invalid. Empty fields
  /// only block Save — no message before the user has typed anything.
  List<String> get _pkMessages {
    if (_isBlend) return const [];
    final hl = _halfLife;
    final tpText = _tp.text.trim();
    final tp = tpText.isEmpty ? 0.0 : parseFlexibleDouble(tpText);
    return [
      if (_hl.text.trim().isNotEmpty && hl == null)
        'Half-life must be more than 0 and at most '
            '${formatDose(_kMaxHalfLifeDays)} d.',
      if (tp == null || tp < 0 || tp > _kMaxTimeToPeakDays)
        'Time to peak must be between 0 and '
            '${formatDose(_kMaxTimeToPeakDays)} d.'
      else if (hl != null && tp >= _maxReachableTimeToPeak(hl))
        // Floored so every value the message allows really is accepted.
        'Time to peak must be under '
            '${formatDose((_maxReachableTimeToPeak(hl) * 1000).floor() / 1000)} d '
            '(half-life ÷ ln 2) — the model can’t peak any later.',
      if (_yld.text.trim().isNotEmpty && _ratio == null)
        'Yield must be more than 0 and at most 100 %.',
    ];
  }

  bool get _canSave {
    if (!_isBlend &&
        (_halfLife == null || _timeToPeak == null || _ratio == null)) {
      return false;
    }
    // A locked identity is the stored one, so it is always valid.
    if (_identityLocked) return true;
    if (_name.text.trim().isEmpty) return false;
    if (_type == CompoundType.steroid && _ester.text.trim().isEmpty) return false;
    if (_clash != null) return false;
    return true;
  }

  /// The catalogue entry (built-in or user compound) a new or renamed
  /// custom would collide with, or null. Compared on the trimmed
  /// base+ester key ignoring case — "testosterone enanthate" would read as
  /// the built-in everywhere. The compound being edited doesn't clash with
  /// itself.
  CompoundDefinition? get _clash {
    if (_identityLocked) return null;
    final base = _name.text.trim();
    if (base.isEmpty) return null;
    final key = compoundKey(base, _effectiveEster).toLowerCase();
    final ownKey = _editing ? keyOf(widget.editing!) : null;
    for (final c in cataloguedCompounds(userCompounds: widget.userCompounds)) {
      final k = keyOf(c);
      if (k == ownKey) continue;
      if (k.toLowerCase() == key) return c;
    }
    return null;
  }

  /// The unit the compound is natively dosed in: the library's for a
  /// built-in, the stored one for a custom. Null when creating — a new
  /// compound defines its native unit.
  Unit? get _nativeUnit {
    final e = widget.editing;
    if (e == null) return null;
    return (e.isCustom ? null : defaultDefFor(e)?.unit) ?? e.unit;
  }

  /// Dose units offered: the wizard's rule ([doseUnitOptions] of the native
  /// unit — IU-only for IU-native, mg/mcg otherwise), so the preferred unit
  /// picked here is always one the wizard honours (N3).
  List<Unit> get _unitOptions {
    final native = _nativeUnit;
    return native == null ? Unit.values : doseUnitOptions(native);
  }

  bool get _editing => widget.editing != null;
  bool get _showsVisMode =>
      _type == CompoundType.peptide || _type == CompoundType.ancillary;
  // Editing a built-in (library) compound: identity is locked, a warning banner
  // shows, and the footer offers Reset to default instead of Delete.
  bool get _isBuiltInEdit => _editing && !widget.editing!.isCustom;

  /// A custom that logs or reminders point at (by base+ester): renaming or
  /// retyping it would silently detach them, so its identity is locked.
  bool get _isInUseCustom =>
      _editing &&
      widget.editing!.isCustom &&
      (widget.logCount > 0 || widget.linkedReminderCount > 0);

  /// Name, ester and type can't be edited (built-in, or custom in use).
  bool get _identityLocked => _isBuiltInEdit || _isInUseCustom;

  /// "3 logs and 1 reminder refer to this compound…" for [_isInUseCustom].
  String get _inUseLockReason {
    String n(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';
    final parts = [
      if (widget.logCount > 0) n(widget.logCount, 'log'),
      if (widget.linkedReminderCount > 0) n(widget.linkedReminderCount, 'reminder'),
    ];
    final total = widget.logCount + widget.linkedReminderCount;
    return '${parts.join(' and ')} ${total == 1 ? 'refers' : 'refer'} to this '
        'compound by its name, ester and type, so they’re locked — changing '
        'them would detach that history.';
  }

  @override
  Widget build(BuildContext context) {
    // System back / the back gesture would otherwise drop unsaved edits
    // without the "Discard changes?" prompt Cancel shows (B25). Save, Delete
    // and Discard leave via Navigator.pop, which PopScope doesn't block.
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: _shell(),
    );
  }

  Widget _shell() {
    return ProtoLogShell(
      activeTab: ShellTab.library,
      // popUntil bypasses PopScope, so tab switches ask explicitly.
      onTabChanged: (t) async {
        if (!await _confirmLeave() || !mounted) return;
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
                if (_isBuiltInEdit) ...[
                  _warningBanner(),
                  const SizedBox(height: 18),
                ],
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
              Text(
                  _isBuiltInEdit
                      ? 'Library · built-in'
                      : 'Library · ${_editing ? "edit" : "new"}',
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

  /// Cancel, system back and the back gesture all land here.
  Future<void> _cancel() async {
    if (await _confirmLeave() && mounted) Navigator.of(context).pop();
  }

  /// True when it's fine to leave the editor: nothing changed, or the user
  /// chose Discard.
  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        title: Text('Discard changes?',
            style: AppTheme.sans(size: 14, weight: FontWeight.w600, color: AppTheme.fg)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep editing',
                style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Discard',
                style: AppTheme.sans(
                  size: 12, weight: FontWeight.w600, color: AppTheme.warn,
                )),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Widget _identitySection() {
    if (_identityLocked) return _lockedIdentitySection();
    final needsEster = _type == CompoundType.steroid;
    final clash = _clash;
    return LibrarySection(
      title: 'Identity',
      child: Column(
        children: [
          LabField(
            label: 'Base name',
            hint: 'required',
            focused: true,
            child: TextField(
              key: const ValueKey('compound-editor-name'),
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
                    key: const ValueKey('compound-editor-ester'),
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
          if (clash != null) ...[
            const SizedBox(height: 8),
            _validationNote(
              '${displayName(clash)} is already in the library — '
              'choose a different name${needsEster ? ' or ester' : ''}.',
            ),
          ],
          const SizedBox(height: 8),
          _label('Type'),
          const SizedBox(height: 6),
          LabSegmented<CompoundType>(
            value: _type,
            options: CompoundType.values,
            labelFor: _typeLabel,
            onChange: (t) => setState(() {
              _type = t;
              if (t == CompoundType.steroid || t == CompoundType.oral) {
                _visMode = GraphType.curve;
              } else if (_visMode == GraphType.curve) {
                // Curve isn't offered for peptides/ancillaries — default to window.
                _visMode = GraphType.activeWindow;
              }
            }),
          ),
          ..._visModeBlock(),
        ],
      ),
    );
  }

  /// Read-only identity for built-ins: name, ester, and type are fixed; only
  /// the visual-mode toggle (for peptides/ancillaries) stays editable.
  Widget _lockedIdentitySection() {
    final e = widget.editing!;
    final hasEster =
        e.ester.trim().isNotEmpty && e.ester.toLowerCase() != 'none';
    final hint = _isBuiltInEdit ? 'built-in' : 'in use';
    return LibrarySection(
      title: 'Identity',
      meta: 'locked',
      child: Column(
        children: [
          if (!_isBuiltInEdit) ...[
            SizedBox(
              width: double.infinity,
              child: Text(
                _inUseLockReason,
                style: AppTheme.sans(size: 11, color: AppTheme.fgMute, height: 1.4),
              ),
            ),
            const SizedBox(height: 8),
          ],
          LabField(
            label: 'Base name',
            hint: hint,
            child: Text(e.base,
                style: AppTheme.serif(
                    size: 22, weight: FontWeight.w500,
                    color: AppTheme.fgMute, letterSpacing: -0.4)),
          ),
          const SizedBox(height: 8),
          LabField(
            label: 'Ester',
            hint: hint,
            child: Text(hasEster ? e.ester : '—',
                style: AppTheme.serif(
                    size: 18, weight: FontWeight.w500, color: AppTheme.fgMute)),
          ),
          const SizedBox(height: 8),
          _label('Type'),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(border: Border.all(color: AppTheme.border, width: 1)),
            child: Text(_typeLabel(e.type),
                style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
          ),
          ..._visModeBlock(),
        ],
      ),
    );
  }

  List<Widget> _visModeBlock() {
    if (!_showsVisMode) return const [];
    return [
      const SizedBox(height: 8),
      _label('Visual mode'),
      const SizedBox(height: 6),
      LabSegmented<GraphType>(
        value: _visMode,
        // Peptides/ancillaries are never modeled as release curves — only
        // window (Bateman gradient) or event (dose markers).
        options: const [GraphType.activeWindow, GraphType.event],
        labelFor: (g) {
          switch (g) {
            case GraphType.curve: return 'Curve';
            case GraphType.activeWindow: return 'Window';
            case GraphType.event: return 'Event';
          }
        },
        onChange: (g) => setState(() => _visMode = g),
      ),
    ];
  }

  String _typeLabel(CompoundType t) {
    switch (t) {
      case CompoundType.steroid: return 'Steroid';
      case CompoundType.oral: return 'Oral';
      case CompoundType.peptide: return 'Peptide';
      case CompoundType.ancillary: return 'Ancillary';
    }
  }

  Widget _warningBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.warn.withValues(alpha: 0.08),
        border: Border.all(color: AppTheme.warn.withValues(alpha: 0.55), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: AppTheme.warn),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Editing a built-in’s pharmacokinetics isn’t recommended unless '
              'you’re certain of the values. You can reset to default anytime.',
              style: AppTheme.sans(size: 11.5, color: AppTheme.warn, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pkSection() {
    final blend = _blend;
    final blendPk = blend != null ? _blendPk : null;
    return LibrarySection(
      title: 'Pharmacokinetics',
      meta: blend != null ? 'blend' : null,
      child: Column(
        children: [
          Row(children: [
            Expanded(
              child: blendPk != null
                  ? _readOnlyField(label: 'Half-life', suffix: 'd', value: blendPk.halfLife)
                  : _numField(label: 'Half-life', suffix: 'd', controller: _hl, fieldKey: 'half-life'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: blendPk != null
                  ? _readOnlyField(label: 'Time to peak', suffix: 'd', value: blendPk.timeToPeak)
                  : _numField(label: 'Time to peak', suffix: 'd', controller: _tp, fieldKey: 'time-to-peak'),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: blendPk != null
                  ? _readOnlyField(label: 'Yield', suffix: '%', value: blendPk.ratio * 100)
                  : _numField(label: 'Yield', suffix: '%', controller: _yld, hint: 'bioavailability', fieldKey: 'yield'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Dose unit'),
                  const SizedBox(height: 6),
                  LabSegmented<Unit>(
                    value: _unit,
                    options: _unitOptions,
                    mono: true,
                    labelFor: (u) {
                      switch (u) {
                        case Unit.mg: return 'mg';
                        case Unit.mcg: return 'mcg';
                        case Unit.iu: return 'IU';
                      }
                    },
                    onChange: (u) => setState(() => _unit = u),
                  ),
                ],
              ),
            ),
          ]),
          if (blend != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: Text(
                'Modelled from its ${blend.length} component esters — '
                'half-life, time to peak and yield above aren’t used.',
                style: AppTheme.sans(size: 11, color: AppTheme.fgMute, height: 1.4),
              ),
            ),
          ],
          for (final m in _pkMessages) ...[
            const SizedBox(height: 8),
            _validationNote(m),
          ],
        ],
      ),
    );
  }

  /// A PK value shown but not editable (blends).
  Widget _readOnlyField({
    required String label,
    required String suffix,
    required double value,
  }) {
    return LabField(
      label: label,
      hint: 'fixed',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              formatDose(value),
              style: AppTheme.serif(
                size: 22, weight: FontWeight.w500,
                color: AppTheme.fgMute, letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(suffix, style: AppTheme.sans(size: 11, color: AppTheme.fgDim)),
        ],
      ),
    );
  }

  /// Inline validation message (warn color) under a section's fields.
  Widget _validationNote(String text) {
    return SizedBox(
      width: double.infinity,
      child: Text(
        text,
        style: AppTheme.sans(size: 11, color: AppTheme.warn, height: 1.4),
      ),
    );
  }

  Widget _numField({
    required String label,
    required String suffix,
    required TextEditingController controller,
    required String fieldKey,
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
              key: ValueKey('compound-editor-$fieldKey'),
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
              onTap: () => setState(() => _colorValue = hex),
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
          if (_isBuiltInEdit) ...[
            GestureDetector(
              onTap: _resetToDefault,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(border: Border.all(color: AppTheme.border, width: 1)),
                child: Text(
                  'Reset to default',
                  style: AppTheme.sans(
                    size: 13, weight: FontWeight.w600,
                    color: AppTheme.fgMute, letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ] else if (_editing) ...[
            GestureDetector(
              onTap: widget.onDelete == null ? null : _confirmDelete,
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

  /// Repopulate the PK fields + color (+ visual mode) from the BASE_LIBRARY
  /// default. The user reviews and Saves to persist; if the saved values equal
  /// the default, the compound reads as un-edited again.
  void _resetToDefault() {
    final def = defaultDefFor(widget.editing!);
    if (def == null) return;
    setState(() {
      _hl.text = def.halfLife.toString();
      _tp.text = def.timeToPeak.toString();
      _yld.text = _yieldText(def.ratio);
      _unit = def.unit;
      _colorValue = def.colorValue;
      if (_showsVisMode) _visMode = def.graphType;
      _blendPkSource = def;
    });
  }

  /// Same confirmation as the detail page's Delete; [CompoundEditorPage.onDelete]
  /// runs only once the user confirms.
  Future<void> _confirmDelete() async {
    final ok = await confirmDeleteCompound(
      context,
      compound: widget.editing!,
      logCount: widget.logCount,
      linkedReminderCount: widget.linkedReminderCount,
    );
    if (ok && mounted) widget.onDelete?.call();
  }

  void _save() {
    // A locked identity is saved exactly as stored.
    final locked = _identityLocked ? widget.editing! : null;
    final name = locked?.base ?? _name.text.trim();
    final ester = _effectiveEster;
    final type = locked?.type ?? _type;
    // _canSave guarantees valid PK values; blends store theirs untouched.
    final blendPk = _isBlend ? _blendPk : null;
    final halfLife = blendPk?.halfLife ?? _halfLife!;
    final timeToPeak = blendPk?.timeToPeak ?? _timeToPeak!;
    final ratio = blendPk?.ratio ?? _ratio!;
    final graphType = (type == CompoundType.steroid || type == CompoundType.oral)
        ? GraphType.curve
        : _visMode;

    if (_editing) {
      final updated = widget.editing!.copyWith(
        base: name, ester: ester, type: type, graphType: graphType,
        halfLife: halfLife, timeToPeak: timeToPeak, ratio: ratio,
        unit: _unit, colorValue: _colorValue,
      );
      widget.onUpdate?.call(updated);
      Navigator.of(context).pop(updated);
    } else {
      final created = CompoundDefinition(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        base: name, ester: ester, type: type, graphType: graphType,
        halfLife: halfLife, timeToPeak: timeToPeak, ratio: ratio,
        unit: _unit, colorValue: _colorValue, isCustom: true,
      );
      widget.onCreate?.call(created);
      Navigator.of(context).pop(created);
    }
  }
}
