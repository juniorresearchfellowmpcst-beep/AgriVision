import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Shown wherever drone gauges would go when there is nothing to show:
/// no aircraft paired, or paired but not reporting.
///
/// It replaces the readings rather than sitting next to them, so the screen
/// can never be read as "battery 0%" when the truth is "we don't know".
class DroneConnectCard extends StatelessWidget {
  const DroneConnectCard({
    super.key,
    required this.title,
    required this.message,
    required this.onConnect,
    this.actionLabel = 'Connect Drone',
  });

  /// The two states worth distinguishing to the operator.
  factory DroneConnectCard.unpaired({
    Key? key,
    required VoidCallback onConnect,
  }) => DroneConnectCard(
    key: key,
    title: 'No drone connected',
    message: 'Pair your aircraft to see live battery, tank and GPS here.',
    onConnect: onConnect,
  );

  factory DroneConnectCard.offline({
    Key? key,
    required String unitName,
    required VoidCallback onConnect,
  }) => DroneConnectCard(
    key: key,
    title: '$unitName is offline',
    message: 'No telemetry coming in — open the link to see live readings.',
    onConnect: onConnect,
    actionLabel: 'Open Link',
  );

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
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
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.light500,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const DroneIcon(size: 20, color: AppColors.dark300),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyle.textMdSemibold,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark300,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppIconButton(
            label: actionLabel,
            startIcon: Icons.link_rounded,
            color: AppColors.primary,
            pressedColor: AppColors.primary,
            showBorder: false,
            textColor: AppColors.light100,
            pressedTextColor: AppColors.light100,
            iconColor: AppColors.light100,
            pressedIconColor: AppColors.light100,
            textStyle: AppTextStyle.textSmSemibold,
            iconSize: 15,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            borderRadius: AppRadius.full,
            mainAxisAlignment: MainAxisAlignment.center,
            onPressed: onConnect,
          ),
        ],
      ),
    );
  }
}
