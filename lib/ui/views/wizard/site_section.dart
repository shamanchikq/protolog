import 'package:flutter/material.dart';
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

/// The route's built-in sites followed by the user's [custom] ones.
List<String> sitesForRoute({required bool subcutaneous, required List<String> custom}) =>
    [...(subcutaneous ? builtInSitesSubQ : builtInSitesIM), ...custom];

/// "Site" section of the details step: a 3-column grid of [sites] plus an
/// "+ Add site" tile. Tapping the selected site clears the selection.
class SiteSection extends StatelessWidget {
  final List<String> sites;

  /// The selected site; '' for none.
  final String selected;

  /// Site of the previous log of this base, shown as "last: …".
  final String? lastSite;
  final ValueChanged<String> onSelect;
  final VoidCallback onAddSite;

  const SiteSection({
    super.key,
    required this.sites,
    required this.selected,
    required this.lastSite,
    required this.onSelect,
    required this.onAddSite,
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
