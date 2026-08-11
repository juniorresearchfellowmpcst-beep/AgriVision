import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Card showing the currently paired drone unit with a live dot
/// and a connect / pair button below.
///
/// With nothing paired ([serialNumber] null) it says so plainly — no unit
/// name, no status dot — and the button offers to connect one.
class DronePairingCard extends StatelessWidget {
  const DronePairingCard({
    super.key,
    this.unitName,
    this.serialNumber,
    this.isOnline = false,
    this.onPairNew,
  });

  final String? unitName;
  final String? serialNumber;
  final bool isOnline;
  final VoidCallback? onPairNew;

  bool get _isPaired => serialNumber != null;

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
                child: _isPaired
                    ? Text(
                        (unitName ?? 'D').trim().isEmpty
                            ? 'D'
                            : unitName!.trim()[0].toUpperCase(),
                        style: AppTextStyle.textLgBold.copyWith(
                          color: AppColors.dark500,
                        ),
                      )
                    : const DroneIcon(size: 22, color: AppColors.dark300),
              ),
              const SizedBox(width: AppSpacing.md),

              // name + serial
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isPaired ? unitName ?? 'Drone' : 'No drone paired',
                      style: AppTextStyle.textMdSemibold,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isPaired
                          ? 'SN: $serialNumber · ${isOnline ? 'Online' : 'Offline'}'
                          : 'Connect an aircraft to see live telemetry.',
                      style: AppTextStyle.textSmRegular.copyWith(
                        color: AppColors.dark300,
                      ),
                    ),
                  ],
                ),
              ),

              // live dot — only meaningful once something is paired
              if (_isPaired)
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

        // Connect / pair button
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: AppIconButton(
            label: _isPaired ? 'Manage Drone Connection' : 'Connect Drone',
            startIcon: Icons.link_rounded,
            color: AppColors.light100,
            pressedColor: AppColors.light300,
            borderColor: AppColors.light700,
            pressedBorderColor: AppColors.primary,
            textColor: AppColors.dark700,
            pressedTextColor: AppColors.primary,
            iconColor: AppColors.dark500,
            pressedIconColor: AppColors.primary,
            textStyle: AppTextStyle.textMdSemibold,
            iconSize: 17,
            width: double.infinity,
            height: 44,
            // 12 + 20 (line height) + 12 = the 44 this button is meant to be.
            // The default 14px vertical padding overshoots it and the label
            // gets clipped away.
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            borderRadius: AppRadius.md,
            mainAxisAlignment: MainAxisAlignment.center,
            onPressed: onPairNew ?? () {},
          ),
        ),
      ],
    );
  }
}
