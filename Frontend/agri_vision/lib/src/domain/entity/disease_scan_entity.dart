import 'package:equatable/equatable.dart';

/// A past plant-disease scan, from `GET /api/disease/scans`.
///
/// Scans are persisted so a diagnosis becomes field history: knowing *when* a
/// blight first showed up in a block matters as much as knowing it is there
/// now. The list view carries only the summary; the full diagnosis is fetched
/// per-scan when the operator re-opens one.
class DiseaseScanEntity extends Equatable {
  const DiseaseScanEntity({
    required this.id,
    required this.conditionName,
    required this.isHealthy,
    this.conditionId,
    this.severity,
    this.confidence = 0,
    this.engine,
    this.fieldName,
    this.filename,
    this.scannedAt,
  });

  final int id;
  final String conditionName;
  final bool isHealthy;
  final String? conditionId;
  final String? severity; // none | low | moderate | high
  final double confidence; // 0..1
  final String? engine; // 'model' or 'heuristic'
  final String? fieldName;
  final String? filename;
  final DateTime? scannedAt;

  int get confidencePercent => (confidence * 100).round();

  /// Where the scan was taken, when the operator tagged a block.
  String get locationLabel => (fieldName?.trim().isNotEmpty ?? false)
      ? fieldName!.trim()
      : 'Unlabelled block';

  factory DiseaseScanEntity.fromJson(Map<String, dynamic> json) {
    return DiseaseScanEntity(
      id: json['id'] is num ? (json['id'] as num).toInt() : 0,
      conditionName: json['condition_name']?.toString() ?? 'Unknown condition',
      isHealthy: json['is_healthy'] == true,
      conditionId: json['condition_id']?.toString(),
      severity: json['severity']?.toString(),
      confidence: json['confidence'] is num
          ? (json['confidence'] as num).toDouble()
          : 0,
      engine: json['engine']?.toString(),
      fieldName: json['field_name']?.toString(),
      filename: json['filename']?.toString(),
      scannedAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  static List<DiseaseScanEntity> fromJsonList(List<dynamic> items) => [
    for (final item in items)
      if (item is Map)
        DiseaseScanEntity.fromJson(Map<String, dynamic>.from(item)),
  ];

  @override
  List<Object?> get props => [
    id,
    conditionName,
    isHealthy,
    conditionId,
    severity,
    confidence,
    engine,
    fieldName,
    filename,
    scannedAt,
  ];
}
