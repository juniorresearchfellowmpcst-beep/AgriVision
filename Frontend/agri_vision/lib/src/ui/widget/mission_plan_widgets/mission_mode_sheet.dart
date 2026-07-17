import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Modal bottom sheet shown before launch: pick the flight profile.
///
/// Two modes (see [MissionMode]):
///  - High-Speed Survey  → multispectral assessment
///  - Low-Pace Scouting  → weed / pest / disease detection
class MissionModeSheet extends StatelessWidget {
  const MissionModeSheet({super.key, required this.onSelect});

  final ValueChanged<MissionMode> onSelect;

  static void show(
    BuildContext context, {
    required ValueChanged<MissionMode> onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => MissionModeSheet(onSelect: onSelect),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: const Color(0xFF1A3A28),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose Mission Mode',
            style: AppTextStyle.textLgBold.copyWith(color: AppColors.light100),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final mode in MissionMode.values) ...[
            _ModeCard(
              mode: mode,
              onTap: () {
                Navigator.pop(context);
                onSelect(mode);
              },
            ),
            if (mode != MissionMode.values.last)
              const SizedBox(height: AppSpacing.md),
          ],
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode, required this.onTap});

  final MissionMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.light100.withOpacity(0.07),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.35),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(mode.icon, size: 24, color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          mode.label,
                          style: AppTextStyle.textMdSemibold.copyWith(
                            color: AppColors.light100,
                          ),
                        ),
                      ),
                      Text(
                        '${mode.speed.toStringAsFixed(0)} m/s',
                        style: AppTextStyle.textXsBold.copyWith(
                          color: const Color(0xFFE7B10A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mode.description,
                    style: AppTextStyle.textXsRegular.copyWith(
                      color: AppColors.light100.withOpacity(0.65),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.light100.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }
}
