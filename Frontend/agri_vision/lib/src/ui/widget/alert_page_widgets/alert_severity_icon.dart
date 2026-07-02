import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Circular icon badge representing the alert severity type —
/// red warning triangle for High, amber for Medium, green for Low.
class AlertSeverityIcon extends StatelessWidget {
  const AlertSeverityIcon({super.key, required this.severity, this.size = 44});

  final AlertSeverity severity;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: severity.iconBackground,
        shape: BoxShape.circle,
      ),
      child: Icon(severity.icon, size: size * 0.50, color: severity.iconColor),
    );
  }
}
