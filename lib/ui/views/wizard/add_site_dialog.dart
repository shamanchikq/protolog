import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../widgets/lab_tap.dart';
import '../../widgets/tap_target.dart';

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
    return TapTargetScope(
      child: Dialog(
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
                    hintStyle: AppTheme.sans(size: 14, color: AppTheme.fgDimText),
                  ),
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(height: 8),
              Text('Long-press a site you added to remove it.',
                  style: AppTheme.sans(size: 11, color: AppTheme.fgDimText)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  LabTap(
                    onTap: () => Navigator.of(context).pop(null),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Text('Cancel',
                          style: AppTheme.sans(size: 13, color: AppTheme.fgMute)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  LabTap(
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
      ),
    );
  }
}

/// Asks whether to remove the custom injection [site]. Resolves to true on
/// Remove, false on Cancel / dismiss.
Future<bool> showRemoveSiteDialog(BuildContext context, String site) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => RemoveSiteDialog(site: site),
  );
  return result ?? false;
}

class RemoveSiteDialog extends StatelessWidget {
  final String site;

  const RemoveSiteDialog({super.key, required this.site});

  @override
  Widget build(BuildContext context) {
    return TapTargetScope(
      child: Dialog(
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
              Text('Remove site?',
                  style: AppTheme.serif(
                      size: 18, weight: FontWeight.w500, color: AppTheme.fg, letterSpacing: -0.3)),
              const SizedBox(height: 10),
              Text('"$site" leaves your site list. Past logs keep it.',
                  style: AppTheme.sans(size: 13, color: AppTheme.fgMute)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  LabTap(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Text('Cancel', style: AppTheme.sans(size: 13, color: AppTheme.fgMute)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  LabTap(
                    onTap: () => Navigator.of(context).pop(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Text('Remove',
                          style: AppTheme.sans(
                              size: 13, weight: FontWeight.w600, color: AppTheme.warn, letterSpacing: 0.3)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
