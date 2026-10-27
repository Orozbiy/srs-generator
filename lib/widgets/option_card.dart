import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Тандоо үчүн жалпы карта (предмет, тил, барак саны).
class OptionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? glyph;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  /// Узак басуу же оң баскыч (мис. картаны өчүрүү үчүн).
  final VoidCallback? onLongPress;

  const OptionCard({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.subtitle,
    this.glyph,
    this.color = AppTheme.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTap: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.08) : AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? color : AppTheme.line,
              width: selected ? 1.8 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.16),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    )
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (glyph != null) ...[
                Text(
                  glyph!,
                  style: TextStyle(
                    fontSize: 22,
                    color: selected ? color : AppTheme.muted,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? color : AppTheme.ink,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: selected
                        ? color.withValues(alpha: 0.8)
                        : AppTheme.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Бөлүмдүн аталышы.
class SectionLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? trailing;

  const SectionLabel(this.icon, this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.ink,
              letterSpacing: -0.1,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
