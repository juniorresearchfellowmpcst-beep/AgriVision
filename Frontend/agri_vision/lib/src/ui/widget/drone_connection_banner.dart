import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Translucent pill shown in the dark-green header indicating the
/// current GCS connection status, frequency, and signal strength.
///
/// The wording follows [isConnected] rather than assuming a link: with
/// nothing on the wire it reads "Not connected · Tap to connect" and [onTap]
/// opens the connect flow.
class GcsConnectionBanner extends StatelessWidget {
  const GcsConnectionBanner({
    super.key,
    required this.gcsId,
    required this.frequency,
    required this.signalDbm,
    this.isConnected = true,
    this.onTap,
  });

  final String gcsId;
  final String frequency;
  final String signalDbm;
  final bool isConnected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
                isConnected
                    ? '$gcsId Connected · $frequency'
                    : '$gcsId · Not connected'
                          '${onTap == null ? '' : ' · Tap to connect'}',
                style: AppTextStyle.textSmMedium.copyWith(
                  color: AppColors.light100,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              isConnected ? Icons.wifi : Icons.wifi_off_rounded,
              size: 14,
              color: isConnected ? AppColors.primary3 : AppColors.themeError,
            ),
            const SizedBox(width: 4),
            Text(
              signalDbm,
              style: AppTextStyle.textSmMedium.copyWith(
                color: isConnected ? AppColors.primary3 : AppColors.themeError,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
