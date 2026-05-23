import 'package:flutter/material.dart';
import '../theme.dart';

enum ShellTab { today, calendar, library, reminders }

class ProtoLogShell extends StatelessWidget {
  final ShellTab activeTab;
  final ValueChanged<ShellTab> onTabChanged;
  final VoidCallback? onFabPressed;
  final Widget body;

  const ProtoLogShell({
    super.key,
    required this.activeTab,
    required this.onTabChanged,
    this.onFabPressed,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _TopBar(active: activeTab, onChange: onTabChanged),
                Expanded(child: body),
              ],
            ),
            if (onFabPressed != null)
              Positioned(
                right: 18,
                bottom: 18,
                child: _Fab(onPressed: onFabPressed!),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final ShellTab active;
  final ValueChanged<ShellTab> onChange;
  const _TopBar({required this.active, required this.onChange});

  static const _tabs = <(ShellTab, String)>[
    (ShellTab.today, 'Today'),
    (ShellTab.calendar, 'Calendar'),
    (ShellTab.library, 'Library'),
    (ShellTab.reminders, 'Reminders'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.accent, width: 1.4),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('protolog', style: AppTheme.sans(size: 16, weight: FontWeight.w600, letterSpacing: -0.3)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final (tab, label) in _tabs)
                _Tab(label: label, active: active == tab, onTap: () => onChange(tab)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Tab({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.only(top: 10, bottom: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AppTheme.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: AppTheme.sans(
            size: 13,
            weight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? AppTheme.fg : AppTheme.fgMute,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}

class _Fab extends StatelessWidget {
  final VoidCallback onPressed;
  const _Fab({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          color: AppTheme.accent,
          boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 20, offset: Offset(0, 6))],
        ),
        child: Center(
          child: Text(
            '+',
            style: AppTheme.sans(size: 26, weight: FontWeight.w300, color: AppTheme.bg, height: 1),
          ),
        ),
      ),
    );
  }
}
