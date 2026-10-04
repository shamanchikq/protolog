import 'package:flutter/material.dart';

import '../theme.dart';
import 'tap_target.dart';

/// A tappable Lab Sheet control: [child] drawn exactly as given, announced
/// to screen readers as a button with its state, and touchable over at least
/// 48 × 48 dp inside a [TapTargetScope] (see [TapTarget]).
///
/// The child's text is the spoken label unless [label] replaces it — use one
/// for glyph-only controls ("‹", "×", an icon).
class LabTap extends StatelessWidget {
  const LabTap({
    super.key,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.label,
    this.hint,
    this.tooltip,
    this.selected,
    this.toggled,
    this.checked,
    this.inMutuallyExclusiveGroup = false,
    this.mergeSemantics = true,
  });

  /// Null disables the control (announced as disabled).
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  /// Spoken instead of the child's text.
  final String? label;

  /// Spoken after the label, e.g. what the tap does.
  final String? hint;

  /// Shown on long-press (and spoken), e.g. what a terse label means.
  final String? tooltip;

  /// Choice state (a filter chip, a tab, a range pill); null for a plain
  /// button.
  final bool? selected;

  /// On/off state (a switch-like toggle).
  final bool? toggled;

  /// Checkbox state.
  final bool? checked;

  /// Whether this is one of a set of choices of which one is selected.
  final bool inMutuallyExclusiveGroup;

  /// See [TapTarget.mergeSemantics]: false for a row that holds its own
  /// buttons.
  final bool mergeSemantics;

  @override
  Widget build(BuildContext context) {
    Widget content = label != null ? ExcludeSemantics(child: child) : child;
    content = GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
    content = Semantics(
      button: true,
      enabled: onTap != null || onLongPress != null,
      selected: selected,
      toggled: toggled,
      checked: checked,
      inMutuallyExclusiveGroup: inMutuallyExclusiveGroup ? true : null,
      label: label,
      hint: hint,
      child: content,
    );
    if (tooltip != null) content = LabTooltip(message: tooltip!, child: content);
    return TapTarget(mergeSemantics: mergeSemantics, child: content);
  }
}

/// A long-press tooltip in the Lab Sheet style (sharp, bordered, surface2).
class LabTooltip extends StatelessWidget {
  const LabTooltip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.longPress,
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      textStyle: AppTheme.sans(size: 11.5, color: AppTheme.fg),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: child,
    );
  }
}

/// A text field touchable over at least 48 dp tall (a near miss focuses it,
/// see [TapTarget]) and spoken with [label] — the field's visible
/// microlabel sits outside it, in a LabField / WizardField box.
class LabTextFieldTarget extends StatelessWidget {
  const LabTextFieldTarget({super.key, this.label, required this.child});

  /// Spoken name of the field; null when its hint already says it.
  final String? label;
  final Widget child;

  @override
  Widget build(BuildContext context) => TapTarget(
        child: label == null ? child : Semantics(label: label, child: child),
      );
}
