import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Settings row with a [Switch] on the right. Use for toggleable
/// options like Auto Sync, Push Notifications.
class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor ?? AppColors.dark500),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(label, style: AppTextStyle.textMdMedium)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.light100,
            activeTrackColor: AppColors.primary,
            inactiveThumbColor: AppColors.light100,
            inactiveTrackColor: AppColors.light700,
            trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
          ),
        ],
      ),
    );
  }
}
