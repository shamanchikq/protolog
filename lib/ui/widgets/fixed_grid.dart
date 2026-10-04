import 'package:flutter/material.dart';

/// A non-scrolling grid with the geometry of a shrink-wrapped
/// `GridView` + `SliverGridDelegateWithFixedCrossAxisCount`, built as rows.
///
/// Unlike that GridView it doesn't clip its cells' semantics to its own
/// bounds, so cells on the edges keep their full 48 dp touch areas (see
/// TapTarget) — a scrollable's viewport trims them to the grid.
class FixedGrid extends StatelessWidget {
  const FixedGrid({
    super.key,
    required this.crossAxisCount,
    required this.itemCount,
    required this.itemBuilder,
    this.mainAxisSpacing = 0,
    this.crossAxisSpacing = 0,
    this.mainAxisExtent,
    this.childAspectRatio = 1,
  });

  final int crossAxisCount;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double mainAxisSpacing;
  final double crossAxisSpacing;

  /// Row height; when null, a cell's width / [childAspectRatio].
  final double? mainAxisExtent;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cellWidth =
          (constraints.maxWidth - crossAxisSpacing * (crossAxisCount - 1)) / crossAxisCount;
      final rowHeight = mainAxisExtent ?? cellWidth / childAspectRatio;
      final rows = (itemCount / crossAxisCount).ceil();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var r = 0; r < rows; r++) ...[
            if (r > 0) SizedBox(height: mainAxisSpacing),
            SizedBox(
              height: rowHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < crossAxisCount; c++) ...[
                    if (c > 0) SizedBox(width: crossAxisSpacing),
                    Expanded(
                      child: r * crossAxisCount + c < itemCount
                          ? itemBuilder(context, r * crossAxisCount + c)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    });
  }
}
