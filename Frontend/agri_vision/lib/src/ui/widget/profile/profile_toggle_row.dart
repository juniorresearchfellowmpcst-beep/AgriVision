import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Title + subtitle row with a [Switch] on the right. Used for
/// notification preference toggles on the Profile page.
class ProfileToggleRow extends StatelessWidget {
  const ProfileToggleRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyle.textMdSemibold),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyle.textSmRegular.copyWith(
                    color: AppColors.dark300,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.light100,
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
