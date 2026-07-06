import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Small stat chip used in the bottom sheet quick-stats row.
/// Shows a value + label pair in a light rounded container.
///
/// Usage:
///   MissionStatChip(value: '10', label: 'Waypoints')
class MissionStatChip extends StatelessWidget {
  const MissionStatChip({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
  });

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm + 2,
          horizontal: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.light300,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: AppTextStyle.textLgBold.copyWith(
                color: valueColor ?? AppColors.dark900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark300,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
