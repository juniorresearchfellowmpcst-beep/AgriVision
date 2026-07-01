import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Translucent pill shown in the dark-green header indicating the
/// current GCS connection status, frequency, and signal strength.
class GcsConnectionBanner extends StatelessWidget {
  const GcsConnectionBanner({
    super.key,
    required this.gcsId,
    required this.frequency,
    required this.signalDbm,
    this.isConnected = true,
  });

  final String gcsId;
  final String frequency;
  final String signalDbm;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.light100.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          // live dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isConnected
                  ? const Color(0xFF5FE08A)
                  : AppColors.themeError,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '$gcsId Connected · $frequency',
              style: AppTextStyle.textSmMedium.copyWith(
                color: AppColors.light100,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(Icons.wifi, size: 14, color: AppColors.primary3),
          const SizedBox(width: 4),
          Text(
            signalDbm,
            style: AppTextStyle.textSmMedium.copyWith(
              color: AppColors.primary3,
            ),
          ),
        ],
      ),
    );
  }
}
