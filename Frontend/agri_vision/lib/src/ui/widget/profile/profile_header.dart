import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Dark-green header for the Profile page: Back / Edit row, avatar
/// with an online indicator dot, name, and role/organisation badges.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.profile,
    this.onBack,
    this.onEdit,
  });

  final PilotProfileEntity profile;
  final VoidCallback? onBack;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.darkGreen,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl + 14, // extra bottom so the stats card overlaps into it
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.arrow_back,
                      size: 18,
                      color: AppColors.light100,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Back',
                      style: AppTextStyle.textMdSemibold.copyWith(
                        color: AppColors.light100,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs + 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.light100.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: AppColors.light100,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'Edit',
                        style: AppTextStyle.textSmSemibold.copyWith(
                          color: AppColors.light100,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.light100.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 38,
                        backgroundColor: AppColors.primary,
                        child: Text(
                          profile.initials,
                          style: AppTextStyle.displayH3.copyWith(
                            color: AppColors.light100,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: const Color(0xFF5FE08A),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.darkGreen,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  profile.name,
                  style: AppTextStyle.text2xlBold.copyWith(
                    color: AppColors.light100,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Badge(
                      label: profile.role,
                      background: AppColors.primary.withOpacity(0.25),
                      border: AppColors.primary.withOpacity(0.5),
                      textColor: AppColors.primary3,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _Badge(
                      label: profile.organisation,
                      background: AppColors.light100.withOpacity(0.12),
                      border: Colors.transparent,
                      textColor: AppColors.light100,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.background,
    required this.border,
    required this.textColor,
  });

  final String label;
  final Color background;
  final Color border;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: AppTextStyle.textXsSemibold.copyWith(color: textColor),
      ),
    );
  }
}
