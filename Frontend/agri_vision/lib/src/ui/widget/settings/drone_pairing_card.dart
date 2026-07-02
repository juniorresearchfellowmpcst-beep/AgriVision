import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Card showing the currently paired drone unit with a live dot
/// and a "Pair New Drone" outlined button below.
class DronePairingCard extends StatelessWidget {
  const DronePairingCard({
    super.key,
    required this.unitName,
    required this.serialNumber,
    this.isOnline = true,
    this.onPairNew,
  });

  final String unitName;
  final String serialNumber;
  final bool isOnline;
  final VoidCallback? onPairNew;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // drone row
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md + 2,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              // avatar
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.light500,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  'A',
                  style: AppTextStyle.textLgBold.copyWith(
                    color: AppColors.dark500,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),

              // name + serial
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(unitName, style: AppTextStyle.textMdSemibold),
                    const SizedBox(height: 2),
                    Text(
                      'SN: $serialNumber',
                      style: AppTextStyle.textSmRegular.copyWith(
                        color: AppColors.dark300,
                      ),
                    ),
                  ],
                ),
              ),

              // live dot
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isOnline
                      ? AppColors.themeSuccess
                      : AppColors.themeError,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),

        // divider
        const Divider(
          height: 1,
          thickness: 1,
          indent: AppSpacing.lg,
          endIndent: AppSpacing.lg,
          color: AppColors.light500,
        ),

        // Pair New Drone button
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: AppIconButton(
            label: 'Pair New Drone',
            color: AppColors.light100,
            pressedColor: AppColors.light300,
            borderColor: AppColors.light700,
            pressedBorderColor: AppColors.primary,
            textColor: AppColors.dark700,
            pressedTextColor: AppColors.primary,
            textStyle: AppTextStyle.textMdMedium,
            width: double.infinity,
            height: 44,
            borderRadius: AppRadius.md,
            mainAxisAlignment: MainAxisAlignment.center,
            onPressed: onPairNew ?? () {},
          ),
        ),
      ],
    );
  }
}
