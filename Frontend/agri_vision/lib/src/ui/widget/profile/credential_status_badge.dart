import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Small rounded pill showing a pilot credential's status
/// (Valid / Expiring / Expired).
class CredentialStatusBadge extends StatelessWidget {
  const CredentialStatusBadge({super.key, required this.status});

  final CredentialStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: status.badgeBackground,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        status.label,
        style: AppTextStyle.textXsBold.copyWith(color: status.badgeText),
      ),
    );
  }
}
