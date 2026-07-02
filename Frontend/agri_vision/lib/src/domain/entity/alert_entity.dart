import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

// ── Enums ──────────────────────────────────────────────────────────────────

enum AlertSeverity { high, medium, low }

extension AlertSeverityX on AlertSeverity {
  String get label => switch (this) {
    AlertSeverity.high => 'High',
    AlertSeverity.medium => 'Medium',
    AlertSeverity.low => 'Low',
  };

  Color get badgeBackground => switch (this) {
    AlertSeverity.high => const Color(0xFFFFE5E5),
    AlertSeverity.medium => const Color(0xFFFBEAC7),
    AlertSeverity.low => const Color(0xFFDCF0DE),
  };

  Color get badgeText => switch (this) {
    AlertSeverity.high => AppColors.themeError,
    AlertSeverity.medium => const Color(0xFF9A6A0B),
    AlertSeverity.low => AppColors.themeSuccess,
  };

  Color get iconBackground => switch (this) {
    AlertSeverity.high => const Color(0xFFFFE5E5),
    AlertSeverity.medium => const Color(0xFFFBEAC7),
    AlertSeverity.low => const Color(0xFFDCF0DE),
  };

  Color get iconColor => switch (this) {
    AlertSeverity.high => AppColors.themeError,
    AlertSeverity.medium => AppColors.themeWarning,
    AlertSeverity.low => AppColors.themeSuccess,
  };

  IconData get icon => switch (this) {
    AlertSeverity.high => Icons.warning_rounded,
    AlertSeverity.medium => Icons.warning_amber_rounded,
    AlertSeverity.low => Icons.info_outline_rounded,
  };
}

// ── Entity ─────────────────────────────────────────────────────────────────

class AlertEntity {
  const AlertEntity({
    required this.id,
    required this.title,
    required this.location,
    required this.time,
    required this.severity,
    required this.area,
    required this.confidence,
  });

  final String id;
  final String title;
  final String location;
  final String time;
  final AlertSeverity severity;
  final String area;
  final String confidence;

  static List<AlertEntity> getDummyData() => const [
    AlertEntity(
      id: '1',
      title: 'Leaf Blight (Disease)',
      location: 'Block A – Row 14',
      time: '09:42 AM',
      severity: AlertSeverity.high,
      area: '0.3 ha',
      confidence: '91% conf.',
    ),
    AlertEntity(
      id: '2',
      title: 'Drought Stress',
      location: 'Block A – Row 9',
      time: '09:38 AM',
      severity: AlertSeverity.medium,
      area: '0.5 ha',
      confidence: '84% conf.',
    ),
    AlertEntity(
      id: '3',
      title: 'Nutrient Deficiency',
      location: 'Block B – Row 3',
      time: '09:31 AM',
      severity: AlertSeverity.low,
      area: '0.2 ha',
      confidence: '77% conf.',
    ),
    AlertEntity(
      id: '4',
      title: 'Aphid Infestation',
      location: 'Orchard Row 8',
      time: '08:55 AM',
      severity: AlertSeverity.high,
      area: '0.1 ha',
      confidence: '95% conf.',
    ),
    AlertEntity(
      id: '5',
      title: 'Overwatering Stress',
      location: 'Paddock 3 – West',
      time: '08:22 AM',
      severity: AlertSeverity.medium,
      area: '0.4 ha',
      confidence: '79% conf.',
    ),
    AlertEntity(
      id: '2',
      title: 'Drought Stress',
      location: 'Block A – Row 9',
      time: '09:38 AM',
      severity: AlertSeverity.medium,
      area: '0.5 ha',
      confidence: '84% conf.',
    ),
    AlertEntity(
      id: '3',
      title: 'Nutrient Deficiency',
      location: 'Block B – Row 3',
      time: '09:31 AM',
      severity: AlertSeverity.low,
      area: '0.2 ha',
      confidence: '77% conf.',
    ),
    AlertEntity(
      id: '4',
      title: 'Aphid Infestation',
      location: 'Orchard Row 8',
      time: '08:55 AM',
      severity: AlertSeverity.high,
      area: '0.1 ha',
      confidence: '95% conf.',
    ),
    AlertEntity(
      id: '5',
      title: 'Overwatering Stress',
      location: 'Paddock 3 – West',
      time: '08:22 AM',
      severity: AlertSeverity.medium,
      area: '0.4 ha',
      confidence: '79% conf.',
    ),
    AlertEntity(
      id: '2',
      title: 'Drought Stress',
      location: 'Block A – Row 9',
      time: '09:38 AM',
      severity: AlertSeverity.medium,
      area: '0.5 ha',
      confidence: '84% conf.',
    ),
    AlertEntity(
      id: '3',
      title: 'Nutrient Deficiency',
      location: 'Block B – Row 3',
      time: '09:31 AM',
      severity: AlertSeverity.low,
      area: '0.2 ha',
      confidence: '77% conf.',
    ),
    AlertEntity(
      id: '4',
      title: 'Aphid Infestation',
      location: 'Orchard Row 8',
      time: '08:55 AM',
      severity: AlertSeverity.high,
      area: '0.1 ha',
      confidence: '95% conf.',
    ),
    AlertEntity(
      id: '5',
      title: 'Overwatering Stress',
      location: 'Paddock 3 – West',
      time: '08:22 AM',
      severity: AlertSeverity.medium,
      area: '0.4 ha',
      confidence: '79% conf.',
    ),
    AlertEntity(
      id: '2',
      title: 'Drought Stress',
      location: 'Block A – Row 9',
      time: '09:38 AM',
      severity: AlertSeverity.medium,
      area: '0.5 ha',
      confidence: '84% conf.',
    ),
    AlertEntity(
      id: '3',
      title: 'Nutrient Deficiency',
      location: 'Block B – Row 3',
      time: '09:31 AM',
      severity: AlertSeverity.low,
      area: '0.2 ha',
      confidence: '77% conf.',
    ),
    AlertEntity(
      id: '4',
      title: 'Aphid Infestation',
      location: 'Orchard Row 8',
      time: '08:55 AM',
      severity: AlertSeverity.high,
      area: '0.1 ha',
      confidence: '95% conf.',
    ),
    AlertEntity(
      id: '5',
      title: 'Overwatering Stress',
      location: 'Paddock 3 – West',
      time: '08:22 AM',
      severity: AlertSeverity.medium,
      area: '0.4 ha',
      confidence: '79% conf.',
    ),
  ];
}
