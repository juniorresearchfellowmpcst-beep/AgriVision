import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Full-screen satellite/field map with:
///  - Dark green agriculture-style background with parallel row lines
///  - Dashed yellow flight path connecting waypoints in order
///  - Green spray coverage fill inside the boundary
///  - Numbered draggable waypoint markers
///  - No-fly zone overlay (red dashed corner)
///
/// In production, replace this [CustomPainter] layer with
/// flutter_map / google_maps_flutter / mapbox_maps_flutter and
/// overlay markers + polylines via their respective APIs.
class MissionMapView extends StatefulWidget {
  const MissionMapView({
    super.key,
    required this.waypoints,
    required this.onWaypointMoved,
    required this.onWaypointSelected,
    required this.onMapTapped,
    this.selectedWaypointId,
  });

  final List<WaypointModel> waypoints;
  final void Function(int id, Offset newFraction) onWaypointMoved;
  final void Function(int id) onWaypointSelected;
  final void Function(Offset fraction) onMapTapped;
  final int? selectedWaypointId;

  @override
  State<MissionMapView> createState() => _MissionMapViewState();
}

class _MissionMapViewState extends State<MissionMapView> {
  int? _draggingId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return GestureDetector(
          onTapUp: (d) {
            final frac = Offset(
              d.localPosition.dx / size.width,
              d.localPosition.dy / size.height,
            );
            widget.onMapTapped(frac);
          },
          child: Stack(
            children: [
              // ── Map background ─────────────────────────────────────
              CustomPaint(
                size: size,
                painter: _FieldMapPainter(
                  waypoints: widget.waypoints,
                  size: size,
                ),
              ),

              // ── Draggable waypoint markers ─────────────────────────
              ...widget.waypoints.map((wp) {
                final pos = Offset(
                  wp.position.dx * size.width,
                  wp.position.dy * size.height,
                );
                return Positioned(
                  left: pos.dx - 16,
                  top: pos.dy - 16,
                  child: GestureDetector(
                    onTap: () => widget.onWaypointSelected(wp.id),
                    onPanStart: (_) => setState(() => _draggingId = wp.id),
                    onPanUpdate: (d) {
                      final newPos = Offset(
                        (pos.dx + d.delta.dx).clamp(0, size.width),
                        (pos.dy + d.delta.dy).clamp(0, size.height),
                      );
                      widget.onWaypointMoved(
                        wp.id,
                        Offset(newPos.dx / size.width, newPos.dy / size.height),
                      );
                    },
                    onPanEnd: (_) => setState(() => _draggingId = null),
                    child: _WaypointMarker(
                      id: wp.id,
                      isSelected: widget.selectedWaypointId == wp.id,
                      isDragging: _draggingId == wp.id,
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

// ── Field map painter ──────────────────────────────────────────────────────

class _FieldMapPainter extends CustomPainter {
  const _FieldMapPainter({required this.waypoints, required this.size});

  final List<WaypointModel> waypoints;
  final Size size;

  Offset _wp(WaypointModel wp) =>
      Offset(wp.position.dx * size.width, wp.position.dy * size.height);

  @override
  void paint(Canvas canvas, Size size) {
    // background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF1A3A28),
    );

    // crop row lines
    final rowPaint = Paint()
      ..color = const Color(0xFF224D35)
      ..strokeWidth = 1.2;
    const rowSpacing = 18.0;
    for (double y = 0; y < size.height; y += rowSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rowPaint);
    }

    if (waypoints.isEmpty) return;

    final points = waypoints.map(_wp).toList();

    // ── spray coverage fill ──────────────────────────────────────────
    final fillPath = Path()..addPolygon(points, true);
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = AppColors.primary.withOpacity(0.12)
        ..style = PaintingStyle.fill,
    );

    // ── boundary outline ─────────────────────────────────────────────
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = AppColors.primary.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ── dashed flight path ────────────────────────────────────────────
    final pathPaint = Paint()
      ..color = const Color(0xFFE7B10A)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final flightPath = Path();
    flightPath.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      flightPath.lineTo(points[i].dx, points[i].dy);
    }
    _drawDashed(canvas, flightPath, pathPaint, dashLen: 10, gapLen: 6);

    // ── no-fly zone (top-right corner) ────────────────────────────────
    final nfzRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.78,
        0,
        size.width * 0.22,
        size.height * 0.12,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      nfzRect,
      Paint()..color = AppColors.themeError.withOpacity(0.18),
    );
    _drawDashedRRect(canvas, nfzRect, AppColors.themeError.withOpacity(0.7));

    // NFZ label
    const nfzStyle = TextStyle(
      color: Color(0xFFFF6B6B),
      fontSize: 9,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );
    _drawText(
      canvas,
      'NO-FLY ZONE',
      Offset(size.width * 0.815, size.height * 0.025),
      nfzStyle,
    );

    // ── spray direction arrow ────────────────────────────────────────
    _drawArrow(
      canvas,
      Offset(size.width * 0.50, size.height * 0.78),
      Offset(size.width * 0.65, size.height * 0.78),
      AppColors.primary.withOpacity(0.7),
    );
  }

  void _drawDashed(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dashLen,
    required double gapLen,
  }) {
    for (final m in path.computeMetrics()) {
      double dist = 0;
      bool draw = true;
      while (dist < m.length) {
        final len = draw ? dashLen : gapLen;
        if (draw) canvas.drawPath(m.extractPath(dist, dist + len), paint);
        dist += len;
        draw = !draw;
      }
    }
  }

  void _drawDashedRRect(Canvas canvas, RRect rr, Color color) {
    final path = Path()..addRRect(rr);
    _drawDashed(
      canvas,
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
      dashLen: 6,
      gapLen: 4,
    );
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(from, to, paint);
    const arrowSize = 7.0;
    canvas.drawPath(
      Path()
        ..moveTo(to.dx, to.dy)
        ..lineTo(to.dx - arrowSize, to.dy - arrowSize / 2)
        ..lineTo(to.dx - arrowSize, to.dy + arrowSize / 2)
        ..close(),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    // label
    _drawText(
      canvas,
      'Spray direction',
      Offset(from.dx - 8, from.dy + 6),
      TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w500),
    );
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_FieldMapPainter old) =>
      old.waypoints != waypoints || old.size != size;
}

// ── Waypoint marker ────────────────────────────────────────────────────────

class _WaypointMarker extends StatelessWidget {
  const _WaypointMarker({
    required this.id,
    required this.isSelected,
    required this.isDragging,
  });

  final int id;
  final bool isSelected;
  final bool isDragging;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary : AppColors.light100,
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? AppColors.primary : const Color(0xFFE7B10A),
          width: isDragging ? 2.5 : 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDragging ? 0.35 : 0.20),
            blurRadius: isDragging ? 12 : 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$id',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isSelected ? AppColors.light100 : AppColors.dark900,
        ),
      ),
    );
  }
}
