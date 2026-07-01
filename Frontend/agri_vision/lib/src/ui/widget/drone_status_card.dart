import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Reusable stat card used in the drone status row.
/// Shows an icon + label at the top, a value, optional sub-label,
/// and an optional progress bar at the bottom.
///
/// Usage:
///   DroneStatusCard(
///     icon: Icons.battery_5_bar,
///     iconColor: AppColors.themeSuccess,
///     label: 'Battery',
///     value: '84%',
///     progress: 0.84,
///     progressColor: AppColors.themeSuccess,
///   )
class DroneStatusCard extends StatelessWidget {
  const DroneStatusCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.subLabel,
    this.progress,
    this.progressColor,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? subLabel;

  /// 0.0 – 1.0. When non-null a thin progress bar is shown at bottom.
  final double? progress;
  final Color? progressColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // icon + label row
          Row(
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark100,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          // value
          Text(value, style: AppTextStyle.text2xlBold),

          // optional sub-label (e.g. "sats")
          if (subLabel != null)
            Text(
              subLabel!,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark100,
              ),
            ),

          // optional progress bar
          if (progress != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: AppColors.light500,
                valueColor: AlwaysStoppedAnimation<Color>(
                  progressColor ?? iconColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
