import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Small rounded pill showing alert severity (High / Medium / Low)
/// with appropriate background and text colour from [AlertSeverityX].
class AlertSeverityBadge extends StatelessWidget {
  const AlertSeverityBadge({super.key, required this.severity});

  final AlertSeverity severity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: severity.badgeBackground,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        severity.label,
        style: AppTextStyle.textXsBold.copyWith(color: severity.badgeText),
      ),
    );
  }
}
