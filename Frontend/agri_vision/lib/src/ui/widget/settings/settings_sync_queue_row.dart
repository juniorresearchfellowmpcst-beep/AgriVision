import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

enum SyncStatus { synced, pending }

/// A sync queue row showing a label and item count, with a
/// green check (synced) or spinning/pending amber circle icon.
class SyncQueueRow extends StatelessWidget {
  const SyncQueueRow({
    super.key,
    required this.label,
    required this.count,
    required this.status,
  });

  final String label;
  final int count;
  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final isSynced = status == SyncStatus.synced;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          // status icon
          Icon(
            isSynced ? Icons.check_circle_rounded : Icons.pending_outlined,
            size: 20,
            color: isSynced ? AppColors.themeSuccess : AppColors.themeWarning,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(label, style: AppTextStyle.textMdMedium)),
          Text(
            '$count items',
            style: AppTextStyle.textSmRegular.copyWith(
              color: AppColors.dark100,
            ),
          ),
        ],
      ),
    );
  }
}
