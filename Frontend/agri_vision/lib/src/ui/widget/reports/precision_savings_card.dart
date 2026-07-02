import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Dark-green "Precision Spray Savings" card.
/// Shows used vs saved amounts and a green progress bar.
class PrecisionSavingsCard extends StatelessWidget {
  const PrecisionSavingsCard({
    super.key,
    required this.usedLitres,
    required this.savedLitres,
    required this.totalLitres,
    required this.savedPercent,
  });

  final double usedLitres;
  final double savedLitres;
  final double totalLitres;
  final int savedPercent;

  @override
  Widget build(BuildContext context) {
    final progress = usedLitres / totalLitres;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: const Color(0xFF1F4D38),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // title row
          Row(
            children: [
              Icon(Icons.eco_outlined, size: 18, color: AppColors.primary3),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Precision Spray Savings',
                style: AppTextStyle.textMdSemibold.copyWith(
                  color: AppColors.light100,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // used · saved row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Used: ${usedLitres}L · Saved: ${savedLitres}L',
                style: AppTextStyle.textSmRegular.copyWith(
                  color: AppColors.primary3,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  '$savedPercent% saved',
                  style: AppTextStyle.textXsSemibold.copyWith(
                    color: AppColors.primary3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: AppColors.dark500,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // scale labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '0 L',
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.primary3,
                ),
              ),
              Text(
                '${totalLitres} L used',
                style: AppTextStyle.textXsRegular.copyWith(
                  color: AppColors.primary3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
