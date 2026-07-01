import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Green rounded pill showing the count of active alerts.
/// Shown in the top-right of the Alerts page app bar.
///
/// Usage:
///   AlertActiveChip(count: 5)
class AlertActiveChip extends StatelessWidget {
  const AlertActiveChip({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryFade,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: AppColors.primary3, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.xs + 1),
          Text(
            '$count Active',
            style: AppTextStyle.textSmSemibold.copyWith(
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
