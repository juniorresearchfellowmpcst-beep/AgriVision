import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Bar chart card showing detection counts per zone, with a
/// three-category legend (Healthy / Stressed / Diseased).
///
/// [zones] is a list of zone labels; [values] maps each label
/// to a 0–100 percentage of diseased/stressed readings.
/// For a production version swap the custom painter for fl_chart
/// or syncfusion_flutter_charts.
class DetectionByZoneCard extends StatelessWidget {
  const DetectionByZoneCard({
    super.key,
    required this.zones,
    required this.values,
  });

  final List<String> zones;

  /// Value 0–100 controlling bar height.
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Detection by Zone', style: AppTextStyle.textLgBold),
          const SizedBox(height: AppSpacing.lg),

          // bar chart
          SizedBox(
            height: 140,
            child: _BarChart(zones: zones, values: values),
          ),
          const SizedBox(height: AppSpacing.lg),

          // legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendDot(color: AppColors.themeSuccess, label: 'Healthy'),
              const SizedBox(width: AppSpacing.lg),
              _LegendDot(color: AppColors.themeWarning, label: 'Stressed'),
              const SizedBox(width: AppSpacing.lg),
              _LegendDot(color: AppColors.themeError, label: 'Diseased'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppTextStyle.textXsRegular.copyWith(color: AppColors.dark300),
        ),
      ],
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.zones, required this.values});
  final List<String> zones;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    const maxVal = 100.0;
    const yLabels = ['100', '75', '50', '25', '0'];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // y-axis labels
        Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: yLabels
              .map(
                (l) => Text(
                  l,
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark100,
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(width: AppSpacing.sm),

        // bars + x labels
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(zones.length, (i) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Flexible(
                              child: FractionallySizedBox(
                                heightFactor: values[i] / maxVal,
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.themeError,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // horizontal grid line
              Container(height: 1, color: AppColors.light500),
              const SizedBox(height: AppSpacing.xs),

              // x labels
              Row(
                children: zones
                    .map(
                      (z) => Expanded(
                        child: Text(
                          z,
                          textAlign: TextAlign.center,
                          style: AppTextStyle.textXsRegular.copyWith(
                            color: AppColors.dark100,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
