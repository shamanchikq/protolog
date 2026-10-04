import 'package:flutter/material.dart';
import '../../models.dart';
import '../../utils.dart';
import '../../engine/calendar.dart';
import '../../engine/dose_math.dart';
import '../../engine/injection_draft.dart';
import '../../services/custom_sites_store.dart';
import '../theme.dart';
import 'wizard/add_site_dialog.dart';
import 'wizard/compound_step.dart';
import 'wizard/details_widgets.dart';
import 'wizard/dose_section.dart';
import 'wizard/reconstitution_sheet.dart';
import 'wizard/site_section.dart';
import 'wizard/sticky_bar.dart';
import 'wizard/when_section.dart';

/// Full-screen flow for logging a dose: step 1 picks the compound
/// (`wizard/compound_step.dart`), step 2 takes dose, time, site and notes.
///
/// This state object owns all draft state and wires the pieces together:
/// pure draft logic lives in `engine/injection_draft.dart` (pre-fill and the
/// Injection that Confirm produces), the sections in `wizard/`, custom-site
/// persistence in `services/custom_sites_store.dart`.
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

  /// Live base → display color (MainScreen's resolver), so a library recolor
  /// shows on the compound cards, rows and chip (B26). Without one, the
  /// static palette and then the compound's stored color.
  final Color Function(String base)? colorResolver;

  /// Where the user's custom injection sites are kept (a test seam).
  final CustomSitesStore sitesStore;

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
    this.colorResolver,
    this.sitesStore = const CustomSitesStore(),
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
  // The log's day and clock time, edited separately in the When section.
  // Both start from one rounded timestamp (B24: 23:58 → tomorrow 00:00).
  late DateTime _date;
  late TimeOfDay _time;
  String _site = defaultIntramuscularSite;
  String _notes = '';
  Injection? _lastForCompound;

  bool _advanceReminder = true;

  // Custom sites loaded from SharedPreferences, keyed by route.
  CustomSites _customSites = const CustomSites();

  bool get _isEdit => widget.editingInjection != null;

  Reminder? get _matchingReminder {
    if (_isEdit) return null; // editing history never advances reminders
    return linkedReminderFor(compound: _selectedCompound, reminders: widget.reminders);
  }

  // Text controllers for fields whose initial value comes from state.
  late final TextEditingController _doseController = TextEditingController(text: _doseText);
  late final TextEditingController _volumeController = TextEditingController();
  late final TextEditingController _notesController = TextEditingController();
  late final TextEditingController _concController = TextEditingController();
  // Step 1's search box: outlives the step so Back shows the query (B29).
  late final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _setWhen(defaultLogTime(now: DateTime.now(), day: widget.prefillDate));
    _loadCustomSites();
    // Prefill is pure, so edit / prefilled modes start on the details step
    // from the very first frame (no step-1 flash).
    final editing = widget.editingInjection;
    final pre = widget.prefillCompound;
    if (editing != null) {
      _applyEdit(editing);
    } else if (pre != null) {
      _applyNewLog(pre);
    }
  }

  @override
  void dispose() {
    _doseController.dispose();
    _volumeController.dispose();
    _notesController.dispose();
    _concController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Sets the When section's day and clock time from one timestamp.
  void _setWhen(DateTime at) {
    _date = dateOnly(at);
    _time = TimeOfDay.fromDateTime(at);
  }

  // ── Entering the details step ──────────────────────────────────────────────

  /// Moves to the details step for a new log of [c] (step 1's pick).
  void _enterStep2(CompoundDefinition c) => setState(() => _applyNewLog(c));

  /// Loads the details step for a new log of [c] (see [prefillNewLog]).
  /// Call inside setState, or from initState.
  void _applyNewLog(CompoundDefinition c) {
    _applyPrefill(
      prefillNewLog(
        picked: c,
        userCompounds: widget.userCompounds,
        injections: widget.injections,
      ),
      at: defaultLogTime(now: DateTime.now(), day: widget.prefillDate),
      notes: '',
    );
  }

  /// Loads the details step from an existing injection (edit mode, called
  /// from initState). Unlike [_applyNewLog], the compound is the injection's
  /// own frozen snapshot — editing a log must never silently
  /// re-canonicalize its PK.
  void _applyEdit(Injection inj) {
    _applyPrefill(
      prefillEdit(inj),
      at: inj.date,
      notes: inj.notes ?? '',
    );
    _advanceReminder = false;
  }

  /// Loads a [DraftPrefill] into the details-step state and moves to step 2.
  /// Call inside setState, or from initState.
  void _applyPrefill(
    DraftPrefill p, {
    required DateTime at,
    required String notes,
  }) {
    final c = p.compound;
    _selectedCompound = c;
    _lastForCompound = p.lastLog;
    _unit = p.unit;
    _mode = 'direct';
    _doseText = p.dose != null ? formatAmount(p.dose!) : '';
    _doseController.text = _doseText;
    _volumeText = '';
    _volumeController.text = '';
    _notes = notes;
    _notesController.text = notes;
    _concentrationDraft = c.concentration;
    _concController.text = c.concentration != null ? formatAmount(c.concentration!) : '';
    _site = p.site;
    _setWhen(at);
    _step = 2;
  }

  // ── Details-step handlers ──────────────────────────────────────────────────

  bool get _isPillForm {
    final c = _selectedCompound;
    return c != null && isPillFormType(c.type);
  }

  // Sub-Q route covers peptides (incl. hCG, which we treat as a peptide).
  bool get _isSubQ => _selectedCompound?.type == CompoundType.peptide;
  bool get _isIuNative => _selectedCompound?.unit == Unit.iu;
  bool get _isPeptideUnit => _unit == Unit.mcg || _unit == Unit.iu;

  void _setMode(String v) => setState(() {
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
      });

  void _setVolumeInputUnit(String v) => setState(() {
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
      });

  Future<void> _openReconstitutionSheet() async {
    final c = _selectedCompound;
    if (c == null) return;
    final result = await showReconstitutionSheet(
      context,
      isPeptide: _isPeptideUnit,
      doseUnit: _unit,
      massUnitLabel: _isIuNative ? 'IU' : 'mg',
    );
    if (!mounted) return; // the wizard closed while the sheet was open
    if (result != null && result > 0 && !isConcentrationTooHigh(result)) {
      setState(() => _concentrationDraft = result);
    }
  }

  Future<void> _loadCustomSites() async {
    final sites = await widget.sitesStore.load();
    if (!mounted) return;
    setState(() => _customSites = sites);
  }

  /// The sites offered for the current route: built-ins, then the user's.
  List<String> get _routeSites => sitesForRoute(
        subcutaneous: _isSubQ,
        custom: _customSites.forRoute(subcutaneous: _isSubQ),
      );

  Future<void> _promptAddSite() async {
    final result = await showAddSiteDialog(context);
    if (!mounted || result == null || result.isEmpty) return;
    // A name already offered (any case — "quad l") selects that tile
    // instead of adding a duplicate.
    final existing = matchingSite(result, _routeSites);
    if (existing != null) {
      setState(() => _site = existing);
      return;
    }
    setState(() {
      _customSites = _customSites.withSite(result, subcutaneous: _isSubQ);
      _site = result;
    });
    _saveSites(_customSites);
  }

  /// Long-press on a user-added site: confirm, then drop it from the route's
  /// list. Logs that used it keep their site text.
  Future<void> _promptRemoveSite(String site) async {
    final confirmed = await showRemoveSiteDialog(context, site);
    if (!mounted || !confirmed) return;
    final c = _selectedCompound;
    setState(() {
      _customSites = _customSites.withoutSite(site, subcutaneous: _isSubQ);
      if (c != null && matchingSite(_site, [site]) != null) _site = defaultSiteFor(c.type);
    });
    _saveSites(_customSites);
  }

  /// Persists the custom sites. A refused write is reported like any failed
  /// save; the sites stay offered for this session. The messenger is the
  /// app's, so the report survives the wizard closing meanwhile.
  Future<void> _saveSites(CustomSites sites) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (await widget.sitesStore.save(sites)) return;
    messenger?.showSnackBar(SnackBar(
      content: Text("Couldn't save your injection sites — the change may be lost when the app closes.",
          style: AppTheme.sans(size: 12, color: AppTheme.fg)),
      backgroundColor: AppTheme.warn,
      duration: const Duration(seconds: 10),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  /// Whether Android back may close the wizard: only from step 1's base list
  /// — or in edit mode, which has no step 1 (B25).
  bool get _backClosesWizard => _isEdit || (_step == 1 && _selectedBase == null);

  /// Android back inside the wizard: step 2 → step 1 (keeping the filter and
  /// drill-down, like the Back button), ester drill-down → base list.
  void _stepBack() {
    if (_step == 2) {
      setState(() => _step = 1);
    } else if (_selectedBase != null) {
      setState(() => _selectedBase = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _backClosesWizard,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stepBack();
      },
      child: Scaffold(
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
      ),
    );
  }

  Widget _buildStep1() {
    return CompoundStep(
      typeFilter: _typeFilter,
      selectedBase: _selectedBase,
      searchQuery: _searchQuery,
      searchController: _searchController,
      userCompounds: widget.userCompounds,
      injections: widget.injections,
      onTypeFilterChanged: (key) => setState(() {
        _typeFilter = key;
        _selectedBase = null;
      }),
      onSearchChanged: (v) => setState(() => _searchQuery = v),
      onSelectBase: (base) => setState(() => _selectedBase = base),
      onPick: _enterStep2,
      onCancel: widget.onCancel,
      colorResolver: widget.colorResolver,
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
        DetailsHeader(
          isEdit: _isEdit,
          // In edit mode there is no step 1 to go back to — close instead.
          onBack: _isEdit ? widget.onCancel : () => setState(() => _step = 1),
        ),
        const SizedBox(height: 16),
        SelectedCompoundChip(
          compound: c,
          concentration: _concentrationDraft,
          onChange: _isEdit ? null : () => setState(() => _step = 1),
          colorResolver: widget.colorResolver,
        ),
        if (_lastForCompound != null) ...[
          const SizedBox(height: 6),
          LastLogLine(last: _lastForCompound!),
        ],
        const SizedBox(height: 18),
        DoseSection(
          compound: c,
          mode: _mode,
          unit: _unit,
          doseText: _doseText,
          volumeText: _volumeText,
          volumeInputUnit: _volumeInputUnit,
          concentration: _concentrationDraft,
          doseController: _doseController,
          volumeController: _volumeController,
          concController: _concController,
          onModeChanged: _setMode,
          onDoseChanged: (v) => setState(() => _doseText = v),
          onUnitChanged: (u) => setState(() => _unit = u),
          onVolumeChanged: (v) => setState(() => _volumeText = v),
          onVolumeInputUnitChanged: _setVolumeInputUnit,
          onConcentrationChanged: (v) => setState(() => _concentrationDraft = v),
          onOpenReconstitution: _openReconstitutionSheet,
          onVolumeDoseComputed: (text) {
            if (!mounted) return;
            setState(() => _doseText = text);
          },
        ),
        const SizedBox(height: 18),
        WhenSection(
          date: _date,
          time: _time,
          onDateChanged: (d) => setState(() => _date = d),
          onTimeChanged: (t) => setState(() => _time = t),
        ),
        const SizedBox(height: 18),
        if (_isPillForm)
          const SizedBox.shrink()
        else
          SiteSection(
            sites: _routeSites,
            // Only tiles the user added; a stored copy of a built-in is hidden.
            removableSites: {
              for (final s in _routeSites)
                if (!(_isSubQ ? builtInSitesSubQ : builtInSitesIM).contains(s)) s,
            },
            selected: _site,
            lastSite: lastSiteFor(base: c.base, injections: widget.injections),
            onSelect: (s) => setState(() => _site = s),
            onAddSite: _promptAddSite,
            onRemoveSite: _promptRemoveSite,
          ),
        if (!_isPillForm) const SizedBox(height: 18),
        NotesSection(
          controller: _notesController,
          onChanged: (v) => _notes = v,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  /// N5: a concentration over the limit is flagged inline in By-volume mode,
  /// where it would feed the dose, and Confirm waits for a fix. A direct
  /// dose doesn't use it (and buildNewLog never stores it).
  bool get _concentrationBlocksConfirm =>
      _mode == 'volume' && !_isPillForm && isConcentrationTooHigh(_concentrationDraft);

  /// G5: a soft warning when the dose is > 3× or < ⅓ of the last log of this
  /// compound (no last log in edit mode, so none there).
  String? get _doseWarning {
    final last = _lastForCompound;
    final dose = parseFlexibleDouble(_doseText);
    if (last == null || dose == null) return null;
    final ratio = unusualDoseRatio(dose: dose, unit: _unit, last: last);
    return ratio == null ? null : unusualDoseMessage(ratio, last);
  }

  Widget _buildStickyBar() {
    return WizardStickyBar(
      compound: _selectedCompound,
      doseText: _doseText,
      unit: _unit,
      site: _site,
      isEdit: _isEdit,
      doseWarning: _doseWarning,
      submitBlocked: _concentrationBlocksConfirm,
      linkedReminder: _matchingReminder,
      advanceReminder: _advanceReminder,
      onToggleAdvance: () => setState(() => _advanceReminder = !_advanceReminder),
      onSubmit: _submit,
    );
  }

  // ── Confirm ────────────────────────────────────────────────────────────────

  void _submit() {
    final picked = _selectedCompound;
    if (picked == null || _concentrationBlocksConfirm) return;
    final doseVal = parseFlexibleDouble(_doseText);
    if (doseVal == null || doseVal <= 0) return;
    final fullDate = logDateTime(_date, hour: _time.hour, minute: _time.minute);

    // Edit mode: replace the log in place (see buildEditedLog).
    final editing = widget.editingInjection;
    if (editing != null) {
      widget.onEdit?.call(buildEditedLog(
        original: editing,
        dosage: doseVal,
        unit: _unit,
        date: fullDate,
        site: _site,
        notes: _notes,
      ));
      widget.onSuccess();
      return;
    }

    // File the log under the user copy, adopting/updating it as needed.
    final log = buildNewLog(
      compound: picked,
      userCompounds: widget.userCompounds,
      dosage: doseVal,
      unit: _unit,
      date: fullDate,
      site: _site,
      notes: _notes,
      concentrationDraft: _concentrationDraft,
      now: DateTime.now(),
    );
    final upsert = log.compoundUpsert;
    if (upsert != null) widget.addUserCompound(upsert);
    widget.onAdd(log.injection, _matchingReminder != null && _advanceReminder);
    widget.onSuccess();
  }
}
