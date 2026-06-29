import 'package:flutter/material.dart';

class LogoMark extends StatelessWidget {
  final double scale;
  const LogoMark({required this.scale});

  @override
  Widget build(BuildContext context) {
    final size = 108.0 * scale;
    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.26),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2BBE6E), Color(0xFF1C8C50)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2BBE6E).withValues(alpha: 0.35),
              blurRadius: 40 * scale,
              spreadRadius: -4,
              offset: Offset(0, 16 * scale),
            ),
          ],
        ),
        child: Center(
          child: CustomPaint(
            size: Size(size * 0.48, size * 0.48),
            painter: const _DroneGlyphPainter(),
          ),
        ),
      ),
    );
  }
}

class _DroneGlyphPainter extends CustomPainter {
  const _DroneGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final w = size.width;

    final stroke = Paint()
      ..color = Colors.white
      ..strokeWidth = w * 0.07
      ..strokeCap = StrokeCap.round;

    final fill = Paint()..color = Colors.white;

    const dirs = [Offset(-1, -1), Offset(1, -1), Offset(-1, 1), Offset(1, 1)];
    final armLen = w * 0.36;

    for (final d in dirs) {
      final end = Offset(center.dx + d.dx * armLen, center.dy + d.dy * armLen);
      canvas.drawLine(center, end, stroke);
      canvas.drawCircle(
        end,
        w * 0.1,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.045,
      );
    }

    final bodyRect = Rect.fromCenter(
      center: center,
      width: w * 0.34,
      height: w * 0.22,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, Radius.circular(w * 0.06)),
      fill,
    );
  }

  // Static drawing — never needs to repaint.
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
