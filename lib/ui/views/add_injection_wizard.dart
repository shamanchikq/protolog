import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models.dart';
import '../../data.dart';
import '../../utils.dart';
import '../../engine/reminder_schedule.dart';
import '../theme.dart';

class AddInjectionWizard extends StatefulWidget {
  final void Function(Injection injection, bool advanceReminder) onAdd;
  final List<Reminder> reminders;
  final VoidCallback onCancel;
  final VoidCallback onSuccess;
  final List<CompoundDefinition> userCompounds;
  final Function(CompoundDefinition) addUserCompound;
  final List<Injection> injections;
  final CompoundDefinition? prefillCompound;
  final DateTime? prefillDate;

  /// Edit mode (F2): opens directly on the details step prefilled from this
  /// injection; Confirm replaces it in place via [onEdit] instead of logging
  /// a new dose. The frozen PK snapshot is preserved.
  final Injection? editingInjection;
  final void Function(Injection updated)? onEdit;

  const AddInjectionWizard({
    super.key,
    required this.onAdd,
    required this.reminders,
    required this.onCancel,
    required this.onSuccess,
    required this.userCompounds,
    required this.addUserCompound,
    required this.injections,
    this.prefillCompound,
    this.prefillDate,
    this.editingInjection,
    this.onEdit,
  });

  @override
  State<AddInjectionWizard> createState() => _AddInjectionWizardState();
}

class _AddInjectionWizardState extends State<AddInjectionWizard> {
  int _step = 1;

  // Step 1 state
  String _typeFilter = 'steroid'; // 'steroid' | 'oral' | 'peptide' | 'ancillary'
  String? _selectedBase;          // non-null when drilled into a steroid base
  String _searchQuery = '';

  // Step 2 state (set when Step 1 advances)
  CompoundDefinition? _selectedCompound;
  String _mode = 'direct';        // 'direct' | 'volume'
  String _doseText = '';
  Unit _unit = Unit.mg;
  String _volumeText = '';
  String _volumeInputUnit = 'mL'; // 'mL' | 'IU' — only meaningful for peptides
  double? _concentrationDraft;    // sheet/by-volume writes here; persisted on Confirm
  DateTime _date = DateTime.now();
  TimeOfDay _time = _roundedNow();
  String _site = 'Vent. glute R';
  String _notes = '';
  Injection? _lastForCompound;

  bool _advanceReminder = true;

  bool get _isEdit => widget.editingInjection != null;

  Reminder? get _matchingReminder {
    if (_isEdit) return null; // editing history never advances reminders
    final c = _selectedCompound;
    if (c == null) return null;
    for (final r in widget.reminders) {
      if (r.enabled && r.compoundBase == c.base && r.compoundEster == c.ester) {
        return r;
      }
    }
    return null;
  }

  // Text controllers for fields whose initial value comes from state.
  late final TextEditingController _doseController = TextEditingController(text: _doseText);
  late final TextEditingController _volumeController = TextEditingController();
  late final TextEditingController _notesController = TextEditingController();
  late final TextEditingController _concController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustomSites();
    final editing = widget.editingInjection;
    final pre = widget.prefillCompound;
    if (editing != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enterEditMode(editing);
      });
    } else if (pre != null) {
      // _enterStep2 calls setState, so schedule it after the first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enterStep2(pre);
      });
    }
  }

  /// Prefills the details step from an existing injection. Unlike
  /// [_enterStep2], the compound is the injection's own frozen snapshot —
  /// editing a log must never silently re-canonicalize its PK.
  void _enterEditMode(Injection inj) {
    setState(() {
      _selectedCompound = inj.snapshot;
      _lastForCompound = null;
      _unit = inj.snapshot.unit;
      _mode = 'direct';
      _doseText = _trimZero(inj.dosage);
      _doseController.text = _doseText;
      _volumeText = '';
      _volumeController.text = '';
      _notes = inj.notes ?? '';
      _notesController.text = _notes;
      _concentrationDraft = inj.snapshot.concentration;
      _concController.text = inj.snapshot.concentration != null
          ? _trimZero(inj.snapshot.concentration!)
          : '';
      _site = inj.site ??
          (inj.snapshot.type == CompoundType.peptide ? 'Abdominal R' : 'Vent. glute R');
      _date = inj.date;
      _time = TimeOfDay.fromDateTime(inj.date);
      _advanceReminder = false;
      _step = 2;
    });
  }

  Future<void> _loadCustomSites() async {
    final prefs = await SharedPreferences.getInstance();
    final imRaw = prefs.getString('customSitesIM');
    final sqRaw = prefs.getString('customSitesSubQ');
    setState(() {
      _customSitesIM = imRaw != null
          ? List<String>.from(jsonDecode(imRaw) as List)
          : const [];
      _customSitesSubQ = sqRaw != null
          ? List<String>.from(jsonDecode(sqRaw) as List)
          : const [];
    });
  }

  Future<void> _saveCustomSites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('customSitesIM', jsonEncode(_customSitesIM));
    await prefs.setString('customSitesSubQ', jsonEncode(_customSitesSubQ));
  }

  Future<void> _promptAddSite() async {
    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => const _AddSiteDialog(),
    );
    if (result == null || result.isEmpty) return;
    setState(() {
      if (_isSubQ) {
        if (!_customSitesSubQ.contains(result)) {
          _customSitesSubQ = [..._customSitesSubQ, result];
        }
      } else {
        if (!_customSitesIM.contains(result)) {
          _customSitesIM = [..._customSitesIM, result];
        }
      }
      _site = result;
    });
    _saveCustomSites();
  }

  @override
  void dispose() {
    _doseController.dispose();
    _volumeController.dispose();
    _notesController.dispose();
    _concController.dispose();
    super.dispose();
  }

  static TimeOfDay _roundedNow() {
    final n = DateTime.now();
    final m = (n.minute / 5).round() * 5;
    return TimeOfDay(hour: m == 60 ? (n.hour + 1) % 24 : n.hour, minute: m % 60);
  }

  // ── Step 1 data helpers ────────────────────────────────────────────────────

  CompoundType get _targetType {
    switch (_typeFilter) {
      case 'steroid': return CompoundType.steroid;
      case 'oral': return CompoundType.oral;
      case 'peptide': return CompoundType.peptide;
      case 'ancillary': return CompoundType.ancillary;
      default: return CompoundType.steroid;
    }
  }

  bool _matchesSearch(CompoundDefinition c) {
    if (_searchQuery.trim().isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    return c.base.toLowerCase().contains(q) || c.ester.toLowerCase().contains(q);
  }

  int _esterCountForBase(String base) {
    final Set<String> esters = {};
    for (final c in widget.userCompounds) {
      if (c.type == CompoundType.steroid && c.base == base) esters.add(c.ester);
    }
    BASE_LIBRARY.forEach((_, v) {
      if (v.type == CompoundType.steroid && v.base == base) esters.add(v.ester);
    });
    return esters.length;
  }

  /// Recent compounds (up to 3) for the current filter, by most-recent injection.
  /// During steroid drill-down or when searching, returns []. Hidden by the UI.
  List<({CompoundDefinition compound, DateTime lastDate})> _recentList() {
    if (_selectedBase != null || _searchQuery.trim().isNotEmpty) return const [];
    final Map<String, ({CompoundDefinition compound, DateTime lastDate})> map = {};
    // Sort injections newest first, dedupe by base.
    final sorted = [...widget.injections]..sort((a, b) => b.date.compareTo(a.date));
    for (final inj in sorted) {
      final snap = inj.snapshot;
      if (snap.type != _targetType) continue;
      if (map.containsKey(snap.base)) continue;
      // Re-resolve to a current library/user compound by base+ester when possible.
      final live = _resolveCompound(snap.base, snap.ester) ?? snap;
      map[snap.base] = (compound: live, lastDate: inj.date);
      if (map.length >= 3) break;
    }
    return map.values.toList();
  }

  CompoundDefinition? _resolveCompound(String base, String ester) {
    for (final c in widget.userCompounds) {
      if (c.base == base && c.ester == ester) return c;
    }
    for (final v in BASE_LIBRARY.values) {
      if (v.base == base && v.ester == ester) return v;
    }
    return null;
  }

  /// Library list for the current filter. When drilled into a steroid base,
  /// returns the ester variants of that base.
  List<CompoundDefinition> _libraryList() {
    if (_targetType == CompoundType.steroid && _selectedBase == null) {
      // Show one row per base name. Customs first, then BASE_LIBRARY order.
      final Map<String, CompoundDefinition> bases = {};
      for (final c in widget.userCompounds) {
        if (c.type == CompoundType.steroid && !bases.containsKey(c.base)) {
          bases[c.base] = c;
        }
      }
      BASE_LIBRARY.forEach((_, v) {
        if (v.type == CompoundType.steroid && !bases.containsKey(v.base)) {
          bases[v.base] = v;
        }
      });
      return bases.values.where(_matchesSearch).toList();
    }
    if (_targetType == CompoundType.steroid && _selectedBase != null) {
      // Ester variants for the selected base.
      final Map<String, CompoundDefinition> esters = {};
      for (final c in widget.userCompounds) {
        if (c.type == CompoundType.steroid && c.base == _selectedBase) {
          esters.putIfAbsent(c.ester, () => c);
        }
      }
      BASE_LIBRARY.forEach((_, v) {
        if (v.type == CompoundType.steroid && v.base == _selectedBase) {
          esters.putIfAbsent(v.ester, () => v);
        }
      });
      return esters.values.where(_matchesSearch).toList();
    }
    // Non-steroid: one row per base. BASE_LIBRARY is the source of truth for
    // categorization — a user compound whose (base, ester) matches a library
    // entry is just a personalized copy and is filtered through the library's
    // type. User entries with no matching library row are treated as truly
    // custom and surfaced under their own type.
    final Map<String, CompoundDefinition> map = {};
    BASE_LIBRARY.forEach((_, v) {
      if (v.type == _targetType && !map.containsKey(v.base)) {
        map[v.base] = v;
      }
    });
    for (final c in widget.userCompounds) {
      final libMatch = BASE_LIBRARY.values.any((v) => v.base == c.base && v.ester == c.ester);
      if (libMatch) continue; // already represented by the library entry above
      if (c.type == _targetType && !map.containsKey(c.base)) {
        map[c.base] = c;
      }
    }
    return map.values.where(_matchesSearch).toList();
  }

  String _libraryRowMeta(CompoundDefinition c) {
    if (c.type == CompoundType.steroid && _selectedBase == null) {
      final n = _esterCountForBase(c.base);
      return '$n ${n == 1 ? 'ester' : 'esters'}';
    }
    if (c.type == CompoundType.steroid) {
      return '${c.ester} · t½ ${c.halfLife.toStringAsFixed(1)}d';
    }
    if (c.type == CompoundType.oral) {
      return 'Oral · t½ ${c.halfLife.toStringAsFixed(1)}d';
    }
    if (c.type == CompoundType.peptide) {
      return 'Peptide · ${c.graphType == GraphType.event ? 'event' : 'window'}';
    }
    return 'Ancillary · ${c.graphType.name}';
  }

  Color _colorFor(CompoundDefinition c) {
    return AppTheme.compoundColor(c.base) ?? Color(c.colorValue);
  }

  String _relativeAgo(DateTime then) {
    final now = DateTime.now();
    final diff = now.difference(then);
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  // ── End Step 1 data helpers ────────────────────────────────────────────────

  // ── Step 1 rendering helpers ───────────────────────────────────────────────

  Widget _buildSectionTitle(String title, {String? meta}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: AppTheme.sans(size: 11, weight: FontWeight.w500, color: AppTheme.fgMute, letterSpacing: 0.4)),
          if (meta != null)
            Text(meta, style: AppTheme.sans(size: 11, color: AppTheme.fgDim)),
        ],
      ),
    );
  }

  Widget _buildRecentSection() {
    final items = _recentList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle('Recent'),
        Row(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _buildCompoundCard(
                  compound: items[i].compound,
                  lastDate: items[i].lastDate,
                ),
              ),
            ],
            // Fill remaining slots with empty spacers so 1 or 2 cards don't stretch full-width
            for (int i = items.length; i < 3; i++) ...[
              const SizedBox(width: 8),
              const Expanded(child: SizedBox.shrink()),
            ],
          ],
        ),
        const SizedBox(height: 22),
      ],
    );
  }

  Widget _buildCompoundCard({required CompoundDefinition compound, required DateTime lastDate}) {
    final color = _colorFor(compound);
    String sub;
    if (compound.type == CompoundType.steroid) {
      final n = _esterCountForBase(compound.base);
      sub = n > 1 ? '$n esters' : compound.ester;
    } else {
      sub = compound.type.name.toUpperCase();
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onCompoundTap(compound),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border(
            top: BorderSide(color: color, width: 2),
            left: BorderSide(color: AppTheme.border, width: 1),
            right: BorderSide(color: AppTheme.border, width: 1),
            bottom: BorderSide(color: AppTheme.border, width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(compound.base,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.sans(size: 12.5, weight: FontWeight.w600, color: AppTheme.fg, letterSpacing: -0.1)),
            const SizedBox(height: 3),
            Text(sub,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.sans(size: 10.5, color: AppTheme.fgMute)),
            const SizedBox(height: 8),
            Text(_relativeAgo(lastDate),
                style: AppTheme.sans(size: 10.5, color: AppTheme.accent)),
          ],
        ),
      ),
    );
  }

  Widget _buildLibrarySection() {
    final items = _libraryList();
    if (items.isEmpty) {
      if (_searchQuery.trim().isNotEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text('No matches for "$_searchQuery"',
                style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('No $_typeFilter compounds in library',
              style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle('Library'),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++)
                _buildLibraryRow(items[i], isFirst: i == 0),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLibraryRow(CompoundDefinition c, {required bool isFirst}) {
    final color = _colorFor(c);
    final showCustom = c.isCustom;
    final nameStr = (_targetType == CompoundType.steroid && _selectedBase != null)
        ? c.ester
        : c.base;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onCompoundTap(c),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            top: isFirst ? BorderSide.none : BorderSide(color: AppTheme.borderSoft, width: 1),
          ),
        ),
        child: Row(
          children: [
            Container(width: 8, height: 8, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(nameStr,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.sans(size: 13, weight: FontWeight.w500, color: AppTheme.fg)),
                      ),
                      if (showCustom) ...[
                        const SizedBox(width: 8),
                        Text('custom', style: AppTheme.sans(size: 10, color: AppTheme.warm)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(_libraryRowMeta(c),
                      style: AppTheme.sans(size: 11, color: AppTheme.fgMute)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text('›', style: AppTheme.sans(size: 16, color: AppTheme.fgDim)),
          ],
        ),
      ),
    );
  }

  void _onCompoundTap(CompoundDefinition c) {
    // Steroid base list with multi-ester → drill in
    if (c.type == CompoundType.steroid && _selectedBase == null) {
      if (_esterCountForBase(c.base) > 1) {
        setState(() => _selectedBase = c.base);
        return;
      }
    }
    // Otherwise advance to Step 2.
    _enterStep2(c);
  }

  void _enterStep2(CompoundDefinition c) {
    // BASE_LIBRARY is the source of truth for type and unit. If `c` is a stale
    // user-stored copy (e.g. from before a model categorization change), the
    // library version's type/unit take precedence. We keep the user's
    // concentration override though, since that's per-user data.
    CompoundDefinition canon = c;
    for (final v in BASE_LIBRARY.values) {
      if (v.base == c.base && v.ester == c.ester) {
        canon = v;
        break;
      }
    }
    final userOverride = widget.userCompounds.firstWhere(
      (u) => u.base == c.base && u.ester == c.ester,
      orElse: () => canon,
    );
    final effective = canon.copyWith(
      concentration: userOverride.concentration ?? canon.concentration,
    );
    // Find prior injection for pre-fill
    final matches = widget.injections
        .where((i) => i.snapshot.base == effective.base && i.snapshot.ester == effective.ester)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final last = matches.isNotEmpty ? matches.first : null;
    setState(() {
      _selectedCompound = effective;
      _lastForCompound = last;
      // IU is shown only for compounds whose stored unit is iu (HCG, HGH, etc.).
      // Other compounds use the mass segment [mg, mcg].
      _unit = effective.unit;
      _mode = 'direct';
      _doseText = last != null ? _trimZero(last.dosage) : '';
      _doseController.text = _doseText;
      _volumeText = '';
      _volumeController.text = '';
      _notes = '';
      _notesController.text = '';
      _concentrationDraft = effective.concentration;
      _concController.text =
          effective.concentration != null ? _trimZero(effective.concentration!) : '';
      final priorSiteList = widget.injections
          .where((i) => i.snapshot.base == effective.base && i.site != null && i.site!.isNotEmpty)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      final isSubQ = effective.type == CompoundType.peptide;
      final defaultSite = isSubQ ? 'Abdominal R' : 'Vent. glute R';
      _site = (priorSiteList.isNotEmpty ? priorSiteList.first.site! : null) ?? defaultSite;
      _date = widget.prefillDate ?? DateTime.now();
      _time = _roundedNow();
      _step = 2;
    });
  }

  String _trimZero(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    // Cap at 2 decimal places, then trim trailing zeros so "6.6666" → "6.67"
    // and "5.50" → "5.5" while keeping whole-number cases as integers.
    var s = v.toStringAsFixed(2);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    }
    return s;
  }

  // ── End Step 1 rendering helpers ───────────────────────────────────────────

  // ── Step 2 helpers ─────────────────────────────────────────────────────────

  bool get _isOral => _selectedCompound?.type == CompoundType.oral;
  bool get _isAncillary => _selectedCompound?.type == CompoundType.ancillary;
  bool get _isPeptide => _selectedCompound?.type == CompoundType.peptide;
  // "IU-native" compounds (HCG, HGH, etc.) — their stored unit is iu and
  // their vial concentration is IU/mL rather than mg/mL.
  bool get _isIuNative => _selectedCompound?.unit == Unit.iu;
  String get _concentrationUnit => _isIuNative ? 'IU/mL' : 'mg/mL';
  // "Pill form" = anything taken orally (orals + any ancillary). Hides the
  // site picker and the Direct/By-volume mode toggle.
  bool get _isPillForm => _isOral || _isAncillary;
  // Sub-Q route covers peptides (incl. hCG, which we treat as a peptide).
  bool get _isSubQ => _isPeptide;
  bool get _isPeptideUnit => _unit == Unit.mcg || _unit == Unit.iu;

  Widget _buildDoseSection() {
    final c = _selectedCompound!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle('Dose'),
        if (!_isPillForm) ...[
          _Seg<String>(
            value: _mode,
            options: const ['direct', 'volume'],
            labelOf: (s) => s == 'direct' ? 'Direct' : 'By volume',
            onChange: (v) => setState(() {
              _mode = v;
              if (v == 'direct') {
                // Re-sync the dose controller when returning to Direct mode so
                // the last computed by-volume dose (or prior direct entry) shows.
                _doseController.text = _doseText;
              } else {
                // Switching into By-volume: when the user is entering volume
                // in mL, pre-seed the field with "0." so they can start
                // typing the decimal portion directly.
                if (_volumeInputUnit == 'mL' && _volumeController.text.isEmpty) {
                  _volumeController.text = '0.';
                  _volumeController.selection = TextSelection.collapsed(
                    offset: _volumeController.text.length,
                  );
                  _volumeText = '0.';
                }
              }
            }),
          ),
          const SizedBox(height: 8),
        ],
        if (_mode == 'direct' || _isPillForm) _buildDoseDirect(c) else _buildDoseByVolume(c),
      ],
    );
  }

  Widget _buildDoseDirect(CompoundDefinition c) {
    final dose = parseFlexibleDouble(_doseText) ?? 0;
    final conc = _concentrationDraft;
    String? hint;
    if (conc != null && conc > 0 && dose > 0) {
      final ml = dose / conc;
      // U100 syringe-reading hint only adds value for mass-dosed peptides;
      // IU-native compounds are already dosed in IU so the equivalent is the
      // dose itself.
      if (_unit == Unit.mcg) {
        final iu = ml * 100;
        hint = '≈ ${ml.toStringAsFixed(2)} mL · ${iu.toStringAsFixed(1)} IU';
      } else {
        hint = '≈ ${ml.toStringAsFixed(2)} mL';
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _Field(
            label: 'Amount',
            hint: hint,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _doseController,
                    onChanged: (v) => setState(() => _doseText = v),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    cursorColor: AppTheme.accent,
                    style: AppTheme.serif(
                        size: 32, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.8, height: 1.1),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: '0',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(_unit.name, style: AppTheme.sans(size: 13, color: AppTheme.fgMute)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 140,
          child: _Field(
            label: 'Unit',
            child: _Seg<Unit>(
              value: _unit,
              options: _isIuNative
                  ? const [Unit.iu]
                  : const [Unit.mg, Unit.mcg],
              labelOf: (u) => u.name,
              onChange: (u) => setState(() => _unit = u),
              mono: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDoseByVolume(CompoundDefinition c) {
    final conc = _concentrationDraft;
    final volumeRaw = parseFlexibleDouble(_volumeText) ?? 0;
    // Convert the user-entered volume to mL using the U100 standard
    // (100 IU = 1 mL) when they're inputting in IU.
    final volumeMl = (_isPeptide && _volumeInputUnit == 'IU') ? volumeRaw / 100.0 : volumeRaw;
    final computedDose = (conc != null && conc > 0) ? volumeMl * conc : 0.0;
    String volumeHint = '';
    if (conc != null && conc > 0 && volumeRaw > 0) {
      if (_unit == Unit.mcg) {
        // Mass-dosed peptide: show the syringe-reading IU equivalent.
        final mlPart = _trimZero(volumeMl);
        final iuPart = (volumeMl * 100).toStringAsFixed(1);
        if (_volumeInputUnit == 'IU') {
          volumeHint = '= ${_trimZero(computedDose)} ${_unit.name} · $mlPart mL';
        } else {
          volumeHint = '= ${_trimZero(computedDose)} ${_unit.name} ≈ $iuPart IU';
        }
      } else if (_isPeptide && _volumeInputUnit == 'IU') {
        // IU-native peptide and user entered IU volume: just show the dose
        // and the mL equivalent of the volume.
        final mlPart = _trimZero(volumeMl);
        volumeHint = '= ${_trimZero(computedDose)} ${_unit.name} · $mlPart mL';
      } else {
        volumeHint = '= ${_trimZero(computedDose)} ${_unit.name}';
      }
    }
    // Keep _doseText in sync so the sticky bar / confirm logic stays simple.
    final computedDoseText = computedDose > 0 ? _trimZero(computedDose) : '';
    if (_doseText != computedDoseText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _doseText = computedDoseText);
      });
    }
    final concDisplay = (conc != null) ? _trimZero(conc) : '—';
    // Peptides get a tap → reconstitution sheet (mg + bac → mg/mL).
    // Steroids/anything else: edit the concentration directly as a number.
    final Widget concField = _isPeptide
        ? _Field(
            label: 'Concentration',
            hint: (conc == null) ? 'tap to calculate' : 'from vial',
            onTap: _openReconstitutionSheet,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(concDisplay,
                    style: AppTheme.serif(
                        size: 28, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.6, height: 1.1)),
                const SizedBox(width: 6),
                Text(_concentrationUnit, style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
              ],
            ),
          )
        : _Field(
            label: 'Concentration',
            hint: 'from vial',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _concController,
                    onChanged: (v) => setState(() {
                      final parsed = parseFlexibleDouble(v);
                      _concentrationDraft = (parsed != null && parsed > 0) ? parsed : null;
                    }),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    cursorColor: AppTheme.accent,
                    style: AppTheme.serif(
                        size: 28, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.6, height: 1.1),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: '0',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(_concentrationUnit, style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
              ],
            ),
          );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: concField),
          const SizedBox(width: 8),
          Expanded(
            child: _Field(
              label: 'Volume',
              hint: volumeHint.isEmpty ? null : volumeHint,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _volumeController,
                      enabled: conc != null && conc > 0,
                      onChanged: (v) => setState(() => _volumeText = v),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      cursorColor: AppTheme.accent,
                      style: AppTheme.serif(
                          size: 28,
                          weight: FontWeight.w500,
                          color: (conc != null && conc > 0) ? AppTheme.fg : AppTheme.fgDim,
                          letterSpacing: -0.6,
                          height: 1.1),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        hintText: '0',
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                if (_isPeptide)
                  SizedBox(
                    width: 84,
                    child: _Seg<String>(
                      value: _volumeInputUnit,
                      options: const ['mL', 'IU'],
                      labelOf: (s) => s,
                      onChange: (v) => setState(() {
                        _volumeInputUnit = v;
                        if (v == 'mL' && _volumeController.text.isEmpty) {
                          // mL inputs start with "0." for ergonomic decimal entry.
                          _volumeController.text = '0.';
                          _volumeController.selection = TextSelection.collapsed(
                            offset: _volumeController.text.length,
                          );
                          _volumeText = '0.';
                        } else if (v == 'IU' && _volumeController.text == '0.') {
                          // Drop the leftover mL prefill — IU entries are whole numbers.
                          _volumeController.text = '';
                          _volumeText = '';
                        }
                      }),
                      mono: true,
                    ),
                  )
                else
                  Text('mL', style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openReconstitutionSheet() async {
    final c = _selectedCompound;
    if (c == null) return;
    final result = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: AppTheme.bg,
      isScrollControlled: true,
      builder: (ctx) => _ReconstitutionSheet(
        initialMgPerVial: null,
        initialVolume: null,
        isPeptide: _isPeptideUnit,
        massUnitLabel: _isIuNative ? 'IU' : 'mg',
      ),
    );
    if (result != null && result > 0) {
      setState(() => _concentrationDraft = result);
    }
  }

  Widget _buildWhenSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle('When'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 7,
              child: _Field(
                label: 'Date',
                onTap: () => _pickDate(context),
                child: Text(_formatRelativeDate(_date),
                    style: AppTheme.sans(size: 15, weight: FontWeight.w500, color: AppTheme.fg)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: _Field(
                label: 'Time',
                onTap: () => _pickTime(context),
                child: Text(_formatTime(_time),
                    style: AppTheme.mono(size: 15, weight: FontWeight.w500, color: AppTheme.fg)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildQuickTimes(),
      ],
    );
  }

  Widget _buildQuickTimes() {
    const slots = <(int, int)>[(6, 0), (8, 0), (20, 0), (22, 0)];
    return Row(
      children: [
        for (int i = 0; i < slots.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _buildPill(
              label: _formatTime(TimeOfDay(hour: slots[i].$1, minute: slots[i].$2)),
              active: _time.hour == slots[i].$1 && _time.minute == slots[i].$2,
              onTap: () =>
                  setState(() => _time = TimeOfDay(hour: slots[i].$1, minute: slots[i].$2)),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDate: _date,
      builder: (ctx, child) => _themedPickerWrapper(child!),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (ctx, child) => _themedPickerWrapper(child!),
    );
    if (picked != null) setState(() => _time = picked);
  }

  /// Wraps the Material date/time pickers in a Theme that respects the
  /// "Lab Sheet" tokens — near-black surfaces, mint accent, sharp corners.
  Widget _themedPickerWrapper(Widget child) {
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppTheme.bg,
        colorScheme: const ColorScheme.dark(
          primary: AppTheme.accent,
          onPrimary: AppTheme.bg,
          surface: AppTheme.surface,
          onSurface: AppTheme.fg,
          surfaceContainerHighest: AppTheme.surface2,
          outline: AppTheme.border,
          secondary: AppTheme.accent,
          onSecondary: AppTheme.bg,
          error: AppTheme.warn,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: AppTheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(),
        ),
        datePickerTheme: const DatePickerThemeData(
          backgroundColor: AppTheme.surface,
          surfaceTintColor: Colors.transparent,
          headerBackgroundColor: AppTheme.surface2,
          headerForegroundColor: AppTheme.fg,
          shape: RoundedRectangleBorder(),
          dividerColor: AppTheme.border,
          dayShape: WidgetStatePropertyAll(RoundedRectangleBorder()),
        ),
        timePickerTheme: const TimePickerThemeData(
          backgroundColor: AppTheme.surface,
          dialBackgroundColor: AppTheme.surface2,
          dialHandColor: AppTheme.accent,
          dialTextColor: AppTheme.fg,
          hourMinuteColor: AppTheme.surface2,
          hourMinuteTextColor: AppTheme.fg,
          dayPeriodColor: AppTheme.surface2,
          dayPeriodTextColor: AppTheme.fg,
          shape: RoundedRectangleBorder(),
          hourMinuteShape: RoundedRectangleBorder(),
          entryModeIconColor: AppTheme.fgMute,
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.accent,
            textStyle: AppTheme.sans(size: 13, weight: FontWeight.w600),
          ),
        ),
      ),
      child: child,
    );
  }

  String _formatRelativeDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    final monthDay = formatDate(d, 'MMM d');
    if (diff == 0) return 'Today, $monthDay';
    if (diff == 1) return 'Yesterday, $monthDay';
    if (diff == -1) return 'Tomorrow, $monthDay';
    if (d.year == now.year) return monthDay;
    return '${formatDate(d, 'MMM d')}, ${d.year}';
  }

  String _formatTime(TimeOfDay t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  // Intramuscular sites (steroids).
  static const _sitesIM = <String>[
    'Vent. glute L', 'Vent. glute R', 'Quad L',
    'Quad R', 'Delt L', 'Delt R',
  ];

  // Subcutaneous sites (peptides, hCG).
  static const _sitesSubQ = <String>[
    'Abdominal L', 'Abdominal R', 'Glute L',
    'Glute R', 'Quad L', 'Quad R',
  ];

  // Custom sites loaded from SharedPreferences, keyed by route.
  List<String> _customSitesIM = const [];
  List<String> _customSitesSubQ = const [];

  List<String> get _allSites {
    final base = _isSubQ ? _sitesSubQ : _sitesIM;
    final custom = _isSubQ ? _customSitesSubQ : _customSitesIM;
    return [...base, ...custom];
  }

  Widget _buildSiteSection() {
    if (_isPillForm) return const SizedBox.shrink();
    // Find the most-recent prior site for this compound's base
    String? lastSite;
    if (_selectedCompound != null) {
      final base = _selectedCompound!.base;
      final priors = widget.injections
          .where((i) => i.snapshot.base == base && i.site != null && i.site!.isNotEmpty)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      if (priors.isNotEmpty) lastSite = priors.first.site;
    }
    final sites = _allSites;
    // Total cells = sites + 1 "+ Add site" tile.
    final cellCount = sites.length + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle('Site', meta: lastSite != null ? 'last: $lastSite' : null),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cellCount,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 3.2,
          ),
          itemBuilder: (_, i) {
            if (i == cellCount - 1) {
              // Add-site tile
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _promptAddSite,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.borderSoft, width: 1),
                  ),
                  child: Text('+ Add site',
                      style: AppTheme.sans(
                          size: 11.5, weight: FontWeight.w500, color: AppTheme.fgDim)),
                ),
              );
            }
            final s = sites[i];
            final active = s == _site;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _site = active ? '' : s),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? AppTheme.surface : Colors.transparent,
                  border: Border.all(
                    color: active ? AppTheme.fg : AppTheme.border,
                    width: 1,
                  ),
                ),
                child: Text(s,
                    style: AppTheme.sans(
                        size: 11.5,
                        weight: active ? FontWeight.w600 : FontWeight.w400,
                        color: active ? AppTheme.fg : AppTheme.fgMute)),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle('Notes', meta: 'optional'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: TextField(
            controller: _notesController,
            onChanged: (v) => _notes = v,
            minLines: 1,
            maxLines: 3,
            cursorColor: AppTheme.accent,
            style: AppTheme.sans(size: 13, color: AppTheme.fg),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              hintText: 'Add a note…',
              hintStyle: AppTheme.sans(size: 13, color: AppTheme.fgDim),
            ),
          ),
        ),
      ],
    );
  }

  Widget _reminderBanner(Reminder r) {
    final next = nextOccurrence(r, DateTime.now());
    final label = '${relativeDayLabel(next, DateTime.now())} '
        '${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Linked to your ${r.compoundBase} reminder',
                    style: AppTheme.sans(size: 12, weight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text('Next due $label', style: AppTheme.sans(size: 11, color: AppTheme.fgMute)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _advanceReminder = !_advanceReminder),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    color: _advanceReminder ? AppTheme.accent : Colors.transparent,
                    border: Border.all(color: _advanceReminder ? AppTheme.accent : AppTheme.border, width: 1),
                  ),
                  child: _advanceReminder
                      ? const Icon(Icons.check, size: 13, color: AppTheme.bg)
                      : null,
                ),
                const SizedBox(width: 6),
                Text('Advance', style: AppTheme.sans(size: 11, color: AppTheme.fgMute)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── End Step 2 helpers ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: _step == 1 ? _buildStep1() : _buildStep2(),
            ),
            if (_step == 2) _buildStickyBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
          child: _buildStep1Header(),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _buildSearchBar(),
        ),
        const SizedBox(height: 14),
        if (_selectedBase == null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _buildFilterPills(),
          ),
          const SizedBox(height: 22),
        ],
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildRecentSection(),
                _buildLibrarySection(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep1Header() {
    final title = _selectedBase ?? 'Select compound';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Step 1 of 2',
                  style: AppTheme.sans(size: 11, color: AppTheme.fgDim)),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (_selectedBase != null)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _selectedBase = null),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text('‹',
                            style: AppTheme.serif(
                                size: 22, weight: FontWeight.w500, color: AppTheme.fgMute, letterSpacing: -0.4)),
                      ),
                    ),
                  Text(title,
                      style: AppTheme.serif(
                          size: 22, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.4)),
                ],
              ),
            ],
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onCancel,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(border: Border.all(color: AppTheme.border, width: 1)),
            child: Text('Cancel', style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: AppTheme.fgDim),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              cursorColor: AppTheme.accent,
              style: AppTheme.sans(size: 13, color: AppTheme.fg),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search compounds',
                hintStyle: AppTheme.sans(size: 13, color: AppTheme.fgDim),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPills() {
    const filters = <(String, String)>[
      ('steroid', 'Injectable'),
      ('oral', 'Oral'),
      ('peptide', 'Peptide'),
      ('ancillary', 'Ancillary'),
    ];
    return Row(
      children: [
        for (final (key, label) in filters) ...[
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _buildPill(
              label: label,
              active: _typeFilter == key,
              onTap: () => setState(() {
                _typeFilter = key;
                _selectedBase = null;
              }),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPill({required String label, required bool active, required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.fg : Colors.transparent,
          border: Border.all(color: active ? AppTheme.fg : AppTheme.border, width: 1),
        ),
        child: Text(
          label,
          style: AppTheme.sans(
            size: 12,
            weight: FontWeight.w500,
            color: active ? AppTheme.bg : AppTheme.fgMute,
          ),
        ),
      ),
    );
  }

  Widget _buildStep2() {
    final c = _selectedCompound;
    if (c == null) {
      // Shouldn't happen — Step 1 sets it before advancing.
      return const SizedBox.shrink();
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
      children: [
        _buildStep2Header(),
        const SizedBox(height: 16),
        _buildSelectedChip(c),
        if (_lastForCompound != null) ...[
          const SizedBox(height: 6),
          Text(
            'Last: ${_trimZero(_lastForCompound!.dosage)} ${_lastForCompound!.snapshot.unit.name} · ${_relativeAgo(_lastForCompound!.date)}',
            style: AppTheme.sans(size: 11, color: AppTheme.accent),
          ),
        ],
        const SizedBox(height: 18),
        _buildDoseSection(),
        const SizedBox(height: 18),
        _buildWhenSection(context),
        const SizedBox(height: 18),
        _buildSiteSection(),
        if (!_isPillForm) const SizedBox(height: 18),
        _buildNotesSection(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildStep2Header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_isEdit ? 'Editing logged dose' : 'Step 2 of 2',
                  style: AppTheme.sans(size: 11, color: AppTheme.fgDim)),
              const SizedBox(height: 4),
              Text(_isEdit ? 'Edit dose' : 'Dose & time',
                  style: AppTheme.serif(
                      size: 22, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.4)),
            ],
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          // In edit mode there is no step 1 to go back to — close instead.
          onTap: _isEdit ? widget.onCancel : () => setState(() => _step = 1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(border: Border.all(color: AppTheme.border, width: 1)),
            child: Text(_isEdit ? 'Cancel' : 'Back',
                style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedChip(CompoundDefinition c) {
    final color = _colorFor(c);
    final esterPart = (c.type == CompoundType.steroid &&
            c.ester.isNotEmpty &&
            c.ester.toLowerCase() != 'none')
        ? ' ${c.ester}'
        : '';
    final concPart = _concentrationDraft != null
        ? '${_trimZero(_concentrationDraft!)} $_concentrationUnit'
        : 'concentration unset';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: color, width: 2),
          left: BorderSide(color: AppTheme.border, width: 1),
          right: BorderSide(color: AppTheme.border, width: 1),
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: c.base,
                        style: AppTheme.sans(size: 14, weight: FontWeight.w600, color: AppTheme.fg, letterSpacing: -0.2),
                      ),
                      TextSpan(
                        text: esterPart,
                        style: AppTheme.sans(size: 14, weight: FontWeight.w400, color: AppTheme.fgMute, letterSpacing: -0.2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text('t½ ${c.halfLife.toStringAsFixed(1)}d · $concPart',
                    style: AppTheme.sans(size: 11, color: AppTheme.fgDim)),
              ],
            ),
          ),
          if (!_isEdit)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _step = 1),
              child: Text('Change',
                  style: AppTheme.sans(size: 11, color: AppTheme.accent)),
            ),
        ],
      ),
    );
  }

  Widget _buildStickyBar() {
    final c = _selectedCompound;
    final doseVal = parseFlexibleDouble(_doseText) ?? 0;
    final hasDose = doseVal > 0;
    final showSite = c != null &&
        c.type != CompoundType.oral &&
        c.type != CompoundType.ancillary;
    final siteShort = (showSite && _site.isNotEmpty)
        ? ' · ${_site.replaceFirst('Vent. ', '')}'
        : '';
    final matched = _matchingReminder;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (matched != null) _reminderBanner(matched),
        Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_isEdit ? 'EDITING' : 'LOGGING',
                  style: AppTheme.sans(size: 10, color: AppTheme.fgDim, letterSpacing: 0.6)),
              const SizedBox(height: 2),
              Text(
                hasDose
                    ? '${_trimZero(doseVal)} ${_unit.name}$siteShort'
                    : '—',
                style: AppTheme.mono(size: 14, weight: FontWeight.w500, color: AppTheme.fg),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: hasDose ? _submit : null,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 12),
                color: hasDose ? AppTheme.accent : AppTheme.surface2,
                child: Text(
                    _isEdit
                        ? 'Save changes'
                        : (_isPillForm ? 'Log administration' : 'Log injection'),
                    style: AppTheme.sans(
                        size: 13,
                        weight: FontWeight.w600,
                        color: hasDose ? AppTheme.bg : AppTheme.fgDim,
                        letterSpacing: 0.3)),
              ),
            ),
          ),
        ],
      ),
        ),
      ],
    );
  }

  void _submit() {
    final picked = _selectedCompound;
    if (picked == null) return;
    final doseVal = parseFlexibleDouble(_doseText);
    if (doseVal == null || doseVal <= 0) return;
    final fullDate = DateTime(
      _date.year, _date.month, _date.day, _time.hour, _time.minute,
    );

    // Edit mode: replace the log in place. The snapshot stays frozen (only
    // the display unit follows the selector) and userCompounds are untouched.
    final editing = widget.editingInjection;
    if (editing != null) {
      final showSite = !_isPillForm;
      widget.onEdit?.call(Injection(
        id: editing.id,
        compoundId: editing.compoundId,
        date: fullDate,
        dosage: doseVal,
        snapshot: editing.snapshot.copyWith(unit: _unit),
        site: (showSite && _site.isNotEmpty) ? _site : null,
        notes: _notes.trim().isEmpty ? null : _notes.trim(),
      ));
      widget.onSuccess();
      return;
    }

    // Find or materialize the user compound; bake in the latest concentration.
    final existing = widget.userCompounds.firstWhere(
      (c) => c.base == picked.base && c.ester == picked.ester,
      orElse: () => CompoundDefinition(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        base: picked.base,
        ester: picked.ester,
        type: picked.type,
        graphType: picked.graphType,
        halfLife: picked.halfLife,
        defaultHalfLife: picked.defaultHalfLife,
        timeToPeak: picked.timeToPeak,
        ratio: picked.ratio,
        unit: _unit,
        colorValue: picked.colorValue,
        isCustom: picked.isCustom,
        concentration: _concentrationDraft ?? picked.concentration,
      ),
    );
    final isAlreadyUser = widget.userCompounds.any((c) => c.id == existing.id);
    CompoundDefinition compDef;
    if (isAlreadyUser) {
      // Existing user compound — write back the new concentration / unit if changed.
      if (existing.concentration != _concentrationDraft || existing.unit != _unit) {
        compDef = existing.copyWith(
          concentration: _concentrationDraft ?? existing.concentration,
          unit: _unit,
        );
        widget.addUserCompound(compDef);
      } else {
        compDef = existing;
      }
    } else {
      // New record from BASE_LIBRARY adoption.
      compDef = existing;
      widget.addUserCompound(compDef);
    }
    final showSite = !_isPillForm;
    widget.onAdd(Injection(
      id: DateTime.now().toIso8601String(),
      compoundId: compDef.id,
      date: fullDate,
      dosage: doseVal,
      snapshot: compDef,
      site: (showSite && _site.isNotEmpty) ? _site : null,
      notes: _notes.trim().isEmpty ? null : _notes.trim(),
    ), _matchingReminder != null && _advanceReminder);
    widget.onSuccess();
  }
}

/// A labeled input shell: surface bg + 1px border + uppercase label row + optional right-side hint.
class _Field extends StatelessWidget {
  final String label;
  final String? hint;
  final Widget child;
  final VoidCallback? onTap;

  const _Field({
    required this.label,
    this.hint,
    required this.child,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(label.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.sans(size: 10, color: AppTheme.fgDim, letterSpacing: 0.8)),
              ),
              if (hint != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(hint!,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: AppTheme.mono(size: 10, color: AppTheme.fgDim)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
    if (onTap == null) return body;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: body);
  }
}

/// A segmented control. `value` must be in `options`. `onChange` is called with the new value.
/// If `mono` is true, labels render in JetBrains Mono.
class _Seg<T> extends StatelessWidget {
  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onChange;
  final bool mono;

  const _Seg({
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChange,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppTheme.border, width: 1)),
      child: Row(
        children: [
          for (int i = 0; i < options.length; i++) ...[
            if (i > 0) Container(width: 1, color: AppTheme.border),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChange(options[i]),
                child: Container(
                  alignment: Alignment.center,
                  color: options[i] == value ? AppTheme.fg : Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Builder(
                    builder: (_) {
                      final style = mono
                          ? AppTheme.mono(
                              size: 12,
                              weight: options[i] == value ? FontWeight.w600 : FontWeight.w400,
                              color: options[i] == value ? AppTheme.bg : AppTheme.fgMute,
                              letterSpacing: 0.2,
                            )
                          : AppTheme.sans(
                              size: 12,
                              weight: options[i] == value ? FontWeight.w600 : FontWeight.w400,
                              color: options[i] == value ? AppTheme.bg : AppTheme.fgMute,
                              letterSpacing: 0.2,
                            );
                      return Text(labelOf(options[i]), style: style);
                    },
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReconstitutionSheet extends StatefulWidget {
  final double? initialMgPerVial;
  final double? initialVolume;
  final bool isPeptide;
  final String massUnitLabel; // 'mg' for mass-dosed, 'IU' for IU-native
  const _ReconstitutionSheet({
    required this.initialMgPerVial,
    required this.initialVolume,
    required this.isPeptide,
    this.massUnitLabel = 'mg',
  });

  @override
  State<_ReconstitutionSheet> createState() => _ReconstitutionSheetState();
}

class _ReconstitutionSheetState extends State<_ReconstitutionSheet> {
  late final TextEditingController _mg = TextEditingController(
      text: widget.initialMgPerVial?.toString() ?? '');
  late final TextEditingController _vol = TextEditingController(
      text: widget.initialVolume?.toString() ?? '');
  String _volUnit = 'mL'; // 'mL' or 'IU'

  @override
  void dispose() {
    _mg.dispose();
    _vol.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mg = parseFlexibleDouble(_mg.text) ?? 0;
    final volRaw = parseFlexibleDouble(_vol.text) ?? 0;
    // At U100, 100 IU = 1 mL.
    final volMl = _volUnit == 'IU' ? volRaw / 100.0 : volRaw;
    final conc = (mg > 0 && volMl > 0) ? (mg / volMl) : 0.0;
    // The "X per 10 IU" line is the syringe-reading hint, only useful when
    // the dose unit is mass (mcg). IU-native compounds dose in IU directly.
    final iuLine = (widget.isPeptide && widget.massUnitLabel == 'mg' && conc > 0)
        ? '≈ ${(conc * 0.1).toStringAsFixed(2)} mg per 10 IU'
        : null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.bg,
            border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Reconstitute vial',
                        style: AppTheme.serif(
                            size: 18, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.3)),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text('×', style: AppTheme.sans(size: 18, color: AppTheme.fgMute)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _sheetField('${widget.massUnitLabel} per vial', _mg)),
                    const SizedBox(width: 8),
                    Expanded(child: _volField()),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  border: Border.all(color: AppTheme.border, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conc > 0
                          ? '${conc.toStringAsFixed(2)} ${widget.massUnitLabel}/mL'
                          : '— ${widget.massUnitLabel}/mL',
                      style: AppTheme.mono(size: 22, weight: FontWeight.w500, color: AppTheme.fg),
                    ),
                    if (iuLine != null) ...[
                      const SizedBox(height: 4),
                      Text(iuLine, style: AppTheme.sans(size: 11, color: AppTheme.fgMute)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: conc > 0 ? () => Navigator.of(context).pop(conc) : null,
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  color: conc > 0 ? AppTheme.accent : AppTheme.surface2,
                  child: Text('Use this',
                      style: AppTheme.sans(
                          size: 13,
                          weight: FontWeight.w600,
                          color: conc > 0 ? AppTheme.bg : AppTheme.fgDim,
                          letterSpacing: 0.3)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _volField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text('RECONSTITUTION',
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.sans(size: 10, color: AppTheme.fgDim, letterSpacing: 0.8)),
              ),
              const SizedBox(width: 6),
              // Compact mL/IU toggle.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _volUnit = _volUnit == 'mL' ? 'IU' : 'mL'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(border: Border.all(color: AppTheme.border, width: 1)),
                  child: Text(_volUnit,
                      style: AppTheme.mono(size: 10, weight: FontWeight.w600, color: AppTheme.fg)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _vol,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            cursorColor: AppTheme.accent,
            style: AppTheme.serif(
                size: 22, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.4, height: 1.1),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              hintText: '0',
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetField(String label, TextEditingController ctl) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: AppTheme.sans(size: 10, color: AppTheme.fgDim, letterSpacing: 0.8)),
          const SizedBox(height: 4),
          TextField(
            controller: ctl,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            cursorColor: AppTheme.accent,
            style: AppTheme.serif(
                size: 22, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.4, height: 1.1),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              hintText: '0',
            ),
          ),
        ],
      ),
    );
  }
}

class _AddSiteDialog extends StatefulWidget {
  const _AddSiteDialog();

  @override
  State<_AddSiteDialog> createState() => _AddSiteDialogState();
}

class _AddSiteDialogState extends State<_AddSiteDialog> {
  final TextEditingController _ctl = TextEditingController();
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

  void _submit() => Navigator.of(context).pop(_ctl.text.trim());

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
            Text('Add site',
                style: AppTheme.serif(
                    size: 18, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.3)),
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
                cursorColor: AppTheme.accent,
                style: AppTheme.sans(size: 14, color: AppTheme.fg),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  hintText: 'e.g. Lat L',
                  hintStyle: AppTheme.sans(size: 14, color: AppTheme.fgDim),
                ),
                textCapitalization: TextCapitalization.words,
                onSubmitted: (_) => _submit(),
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Text('Cancel',
                        style: AppTheme.sans(size: 13, color: AppTheme.fgMute)),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _submit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    color: AppTheme.accent,
                    child: Text('Add',
                        style: AppTheme.sans(
                            size: 13, weight: FontWeight.w600, color: AppTheme.bg, letterSpacing: 0.3)),
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
