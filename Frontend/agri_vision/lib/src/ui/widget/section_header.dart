import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Row with a bold section title on the left and an optional tappable
/// action label on the right.
///
/// Usage:
///   SectionHeader(
///     title: 'Recent Missions',
///     actionLabel: 'View Reports',
///     onAction: () => ...,
///   )
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: AppTextStyle.textLgBold),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel!,
              style: AppTextStyle.textSmSemibold.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
      ],
    );
  }
}
