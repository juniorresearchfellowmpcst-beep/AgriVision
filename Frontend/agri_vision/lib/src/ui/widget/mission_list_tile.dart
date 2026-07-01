import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';
import 'mission_status_badge.dart';

/// Data class for a single mission row.
class MissionItem {
  const MissionItem({
    required this.title,
    required this.date,
    required this.area,
    required this.status,
  });

  final String title;
  final String date;
  final String area;
  final MissionStatus status;
}

/// Single tappable row in the "Recent Missions" list.
/// Uses [AppIconButton]-inspired design: white card, left icon,
/// stacked title/subtitle, status badge, chevron.
class MissionListTile extends StatelessWidget {
  const MissionListTile({super.key, required this.mission, this.onTap});

  final MissionItem mission;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md + 2,
        ),
        decoration: BoxDecoration(
          color: AppColors.light100,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: AppColors.dark900.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // location pin icon badge
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primaryFade,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(
                Icons.location_on_outlined,
                size: 20,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),

            // title + date · area
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mission.title, style: AppTextStyle.textMdSemibold),
                  const SizedBox(height: 3),
                  Text(
                    '${mission.date} · ${mission.area}',
                    style: AppTextStyle.textSmRegular.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),

            MissionStatusBadge(status: mission.status),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.chevron_right, size: 18, color: AppColors.light900),
          ],
        ),
      ),
    );
  }
}
