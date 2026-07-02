import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

enum ReportStatus { complete, inProgress, scheduled }

extension ReportStatusX on ReportStatus {
  String get label => switch (this) {
    ReportStatus.complete => 'Complete',
    ReportStatus.inProgress => 'In Progress',
    ReportStatus.scheduled => 'Scheduled',
  };

  Color get background => switch (this) {
    ReportStatus.complete => AppColors.primaryFade,
    ReportStatus.inProgress => const Color(0xFFDDEAFB),
    ReportStatus.scheduled => AppColors.light500,
  };

  Color get textColor => switch (this) {
    ReportStatus.complete => AppColors.primary,
    ReportStatus.inProgress => const Color(0xFF1E5A9A),
    ReportStatus.scheduled => AppColors.dark300,
  };
}

class ReportStatusBadge extends StatelessWidget {
  const ReportStatusBadge({super.key, required this.status});
  final ReportStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: status.textColor.withOpacity(0.3), width: 1),
      ),
      child: Text(
        status.label,
        style: AppTextStyle.textSmSemibold.copyWith(color: status.textColor),
      ),
    );
  }
}
