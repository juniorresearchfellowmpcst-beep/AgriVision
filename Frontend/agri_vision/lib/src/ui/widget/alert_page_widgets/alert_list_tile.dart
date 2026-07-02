import 'package:agri_vision/src/ui/widget/alert_page_widgets/alert_severity_badge.dart';
import 'package:agri_vision/src/ui/widget/alert_page_widgets/alert_severity_icon.dart';
import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

///
/// Shows:
///  - [AlertSeverityIcon]   circular coloured icon (left)
///  - Title + location      (centre-left)
///  - Time                  (top-right)
///  - [AlertSeverityBadge]  severity pill · area · confidence (bottom row)
///  - Chevron               (right)
class AlertListTile extends StatelessWidget {
  const AlertListTile({super.key, required this.alert, this.onTap});

  final AlertEntity alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md + 2,
        ),
        decoration: BoxDecoration(
          color: AppColors.light100,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: AppColors.dark900.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Severity icon ───────────────────────────────────────
            AlertSeverityIcon(severity: alert.severity),
            const SizedBox(width: AppSpacing.md),

            // ── Main content ────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // title row + time
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          alert.title,
                          style: AppTextStyle.textMdSemibold,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        alert.time,
                        style: AppTextStyle.textXsRegular.copyWith(
                          color: AppColors.dark100,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),

                  // location
                  Text(
                    alert.location,
                    style: AppTextStyle.textSmRegular.copyWith(
                      color: AppColors.dark300,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // severity badge · area · confidence
                  Row(
                    children: [
                      AlertSeverityBadge(severity: alert.severity),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        alert.area,
                        style: AppTextStyle.textSmMedium.copyWith(
                          color: AppColors.dark300,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        alert.confidence,
                        style: AppTextStyle.textSmBold.copyWith(
                          color: AppColors.dark500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),

            // ── Chevron ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.light900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
