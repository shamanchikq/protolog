import 'package:flutter/material.dart';
import '../../theme.dart';

/// Asks for a custom injection site name. Resolves to the trimmed text on
/// Add / keyboard submit (possibly empty), or null on Cancel / dismiss.
Future<String?> showAddSiteDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => const AddSiteDialog(),
  );
}

class AddSiteDialog extends StatefulWidget {
  const AddSiteDialog({super.key});

  @override
  State<AddSiteDialog> createState() => _AddSiteDialogState();
}

class _AddSiteDialogState extends State<AddSiteDialog> {
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
