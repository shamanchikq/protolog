import 'package:flutter/material.dart';
import '../theme.dart';

/// One catalogue/protocol row: colored stripe · name (+custom tag) · meta ·
/// used-ago (in-protocol section only) · chevron.
class LibraryRow extends StatelessWidget {
  final String name;
  final String meta;
  final Color stripeColor;
  final bool isCustom;
  final String? usedAgo; // null → column rendered empty
  final VoidCallback onTap;

  const LibraryRow({
    super.key,
    required this.name,
    required this.meta,
    required this.stripeColor,
    required this.onTap,
    this.isCustom = false,
    this.usedAgo,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(width: 3, height: 26, color: stripeColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: AppTheme.sans(
                            size: 13, weight: FontWeight.w500, color: AppTheme.fg,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCustom) ...[
                        const SizedBox(width: 8),
                        Text(
                          'custom',
                          style: AppTheme.sans(size: 10, color: AppTheme.warm),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: AppTheme.sans(size: 11, color: AppTheme.fgMute),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            if (usedAgo != null)
              Text(
                usedAgo!,
                style: AppTheme.sans(size: 11, color: AppTheme.accent),
              ),
            const SizedBox(width: 14),
            Text(
              '›',
              style: AppTheme.sans(size: 16, color: AppTheme.fgDim),
            ),
          ],
        ),
      ),
    );
  }
}
