import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Dark-green highlighted card showing the drone currently assigned
/// to this pilot: unit name, connection status, and a battery / tank /
/// flights stat row.
class AssignedDroneCard extends StatelessWidget {
  const AssignedDroneCard({super.key, required this.drone});

  final AssignedDroneEntity drone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.darkGreen,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.light100.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(
                  Icons.flight_rounded,
                  color: AppColors.light100,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      drone.unitName,
                      style: AppTextStyle.textMdSemibold.copyWith(
                        color: AppColors.light100,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'SN: ${drone.serialNumber} · ${drone.frequency}',
                      style: AppTextStyle.textSmRegular.copyWith(
                        color: AppColors.light100.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: drone.isConnected
                      ? const Color(0xFF5FE08A)
                      : AppColors.themeError,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${drone.isConnected ? 'Connected' : 'Offline'} · ${drone.signalDbm}',
                style: AppTextStyle.textSmMedium.copyWith(
                  color: AppColors.light100.withOpacity(0.85),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _DroneStatChip(
                  value: '${drone.batteryPercent}%',
                  label: 'Battery',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _DroneStatChip(
                  value: '${drone.tankPercent}%',
                  label: 'Tank',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _DroneStatChip(
                  value: '${drone.totalFlights}',
                  label: 'Flights',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DroneStatChip extends StatelessWidget {
  const _DroneStatChip({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm + 2,
        horizontal: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.light100.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: AppTextStyle.textLgBold.copyWith(color: AppColors.light100),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyle.textXsRegular.copyWith(
              color: AppColors.light100.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
