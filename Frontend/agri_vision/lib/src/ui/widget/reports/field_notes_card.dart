import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// White card showing field notes text with an Edit button,
/// and Previous / page indicator / Next pagination controls below.
class FieldNotesCard extends StatelessWidget {
  const FieldNotesCard({
    super.key,
    required this.notes,
    required this.currentPage,
    required this.totalPages,
    this.onEdit,
    this.onPrevious,
    this.onNext,
  });

  final String notes;
  final int currentPage;
  final int totalPages;
  final VoidCallback? onEdit;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // notes card
        Container(
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Field Notes', style: AppTextStyle.textLgBold),
                  AppIconButton(
                    label: 'Edit',
                    color: AppColors.light100,
                    pressedColor: AppColors.light300,
                    borderColor: AppColors.light700,
                    pressedBorderColor: AppColors.primary,
                    textColor: AppColors.dark700,
                    pressedTextColor: AppColors.primary,
                    textStyle: AppTextStyle.textSmMedium,
                    height: 30,
                    borderRadius: AppRadius.md,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 4,
                    ),
                    mainAxisAlignment: MainAxisAlignment.center,
                    onPressed: onEdit ?? () {},
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              Text(
                notes,
                style: AppTextStyle.textMdRegular.copyWith(
                  color: AppColors.dark500,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // pagination row
        Row(
          children: [
            // Previous
            Expanded(
              child: AppIconButton(
                label: 'Previous',
                startIcon: Icons.arrow_back,
                color: AppColors.light100,
                pressedColor: AppColors.light300,
                borderColor: AppColors.light700,
                pressedBorderColor: AppColors.primary,
                textColor: currentPage > 1
                    ? AppColors.dark700
                    : AppColors.dark100,
                pressedTextColor: AppColors.primary,
                iconColor: currentPage > 1
                    ? AppColors.dark700
                    : AppColors.dark100,
                pressedIconColor: AppColors.primary,
                textStyle: AppTextStyle.textSmMedium,
                height: 40,
                borderRadius: AppRadius.md,
                mainAxisAlignment: MainAxisAlignment.center,
                onPressed: currentPage > 1 ? onPrevious : null,
              ),
            ),
            const SizedBox(width: AppSpacing.md),

            // page indicator
            Text(
              '$currentPage / $totalPages',
              style: AppTextStyle.textSmMedium.copyWith(
                color: AppColors.dark300,
              ),
            ),
            const SizedBox(width: AppSpacing.md),

            // Next
            Expanded(
              child: AppIconButton(
                label: 'Next',
                endIcon: Icons.arrow_forward,
                color: AppColors.light100,
                pressedColor: AppColors.light300,
                borderColor: AppColors.light700,
                pressedBorderColor: AppColors.primary,
                textColor: currentPage < totalPages
                    ? AppColors.dark700
                    : AppColors.dark100,
                pressedTextColor: AppColors.primary,
                iconColor: currentPage < totalPages
                    ? AppColors.dark700
                    : AppColors.dark100,
                pressedIconColor: AppColors.primary,
                textStyle: AppTextStyle.textSmMedium,
                height: 40,
                borderRadius: AppRadius.md,
                mainAxisAlignment: MainAxisAlignment.center,
                onPressed: currentPage < totalPages ? onNext : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
