import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

enum MissionStatus { done, partial, inProgress, scheduled }

extension MissionStatusX on MissionStatus {
  String get label => switch (this) {
    MissionStatus.done => 'Done',
    MissionStatus.partial => 'Partial',
    MissionStatus.inProgress => 'In Progress',
    MissionStatus.scheduled => 'Scheduled',
  };

  Color get backgroundColor => switch (this) {
    MissionStatus.done => const Color(0xFFDCF0DE),
    MissionStatus.partial => const Color(0xFFFBEAC7),
    MissionStatus.inProgress => const Color(0xFFDDEAFB),
    MissionStatus.scheduled => AppColors.light500,
  };

  Color get textColor => switch (this) {
    MissionStatus.done => const Color(0xFF1E7A33),
    MissionStatus.partial => const Color(0xFF9A6A0B),
    MissionStatus.inProgress => const Color(0xFF1E5A9A),
    MissionStatus.scheduled => AppColors.dark300,
  };
}

/// Small rounded pill for mission status (Done / Partial / In Progress).
class MissionStatusBadge extends StatelessWidget {
  const MissionStatusBadge({super.key, required this.status});

  final MissionStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: status.backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        status.label,
        style: AppTextStyle.textXsSemibold.copyWith(color: status.textColor),
      ),
    );
  }
}
