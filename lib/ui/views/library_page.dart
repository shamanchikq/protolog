import 'package:flutter/material.dart';
import '../../models.dart';
import '../../engine/library_stats.dart';
import '../theme.dart';
import '../widgets/lab_primitives.dart';
import '../widgets/library_row.dart';
import '../widgets/library_section.dart';

enum _LibFilter { all, steroid, oral, peptide, ancillary }

class LibraryPage extends StatefulWidget {
  final List<CompoundDefinition> userCompounds;
  final List<Injection> injections;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final void Function(CompoundDefinition compound) onOpenDetail;
  final VoidCallback onOpenCreate;

  const LibraryPage({
    super.key,
    required this.userCompounds,
    required this.injections,
    required this.onExport,
    required this.onImport,
    required this.onOpenDetail,
    required this.onOpenCreate,
  });

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  _LibFilter _filter = _LibFilter.all;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final protocol = protocolCompounds(
      userCompounds: widget.userCompounds,
      injections: widget.injections,
      now: now,
    );
    final catalogue = cataloguedCompounds(userCompounds: widget.userCompounds);
    final customCount = widget.userCompounds.where((c) => c.isCustom).length;

    final protocolFiltered =
        protocol.where((c) => _matchesFilter(c)).toList();
    final catalogueFiltered =
        catalogue.where((c) => _matchesFilter(c)).toList();

    final statsLine = widget.injections.isEmpty
        ? '${catalogue.length} compounds · 0 in protocol'
        : '${catalogue.length} compounds · ${protocol.length} in protocol'
            '${customCount > 0 ? " · $customCount custom" : ""}';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            statsLine: statsLine,
            onExport: widget.onExport,
            onImport: widget.onImport,
            onCreate: widget.onOpenCreate,
          ),
          const SizedBox(height: 14),
          _FilterStrip(
            value: _filter,
            onChange: (f) => setState(() => _filter = f),
          ),
          const SizedBox(height: 18),
          LibrarySection(
            title: 'In your protocol',
            meta: protocol.isEmpty ? '0' : '${protocolFiltered.length}',
            child: _protocolBody(protocolFiltered, protocol.isEmpty),
          ),
          const SizedBox(height: 18),
          LibrarySection(
            title: 'All compounds',
            meta: '${catalogueFiltered.length}',
            child: _catalogueBody(catalogueFiltered),
          ),
        ],
      ),
    );
  }

  bool _matchesFilter(CompoundDefinition c) {
    switch (_filter) {
      case _LibFilter.all: return true;
      case _LibFilter.steroid: return c.type == CompoundType.steroid;
      case _LibFilter.oral: return c.type == CompoundType.oral;
      case _LibFilter.peptide: return c.type == CompoundType.peptide;
      case _LibFilter.ancillary: return c.type == CompoundType.ancillary;
    }
  }

  Widget _protocolBody(List<CompoundDefinition> rows, bool overallEmpty) {
    if (overallEmpty) {
      return _ProtocolEmpty();
    }
    if (rows.isEmpty) {
      return _BorderedSurface(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Center(
            child: Text(
              'No ${_filterLabel().toLowerCase()} in protocol.',
              style: AppTheme.sans(size: 12, color: AppTheme.fgDim),
            ),
          ),
        ),
      );
    }
    return _BorderedSurface(child: _rowList(rows, showUsed: true));
  }

  Widget _catalogueBody(List<CompoundDefinition> rows) {
    if (rows.isEmpty) {
      return _BorderedSurface(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Center(
            child: Text(
              'No ${_filterLabel().toLowerCase()} compounds.',
              style: AppTheme.sans(size: 12, color: AppTheme.fgDim),
            ),
          ),
        ),
      );
    }
    return _BorderedSurface(child: _rowList(rows, showUsed: false));
  }

  Widget _rowList(List<CompoundDefinition> rows, {required bool showUsed}) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      final c = rows[i];
      if (i > 0) {
        children.add(const Divider(height: 1, thickness: 1, color: AppTheme.borderSoft));
      }
      final last = lastInjectionFor(
        base: c.base, ester: c.ester, injections: widget.injections,
      );
      children.add(LibraryRow(
        name: displayName(c),
        meta: metaLineFor(c),
        stripeColor: AppTheme.compoundColor(c.base) ?? Color(c.colorValue),
        isCustom: c.isCustom,
        usedAgo: showUsed ? formatUsedAgo(last) : null,
        onTap: () => widget.onOpenDetail(c),
      ));
    }
    return Column(children: children);
  }

  String _filterLabel() {
    switch (_filter) {
      case _LibFilter.all: return 'compound';
      case _LibFilter.steroid: return 'Steroid';
      case _LibFilter.oral: return 'Oral';
      case _LibFilter.peptide: return 'Peptide';
      case _LibFilter.ancillary: return 'Ancillary';
    }
  }
}

class _Header extends StatelessWidget {
  final String statsLine;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final VoidCallback onCreate;
  const _Header({
    required this.statsLine,
    required this.onExport,
    required this.onImport,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Library',
                style: AppTheme.serif(
                  size: 26, weight: FontWeight.w500,
                  color: AppTheme.fg, letterSpacing: -0.5, height: 1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                statsLine,
                style: AppTheme.sans(size: 11, color: AppTheme.fgMute),
              ),
            ],
          ),
        ),
        _ImportExportPill(onExport: onExport, onImport: onImport),
        const SizedBox(width: 6),
        LabPill(label: '+ New', primary: true, onTap: onCreate),
      ],
    );
  }
}

class _ImportExportPill extends StatelessWidget {
  final VoidCallback onExport;
  final VoidCallback onImport;
  const _ImportExportPill({required this.onExport, required this.onImport});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      color: AppTheme.surface2,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      position: PopupMenuPosition.under,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.border, width: 1),
      ),
      onSelected: (v) {
        if (v == 'export') onExport();
        if (v == 'import') onImport();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'export',
          child: Text('Export log to clipboard',
              style: AppTheme.sans(size: 12, color: AppTheme.fg)),
        ),
        PopupMenuItem(
          value: 'import',
          child: Text('Import log from clipboard',
              style: AppTheme.sans(size: 12, color: AppTheme.fg)),
        ),
      ],
      child: const LabPill(label: 'Import / export'),
    );
  }
}

class _FilterStrip extends StatelessWidget {
  final _LibFilter value;
  final ValueChanged<_LibFilter> onChange;
  const _FilterStrip({required this.value, required this.onChange});

  static const _items = [
    (_LibFilter.all, 'All'),
    (_LibFilter.steroid, 'Steroid'),
    (_LibFilter.oral, 'Oral'),
    (_LibFilter.peptide, 'Peptide'),
    (_LibFilter.ancillary, 'Ancillary'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            LabPill(
              label: _items[i].$2,
              active: value == _items[i].$1,
              onTap: () => onChange(_items[i].$1),
            ),
          ],
        ],
      ),
    );
  }
}

class _BorderedSurface extends StatelessWidget {
  final Widget child;
  const _BorderedSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: child,
    );
  }
}

class _ProtocolEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border, width: 1, style: BorderStyle.solid),
      ),
      // Note: Flutter has no native dashed border. Solid border with surface bg
      // approximates the JSX. A custom painter for dashed could come later.
      child: Column(
        children: [
          Icon(Icons.radio_button_unchecked,
              size: 32, color: AppTheme.fgMute.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            'No active protocol',
            style: AppTheme.serif(
              size: 17, weight: FontWeight.w500, color: AppTheme.fg,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 240,
            child: Text(
              'Pick a compound below to log your first injection — or add a custom with + New.',
              textAlign: TextAlign.center,
              style: AppTheme.sans(size: 12, color: AppTheme.fgMute, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
