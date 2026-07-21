import 'package:intl/intl.dart';

/// One persisted multispectral analysis run (GET /api/analysis/reports).
///
/// This is the history counterpart of [AnalysisResult]: the backend stores a
/// summary of every analyze-images run and this entity renders that list in
/// the Reports tab.
class FieldReportEntity {
  const FieldReportEntity({
    required this.id,
    required this.title,
    required this.date,
    required this.healthScore,
    required this.healthLabel,
    required this.primaryIndex,
    required this.riskHigh,
    required this.riskMedium,
    required this.riskLow,
    required this.alertCount,
    required this.calibrated,
  });

  final int id;
  final String title;
  final String date;
  final double healthScore;
  final String healthLabel;
  final String primaryIndex;

  /// Area fractions (0..1) per risk band.
  final double riskHigh;
  final double riskMedium;
  final double riskLow;

  final int alertCount;
  final bool calibrated;

  factory FieldReportEntity.fromJson(Map<String, dynamic> json) {
    final risk = json['risk_distribution'] is Map<String, dynamic>
        ? json['risk_distribution'] as Map<String, dynamic>
        : const <String, dynamic>{};

    double asDouble(dynamic v) => v is num ? v.toDouble() : 0.0;

    String date = '';
    final parsed = DateTime.tryParse(json['created_at']?.toString() ?? '');
    if (parsed != null) {
      date = DateFormat('MMM d, yyyy').format(parsed.toLocal());
    }

    final fieldName = json['field_name']?.toString() ?? '';

    return FieldReportEntity(
      id: json['id'] ?? 0,
      title: fieldName.isNotEmpty ? fieldName : 'Field Analysis',
      date: date,
      healthScore: asDouble(json['health_score']),
      healthLabel: json['health_label']?.toString() ?? '',
      primaryIndex: (json['primary_index']?.toString() ?? '').toUpperCase(),
      riskHigh: asDouble(risk['high']),
      riskMedium: asDouble(risk['medium']),
      riskLow: asDouble(risk['low']),
      alertCount: json['alert_count'] is num
          ? (json['alert_count'] as num).round()
          : 0,
      calibrated: json['calibrated'] == true,
    );
  }

  static List<FieldReportEntity> fromJsonList(List<dynamic> jsonList) =>
      jsonList
          .whereType<Map<String, dynamic>>()
          .map(FieldReportEntity.fromJson)
          .toList();
}
