import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// A single settings row with a leading icon, a label, and an optional
/// trailing widget (status text, toggle, chevron, etc.).
///
/// Used for: Network, Drone Telemetry, Mission logs, etc.
class SettingsNavRow extends StatelessWidget {
  const SettingsNavRow({
    super.key,
    required this.icon,
    required this.label,
    this.iconColor,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;

  /// Anything on the right — Text, Switch, Badge, etc.
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md + 2,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? AppColors.dark500),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(label, style: AppTextStyle.textMdMedium)),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
