import 'package:flutter/material.dart';
import '../theme.dart';

/// Section header (title + optional meta count/label) above a child container.
/// Title uses 13/600 sans; meta uses 11 fgDim sans, right-aligned.
class LibrarySection extends StatelessWidget {
  final String title;
  final String? meta;
  final Widget child;

  const LibrarySection({
    super.key,
    required this.title,
    this.meta,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: AppTheme.sans(
                  size: 13, weight: FontWeight.w600, color: AppTheme.fg,
                ),
              ),
              if (meta != null && meta!.isNotEmpty)
                Text(
                  meta!,
                  style: AppTheme.sans(size: 11, color: AppTheme.fgDim),
                ),
            ],
          ),
        ),
        child,
      ],
    );
  }
}
