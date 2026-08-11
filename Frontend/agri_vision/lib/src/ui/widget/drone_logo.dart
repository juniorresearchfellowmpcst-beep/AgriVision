import 'package:flutter/material.dart';

/// The app's drone mark, drawn from `assets/images/drone.png`.
///
/// The asset is a solid black quadcopter on transparency, so it tints cleanly
/// to whatever colour the surrounding surface needs. Everywhere the app used to
/// reach for a stock aviation icon (`Icons.flight_takeoff`) it uses this
/// instead — one mark for "drone", on the splash screen, the connect flows, the
/// pairing card and the map.
class DroneIcon extends StatelessWidget {
  const DroneIcon({super.key, this.size = 20, this.color, this.semanticLabel});

  /// Edge length of the square glyph.
  final double size;

  /// Tint applied to the mark. Null keeps the artwork's own black.
  final Color? color;

  final String? semanticLabel;

  static const String assetPath = 'assets/images/drone.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      color: color,
      // Cache at the resolution actually drawn — these appear in list rows and
      // map markers, where the full 512px bitmap is pure waste.
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      filterQuality: FilterQuality.medium,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}

/// The rounded-square brand tile: the drone mark on the app's green gradient.
/// Used by the splash screen and the sign-in header.
class LogoMark extends StatelessWidget {
  final double scale;
  const LogoMark({super.key, required this.scale});

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
          child: DroneIcon(
            size: size * 0.56,
            color: Colors.white,
            semanticLabel: 'AgriVision',
          ),
        ),
      ),
    );
  }
}
