import 'package:flutter/material.dart';
import '../../../services/custom_sites_store.dart';
import '../../theme.dart';
import 'wizard_widgets.dart';

/// Intramuscular sites (steroids).
const builtInSitesIM = <String>[
  'Vent. glute L', 'Vent. glute R', 'Quad L',
  'Quad R', 'Delt L', 'Delt R',
];

/// Subcutaneous sites (peptides, hCG).
const builtInSitesSubQ = <String>[
  'Abdominal L', 'Abdominal R', 'Glute L',
  'Glute R', 'Quad L', 'Quad R',
];

/// The route's built-in sites followed by the user's [custom] ones. A custom
/// site that repeats a built-in or an earlier custom one — ignoring case and
/// surrounding spaces (see [matchingSite]) — is left out, so stored
/// duplicates don't show up as a second tile.
List<String> sitesForRoute({required bool subcutaneous, required List<String> custom}) {
  final sites = [...(subcutaneous ? builtInSitesSubQ : builtInSitesIM)];
  for (final c in custom) {
    if (matchingSite(c, sites) == null) sites.add(c);
  }
  return sites;
}

/// "Site" section of the details step: a 3-column grid of [sites] plus an
/// "+ Add site" tile. Tapping the selected site clears the selection;
/// long-pressing one of [removableSites] (the user's own) asks to remove it.
class SiteSection extends StatelessWidget {
  final List<String> sites;

  /// The user-added sites among [sites]; only these can be long-pressed.
  final Set<String> removableSites;

  /// The selected site; '' for none.
  final String selected;

  /// Site of the previous log of this base, shown as "last: …".
  final String? lastSite;
  final ValueChanged<String> onSelect;
  final VoidCallback onAddSite;

  /// A removable site was long-pressed.
  final ValueChanged<String> onRemoveSite;

  const SiteSection({
    super.key,
    required this.sites,
    this.removableSites = const {},
    required this.selected,
    required this.lastSite,
    required this.onSelect,
    required this.onAddSite,
    required this.onRemoveSite,
  });

  @override
  Widget build(BuildContext context) {
    // Total cells = sites + 1 "+ Add site" tile.
    final cellCount = sites.length + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WizardSectionTitle('Site', meta: lastSite != null ? 'last: $lastSite' : null),
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
                onTap: onAddSite,
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
            final active = s == selected;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(active ? '' : s),
              onLongPress: removableSites.contains(s) ? () => onRemoveSite(s) : null,
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
}
