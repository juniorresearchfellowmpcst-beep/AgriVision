import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Coverage map section card. Shows a section header with a green
/// completion percentage, and a dark map image/placeholder below.
///
/// Replace [mapWidget] with your actual map widget (flutter_map,
/// google_maps_flutter, image, etc.).
class CoverageMapCard extends StatelessWidget {
  const CoverageMapCard({
    super.key,
    required this.coveragePercent,
    this.mapWidget,
    this.mapHeight = 160,
  });

  final int coveragePercent;
  final Widget? mapWidget;
  final double mapHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          // header
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Coverage Map', style: AppTextStyle.textLgBold),
                Row(
                  children: [
                    Text(
                      '$coveragePercent%',
                      style: AppTextStyle.textSmSemibold.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // map area
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(AppRadius.lg),
              bottomRight: Radius.circular(AppRadius.lg),
            ),
            child: SizedBox(
              height: mapHeight,
              child:
                  mapWidget ??
                  Container(
                    color: const Color(0xFF1A3A28),
                    child: Stack(
                      children: [
                        // grid lines
                        CustomPaint(
                          size: Size.infinite,
                          painter: _GridPainter(),
                        ),
                        // dotted flight path overlay
                        CustomPaint(
                          size: Size.infinite,
                          painter: _FlightPathPainter(),
                        ),
                      ],
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Simple grid painter ────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.07)
      ..strokeWidth = 1;

    const step = 30.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Dotted flight path painter ─────────────────────────────────────────────

class _FlightPathPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE7B10A)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.15, size.height * 0.8)
      ..lineTo(size.width * 0.15, size.height * 0.2)
      ..lineTo(size.width * 0.35, size.height * 0.2)
      ..lineTo(size.width * 0.35, size.height * 0.8)
      ..lineTo(size.width * 0.55, size.height * 0.8)
      ..lineTo(size.width * 0.55, size.height * 0.2)
      ..lineTo(size.width * 0.75, size.height * 0.2)
      ..lineTo(size.width * 0.75, size.height * 0.65);

    // draw dashed
    _drawDashed(canvas, path, paint, dashLen: 8, gapLen: 5);

    // waypoint dots
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    for (final offset in [
      Offset(size.width * 0.15, size.height * 0.5),
      Offset(size.width * 0.55, size.height * 0.5),
      Offset(size.width * 0.75, size.height * 0.4),
    ]) {
      canvas.drawCircle(offset, 4, dotPaint);
      canvas.drawCircle(
        offset,
        4,
        Paint()
          ..color = const Color(0xFF1F4D38)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _drawDashed(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dashLen,
    required double gapLen,
  }) {
    final metrics = path.computeMetrics();
    for (final m in metrics) {
      double dist = 0;
      bool draw = true;
      while (dist < m.length) {
        final len = draw ? dashLen : gapLen;
        if (draw) {
          canvas.drawPath(m.extractPath(dist, dist + len), paint);
        }
        dist += len;
        draw = !draw;
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
