import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Reusable grouped settings card — renders a section label above
/// a white rounded card containing any list of child rows.
///
/// Usage:
///   SettingsSectionCard(
///     label: 'CONNECTIVITY',
///     children: [...],
///   )
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    super.key,
    required this.label,
    required this.children,
  });

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // section label
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            label,
            style: AppTextStyle.textXsSemibold.copyWith(
              color: AppColors.dark100,
              letterSpacing: 0.8,
            ),
          ),
        ),

        // white card
        Container(
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
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    indent: AppSpacing.lg,
                    endIndent: AppSpacing.lg,
                    color: AppColors.light500,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
