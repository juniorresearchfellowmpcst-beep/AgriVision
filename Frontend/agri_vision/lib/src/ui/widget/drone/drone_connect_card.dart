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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark900.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      // Side by side where there is room, stacked where there is not.
      //
      // The button sizes to its label, so on a 320 dp phone "Connect Drone"
      // plus the icon plus the text column did not fit and the row overflowed
      // by a couple of pixels — the yellow-and-black stripe, on the home
      // screen, in the state a brand-new install starts in. Shrinking the
      // label instead would give "Connect Dro…" on the one control the
      // operator has to find.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final icon = Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.light500,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: DroneIcon(size: 20, color: AppColors.dark300),
          );

          final text = Column(
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
          );

          AppIconButton button({required double? width}) => AppIconButton(
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
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            borderRadius: AppRadius.full,
            mainAxisAlignment: MainAxisAlignment.center,
            onPressed: onConnect,
          );

          // Roughly: icon + gaps + a readable text column + the button. Below
          // this the row cannot hold all three without squeezing something
          // that should not be squeezed.
          const sideBySideMin = 320.0;
          if (constraints.maxWidth >= sideBySideMin) {
            return Row(
              children: [
                icon,
                const SizedBox(width: AppSpacing.md),
                Expanded(child: text),
                const SizedBox(width: AppSpacing.sm),
                button(width: null),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  icon,
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: text),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              button(width: double.infinity),
            ],
          );
        },
      ),
    );
  }
}