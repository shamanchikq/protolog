import 'package:flutter/material.dart';
import '../theme.dart';

/// Pill button used for filter chips, header actions, secondary buttons.
/// `primary` inverts to fg/bg with bold weight. `danger` paints warn-colored
/// border + text. `active` is the "selected filter chip" state.
class LabPill extends StatelessWidget {
  final String label;
  final bool active;
  final bool primary;
  final bool danger;
  final bool disabled;
  final VoidCallback? onTap;

  const LabPill({
    super.key,
    required this.label,
    this.active = false,
    this.primary = false,
    this.danger = false,
    this.disabled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = active ? AppTheme.fg : Colors.transparent;
    final Color fg = disabled
        ? AppTheme.fgDim
        : danger
            ? AppTheme.warn
            : primary
                ? AppTheme.fg
                : active
                    ? AppTheme.bg
                    : AppTheme.fgMute;
    final Color bd = danger
        ? AppTheme.warn
        : primary
            ? AppTheme.fg
            : active
                ? AppTheme.fg
                : AppTheme.border;
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(color: bg, border: Border.all(color: bd, width: 1)),
          child: Text(
            label,
            style: AppTheme.sans(
              size: 11.5,
              weight: active || primary ? FontWeight.w600 : FontWeight.w400,
              color: fg,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Boxed form field with an uppercase microlabel + optional right-side hint.
/// Caller supplies the input widget as `child`.
class LabField extends StatelessWidget {
  final String label;
  final String? hint;
  final Widget child;
  final bool focused;
  final bool disabled;
  final VoidCallback? onTap;

  const LabField({
    super.key,
    required this.label,
    this.hint,
    required this.child,
    this.focused = false,
    this.disabled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: disabled ? Colors.transparent : AppTheme.surface,
            border: Border.all(color: focused ? AppTheme.fg : AppTheme.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: AppTheme.sans(
                      size: 9.5, color: AppTheme.fgDim, letterSpacing: 0.9,
                    ),
                  ),
                  if (hint != null && hint!.isNotEmpty)
                    Text(hint!,
                      style: AppTheme.mono(size: 10, color: AppTheme.fgDim)),
                ],
              ),
              const SizedBox(height: 4),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal segmented control. Active = inverted (fg bg, bg text).
class LabSegmented<T> extends StatelessWidget {
  final T value;
  final List<T> options;
  final String Function(T) labelFor;
  final ValueChanged<T> onChange;
  final bool mono;

  const LabSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.labelFor,
    required this.onChange,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppTheme.border, width: 1)),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            Expanded(child: _segment(options[i], i)),
          ],
        ],
      ),
    );
  }

  Widget _segment(T opt, int i) {
    final isSelected = opt == value;
    return GestureDetector(
      onTap: () => onChange(opt),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.fg : Colors.transparent,
          border: i == 0 ? null : const Border(
            left: BorderSide(color: AppTheme.border, width: 1),
          ),
        ),
        child: Center(
          child: Text(
            labelFor(opt),
            style: mono
                ? AppTheme.mono(
                    size: 11.5,
                    weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? AppTheme.bg : AppTheme.fgMute,
                    letterSpacing: 0.2,
                  )
                : AppTheme.sans(
                    size: 11.5,
                    weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? AppTheme.bg : AppTheme.fgMute,
                    letterSpacing: 0.2,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Compact metric tile — uppercase label + mono numeric value + optional unit.
class LabMetric extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final bool compact;

  const LabMetric({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 11 : 12,
        compact ? 10 : 12,
        compact ? 11 : 12,
        compact ? 9 : 11,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTheme.sans(size: 9, color: AppTheme.fgDim, letterSpacing: 1.1),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: AppTheme.mono(
                  size: compact ? 17 : 20,
                  weight: FontWeight.w500,
                  color: AppTheme.fg,
                  letterSpacing: -0.3,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 3),
                Text(unit!, style: AppTheme.sans(size: 10.5, color: AppTheme.fgMute)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
