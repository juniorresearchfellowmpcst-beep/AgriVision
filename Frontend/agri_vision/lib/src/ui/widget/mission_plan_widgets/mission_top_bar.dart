import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Translucent dark top app bar showing:
///  - Back button
///  - Field name + area + waypoint count
///  - Layer switcher icon
class MissionTopBar extends StatelessWidget {
  const MissionTopBar({
    super.key,
    required this.fieldName,
    required this.areHa,
    required this.waypointCount,
    required this.activeLayer,
    required this.onBack,
    required this.onLayerTap,
  });

  final String fieldName;
  final double areHa;
  final int waypointCount;
  final MapLayer activeLayer;
  final VoidCallback onBack;
  final VoidCallback onLayerTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1A3A28).withOpacity(0.92),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // back
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.light100.withOpacity(0.10),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: AppColors.light100,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),

          // location pin
          Icon(Icons.location_on_rounded, size: 14, color: AppColors.primary3),
          const SizedBox(width: AppSpacing.xs),

          // field info
          Expanded(
            child: Text(
              '$fieldName · ${areHa.toStringAsFixed(1)} ha · $waypointCount waypoints',
              style: AppTextStyle.textSmSemibold.copyWith(
                color: AppColors.light100,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // layer switcher
          GestureDetector(
            onTap: onLayerTap,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.25),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.5),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.layers_rounded,
                size: 16,
                color: AppColors.light100,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Layer selector bottom sheet ────────────────────────────────────────────

class LayerSelectorSheet extends StatelessWidget {
  const LayerSelectorSheet({
    super.key,
    required this.activeLayer,
    required this.onSelect,
  });

  final MapLayer activeLayer;
  final ValueChanged<MapLayer> onSelect;

  static void show(
    BuildContext context, {
    required MapLayer activeLayer,
    required ValueChanged<MapLayer> onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          LayerSelectorSheet(activeLayer: activeLayer, onSelect: onSelect),
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
            'Map Layer',
            style: AppTextStyle.textLgBold.copyWith(color: AppColors.light100),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: MapLayer.values
                .map(
                  (l) => Expanded(
                    child: GestureDetector(
                      onTap: () {
                        onSelect(l);
                        Navigator.pop(context);
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        decoration: BoxDecoration(
                          color: l == activeLayer
                              ? AppColors.primary.withOpacity(0.25)
                              : AppColors.light100.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: l == activeLayer
                              ? Border.all(color: AppColors.primary, width: 1.5)
                              : null,
                        ),
                        child: Column(
                          children: [
                            Icon(
                              l.icon,
                              size: 22,
                              color: l == activeLayer
                                  ? AppColors.primary
                                  : AppColors.light100,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              l.label,
                              style: AppTextStyle.textXsSemibold.copyWith(
                                color: l == activeLayer
                                    ? AppColors.primary
                                    : AppColors.light100.withOpacity(0.7),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
