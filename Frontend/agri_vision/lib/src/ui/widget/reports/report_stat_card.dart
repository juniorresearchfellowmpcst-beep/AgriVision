import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Single stat card used in the 2×2 mission summary grid.
/// Shows a small label, a large coloured value, and a sub-label.
///
/// Usage:
///   ReportStatCard(
///     label: 'Area Covered',
///     value: '4.2 ha',
///     valueColor: AppColors.primary,
///     subLabel: '100% complete',
///   )
class ReportStatCard extends StatelessWidget {
  const ReportStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.valueColor,
    required this.subLabel,
  });

  final String label;
  final String value;
  final Color valueColor;
  final String subLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
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
        children: [
          Text(
            label,
            style: AppTextStyle.textXsRegular.copyWith(
              color: AppColors.dark300,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: AppTextStyle.text3xlBold.copyWith(color: valueColor),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            subLabel,
            style: AppTextStyle.textXsRegular.copyWith(
              color: AppColors.dark100,
            ),
          ),
        ],
      ),
    );
  }
}
