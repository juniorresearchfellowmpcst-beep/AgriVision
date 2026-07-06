import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Icon + uppercase label + value row used in the PERSONAL DETAILS and
/// PILOT CREDENTIALS section cards. An optional [trailing] widget (e.g.
/// a [CredentialStatusBadge]) can be shown on the right.
class ProfileDetailRow extends StatelessWidget {
  const ProfileDetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.iconBackground,
    this.iconColor,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconBackground;
  final Color? iconColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconBackground ?? AppColors.primaryFade,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, size: 18, color: iconColor ?? AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyle.textXsSemibold.copyWith(
                    color: AppColors.primary,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(value, style: AppTextStyle.textMdSemibold),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}
