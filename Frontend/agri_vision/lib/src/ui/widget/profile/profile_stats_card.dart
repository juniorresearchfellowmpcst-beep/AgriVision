import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// White rounded card with 3 divided stat columns (Missions / Area
/// Flown / Air Time), shown overlapping the bottom edge of
/// [ProfileHeader].
class ProfileStatsCard extends StatelessWidget {
  const ProfileStatsCard({
    super.key,
    required this.missionsFlown,
    required this.areaFlownHa,
    required this.airTimeHours,
  });

  final int missionsFlown;
  final int areaFlownHa;
  final int airTimeHours;

  @override
  Widget build(BuildContext context) {
    return Container(
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
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _StatCell(value: '$missionsFlown', label: 'Missions'),
            ),
            const _VDivider(),
            Expanded(
              child: _StatCell(value: '$areaFlownHa ha', label: 'Area Flown'),
            ),
            const _VDivider(),
            Expanded(
              child: _StatCell(value: '$airTimeHours hr', label: 'Air Time'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: AppTextStyle.text2xlBold),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark300),
        ),
      ],
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: double.infinity,
      child: VerticalDivider(width: 1, thickness: 1, color: AppColors.light500),
    );
  }
}
