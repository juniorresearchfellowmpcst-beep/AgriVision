import 'package:flutter/material.dart';

import 'package:agri_vision/src/core/core.dart';
import 'package:agri_vision/src/domain/entity/spray_prescription.dart';
import 'package:agri_vision/src/domain/entity/survey_entity.dart';

/// The K-means treatment map, and the costed options built on it.
///
/// Two things this card refuses to hide:
///
///   * **Which evidence the map rests on.** A map clustered from a calibrated
///     vegetation index and one clustered from where the aircraft happened to
///     be when the CNN saw something are not equally strong, and the operator
///     is about to commit chemical on the strength of one of them.
///   * **A uniform field.** K-means always names a worst cluster, even in a
///     block where nothing is actually worse. That is the failure mode that
///     quietly sends a drone out to spray a healthy field.
class TreatmentMapCard extends StatelessWidget {
  const TreatmentMapCard({
    required this.map,
    required this.selectedOption,
    required this.onSelectOption,
    super.key,
  });

  final TreatmentMap map;
  final String? selectedOption;
  final ValueChanged<String> onSelectOption;

  static Map<String, Color> _severityColors = {
    'severe': AppColors.themeError,
    'moderate': AppColors.themeWarning,
    'healthy': AppColors.themeSuccess,
  };

  bool get _fromDetections => map.source == 'rgb_detections';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.light500),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.map_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Treatment map',
                  style: AppTextStyle.textMdSemibold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  'K-means · k=${map.zones.length}',
                  style: AppTextStyle.textXsSemibold.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _fromDetections
                ? 'Clustered from where the CNN found problems along the flight '
                  'line. The patch outlines are spray footprints, not the edge '
                  'of the infection.'
                : 'Clustered from the ${map.indexName.isEmpty ? "vegetation index" : map.indexName} '
                  'across the captured frame — the more accurate of the two maps.',
            style: AppTextStyle.textXsRegular.copyWith(
              color: AppColors.dark300,
              height: 1.4,
            ),
          ),

          if (map.mapUrl != null) ...[
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Image.network(
                map.mapUrl!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  height: 120,
                  color: AppColors.light300,
                  alignment: Alignment.center,
                  child: Text(
                    'Map image unavailable',
                    style: AppTextStyle.textXsRegular.copyWith(
                      color: AppColors.dark300,
                    ),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.md),
          _ZoneBar(zones: map.zones),

          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              for (final zone in map.zones)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _severityColors[zone.severity] ?? AppColors.dark100,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${zone.severity} · ${zone.frames} '
                      '${_fromDetections ? "frames" : "px"}',
                      style: AppTextStyle.textXsRegular.copyWith(
                        color: AppColors.dark300,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // K-means names a worst cluster even in a block where nothing is
          // worse. This is the note that stops a healthy field being sprayed.
          if (map.lowContrast) ...[
            const SizedBox(height: AppSpacing.md),
            _Note(
              icon: Icons.warning_amber_rounded,
              color: AppColors.themeWarning,
              text: 'This field looks fairly uniform. K-means still named a '
                  'worst zone, but there may be nothing genuinely wrong with '
                  'it — walk the block before spraying on this.',
            ),
          ],

          if (!map.canGeoreference) ...[
            const SizedBox(height: AppSpacing.md),
            _Note(
              icon: Icons.gps_off,
              color: AppColors.themeError,
              text: 'This map has no position data, so it cannot be turned '
                  'into spray waypoints. Connect the flight link before the '
                  'survey so frames are geotagged as they are scanned.',
            ),
          ],

          if (map.targetedOptions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text('How much to treat', style: AppTextStyle.textSmSemibold),
            const SizedBox(height: AppSpacing.sm),
            for (final option in map.targetedOptions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _OptionRow(
                  option: option,
                  selected: option.id == (selectedOption ?? map.recommendedOption?.id),
                  onTap: () => onSelectOption(option.id),
                ),
              ),
          ],

          if (map.assumptions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'How the coordinates were worked out',
              style: AppTextStyle.textXsSemibold.copyWith(
                color: AppColors.dark300,
              ),
            ),
            for (final assumption in map.assumptions)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '• $assumption',
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark100,
                    height: 1.35,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// The split of the field across the three classes, as one bar.
class _ZoneBar extends StatelessWidget {
  const _ZoneBar({required this.zones});

  final List<TreatmentZone> zones;

  @override
  Widget build(BuildContext context) {
    final total = zones.fold<int>(0, (sum, zone) => sum + zone.frames);
    if (total == 0) return const SizedBox.shrink();

    // Worst first, so the bar reads left to right in the order that matters.
    const order = ['severe', 'moderate', 'healthy'];
    final sorted = [...zones]
      ..sort((a, b) => order.indexOf(a.severity).compareTo(order.indexOf(b.severity)));

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            for (final zone in sorted)
              Expanded(
                flex: zone.frames == 0 ? 1 : zone.frames,
                child: ColoredBox(
                  color: TreatmentMapCard._severityColors[zone.severity] ??
                      AppColors.dark100,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final SprayOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.md);

    return Material(
      color: selected ? AppColors.primary.withOpacity(0.08) : AppColors.light300,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 1.4,
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18,
                color: selected ? AppColors.primary : AppColors.dark100,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            option.label,
                            style: AppTextStyle.textSmSemibold,
                          ),
                        ),
                        if (option.recommended)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(AppRadius.full),
                            ),
                            child: Text(
                              'Recommended',
                              style: AppTextStyle.textXsSemibold.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (option.detail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        option.detail,
                        style: AppTextStyle.textXsRegular.copyWith(
                          color: AppColors.dark300,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        _Stat(
                          label: 'Treated',
                          value: '${option.treatedPercent}%',
                        ),
                        _Stat(
                          label: 'Chemical saved',
                          value: '${option.savingPercent}%',
                          highlight: option.savingPercent > 0,
                        ),
                        if (option.chemicalL != null)
                          _Stat(
                            label: 'Needs',
                            value: '${option.chemicalL!.toStringAsFixed(1)} L',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTextStyle.textSmSemibold.copyWith(
              color: highlight ? AppColors.themeSuccess : AppColors.dark700,
            ),
          ),
          Text(
            label,
            style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark100),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTextStyle.textXsRegular.copyWith(
                color: AppColors.dark500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
