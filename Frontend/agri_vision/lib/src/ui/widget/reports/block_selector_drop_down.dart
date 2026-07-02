import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Dark translucent dropdown pill for selecting which block/field
/// to view in the report header.
class BlockSelectorDropdown extends StatelessWidget {
  const BlockSelectorDropdown({
    super.key,
    required this.selectedBlock,
    required this.blocks,
    required this.onChanged,
  });

  final String selectedBlock;
  final List<String> blocks;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.light100.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.light100.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedBlock,
          items: blocks
              .map(
                (b) => DropdownMenuItem(
                  value: b,
                  child: Text(
                    b,
                    style: AppTextStyle.textSmMedium.copyWith(
                      color: AppColors.light100,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          dropdownColor: const Color(0xFF1F4D38),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.light100,
            size: 18,
          ),
          isDense: true,
          selectedItemBuilder: (context) => blocks
              .map(
                (b) => Row(
                  children: [
                    Icon(
                      Icons.crop_square_outlined,
                      size: 14,
                      color: AppColors.light100,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      b,
                      style: AppTextStyle.textSmMedium.copyWith(
                        color: AppColors.light100,
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
