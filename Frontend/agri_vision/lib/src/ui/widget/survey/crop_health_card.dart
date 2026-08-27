import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:agri_vision/src/core/core.dart';
import 'package:agri_vision/src/domain/entity/survey_entity.dart';

/// The one number and one sentence at the top of a survey summary.
///
/// The score is blunt on purpose. Its value is not precision — it is that two
/// flights over the same block a week apart are comparable, which is the
/// question a farmer actually asks. A pass that scanned nothing shows no
/// number at all rather than a zero, because zero reads as a dead crop.
class CropHealthCard extends StatelessWidget {
  const CropHealthCard({required this.health, this.fieldName, super.key});

  final CropHealth health;
  final String? fieldName;

  static const Map<String, Color> _bandColors = {
    'good': AppColors.themeSuccess,
    'fair': AppColors.themeWarning,
    'poor': Color(0xFFE07B39),
    'critical': AppColors.themeError,
    'unknown': AppColors.dark100,
  };

  @override
  Widget build(BuildContext context) {
    final color = _bandColors[health.band] ?? AppColors.dark100;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.light100,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ScoreDial(score: health.score, color: color),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CROP HEALTH',
                      style: AppTextStyle.textXsSemibold.copyWith(
                        color: AppColors.dark100,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // Sentence case rather than shouting a band name: the
                      // headline is meant to be read, not decoded.
                      _capitalise(health.headline),
                      style: AppTextStyle.textLgSemibold.copyWith(color: color),
                    ),
                    if (fieldName != null && fieldName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        fieldName!,
                        style: AppTextStyle.textXsRegular.copyWith(
                          color: AppColors.dark300,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (health.detail.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              health.detail,
              style: AppTextStyle.textSmRegular.copyWith(
                color: AppColors.dark500,
                height: 1.45,
              ),
            ),
          ],
          // A score built from a handful of frames describes a few seconds of
          // hovering, not a block. Say so next to the number, not in a footnote.
          if (health.score != null && !health.confident) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm + 2),
              decoration: BoxDecoration(
                color: AppColors.themeWarning.withOpacity(0.10),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 15,
                    color: AppColors.themeWarning,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Few frames were scanned, so treat this as indicative. '
                      'Fly a full pass before acting on the percentages.',
                      style: AppTextStyle.textXsRegular.copyWith(
                        color: AppColors.dark500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _capitalise(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}

class _ScoreDial extends StatelessWidget {
  const _ScoreDial({required this.score, required this.color});

  final int? score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: CustomPaint(
        painter: _DialPainter(
          fraction: score == null ? 0 : score! / 100,
          color: color,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                // An em dash, not "0" — a pass that scanned nothing has no
                // reading, and zero would read as a dead field.
                score?.toString() ?? '—',
                style: AppTextStyle.text2xlBold.copyWith(color: color),
              ),
              if (score != null)
                Text(
                  '/100',
                  style: AppTextStyle.textXsRegular.copyWith(
                    color: AppColors.dark100,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = (math.min(size.width, size.height) - stroke) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppColors.light500;

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;

    canvas.drawCircle(centre, radius, track);
    if (fraction > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        -math.pi / 2, // start at twelve o'clock
        2 * math.pi * fraction.clamp(0.0, 1.0),
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) =>
      old.fraction != fraction || old.color != color;
}
