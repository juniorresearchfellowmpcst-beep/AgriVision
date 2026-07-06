import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Single row in the RECENT ACTIVITY section — a colored dot
/// (keyed off [ActivityType]), title + subtitle, and a timestamp.
class ActivityListTile extends StatelessWidget {
  const ActivityListTile({super.key, required this.activity});

  final ProfileActivityEntity activity;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: activity.type.dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(activity.title, style: AppTextStyle.textMdSemibold),
                const SizedBox(height: 2),
                Text(
                  activity.subtitle,
                  style: AppTextStyle.textSmRegular.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            activity.time,
            style: AppTextStyle.textXsRegular.copyWith(
              color: AppColors.dark100,
            ),
          ),
        ],
      ),
    );
  }
}
