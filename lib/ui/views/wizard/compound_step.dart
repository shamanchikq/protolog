import 'package:flutter/material.dart';
import '../../../models.dart';
import '../../theme.dart';
import 'compound_catalog.dart';
import 'wizard_widgets.dart';

/// Step 1 of the add-injection wizard: header, search, type filters, Recent
/// cards and the library list with the steroid base → ester drill-down.
///
/// Stateless: the wizard owns the filter / drill-down / query — and the
/// search box's controller, so the box still shows the query that filters
/// after a trip to step 2 and Back (B29).
class CompoundStep extends StatelessWidget {
  /// 'steroid' | 'oral' | 'peptide' | 'ancillary'.
  final String typeFilter;

  /// Non-null when drilled into a steroid base.
  final String? selectedBase;
  final String searchQuery;

  /// The search box's controller, owned (and disposed) by the wizard; its
  /// text is [searchQuery].
  final TextEditingController searchController;
  final List<CompoundDefinition> userCompounds;
  final List<Injection> injections;
  final ValueChanged<String> onTypeFilterChanged;
  final ValueChanged<String> onSearchChanged;

  /// Drill into a steroid base, or out of it with null.
  final ValueChanged<String?> onSelectBase;

  /// A compound was chosen: go to the details step.
  final ValueChanged<CompoundDefinition> onPick;
  final VoidCallback onCancel;

  /// Live base → color resolver (see [wizardCompoundColor]).
  final Color Function(String base)? colorResolver;

  const CompoundStep({
    super.key,
    required this.typeFilter,
    required this.selectedBase,
    required this.searchQuery,
    required this.searchController,
    required this.userCompounds,
    required this.injections,
    required this.onTypeFilterChanged,
    required this.onSearchChanged,
    required this.onSelectBase,
    required this.onPick,
    required this.onCancel,
    this.colorResolver,
  });

  CompoundType get _targetType => typeForFilter(typeFilter);

  int _esterCount(String base) => esterCountForBase(base, userCompounds);

  void _onCompoundTap(CompoundDefinition c) {
    // Steroid base list with multi-ester → drill in
    if (c.type == CompoundType.steroid && selectedBase == null) {
      if (_esterCount(c.base) > 1) {
        onSelectBase(c.base);
        return;
      }
    }
    // Otherwise advance to Step 2.
    onPick(c);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
          child: _buildHeader(),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _buildSearchBar(),
        ),
        const SizedBox(height: 14),
        if (selectedBase == null) ...[
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

  Widget _buildHeader() {
    final title = selectedBase ?? 'Select compound';
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
                  if (selectedBase != null)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelectBase(null),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text('‹',
                            style: AppTheme.serif(
                                size: 22, weight: FontWeight.w500, color: AppTheme.fgMute, letterSpacing: -0.4)),
                      ),
                    ),
                  Flexible(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.serif(
                            size: 22, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.4)),
                  ),
                ],
              ),
            ],
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onCancel,
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
              controller: searchController,
              onChanged: onSearchChanged,
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
    // A Wrap, not a Row: at large text sizes the pills flow onto a second
    // line instead of overflowing (C1). One line at the default size.
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final (key, label) in filters)
          WizardPill(
            label: label,
            active: typeFilter == key,
            onTap: () => onTypeFilterChanged(key),
          ),
      ],
    );
  }

  Widget _buildRecentSection() {
    // Hidden during steroid drill-down and while searching.
    if (selectedBase != null || searchQuery.trim().isNotEmpty) return const SizedBox.shrink();
    final items = recentCompounds(
      type: _targetType,
      injections: injections,
      userCompounds: userCompounds,
    );
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WizardSectionTitle('Recent'),
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
    final color = wizardCompoundColor(compound, colorResolver);
    String sub;
    if (compound.type == CompoundType.steroid) {
      final n = _esterCount(compound.base);
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
            Text(relativeAgo(lastDate),
                style: AppTheme.sans(size: 10.5, color: AppTheme.accent)),
          ],
        ),
      ),
    );
  }

  Widget _buildLibrarySection() {
    final items = pickerCompounds(
      type: _targetType,
      drillBase: selectedBase,
      query: searchQuery,
      userCompounds: userCompounds,
    );
    if (items.isEmpty) {
      if (searchQuery.trim().isNotEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text('No matches for "$searchQuery"',
                style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('No $typeFilter compounds in library',
              style: AppTheme.sans(size: 12, color: AppTheme.fgMute)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WizardSectionTitle('Library'),
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

  String _libraryRowMeta(CompoundDefinition c) {
    if (c.type == CompoundType.steroid && selectedBase == null) {
      final n = _esterCount(c.base);
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

  Widget _buildLibraryRow(CompoundDefinition c, {required bool isFirst}) {
    final color = wizardCompoundColor(c, colorResolver);
    final showCustom = c.isCustom;
    final nameStr = (_targetType == CompoundType.steroid && selectedBase != null)
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
}
