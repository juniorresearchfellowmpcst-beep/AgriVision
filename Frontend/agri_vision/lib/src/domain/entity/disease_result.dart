import 'package:equatable/equatable.dart';

/// Result of the backend `/api/disease/identify` call.
///
/// Mirrors the JSON that `DiseaseService.identify` returns: the identified
/// condition, a severity estimate, and the farmer-readable symptoms, causes,
/// treatment [solutions] and prevention tips.
class DiseaseResult extends Equatable {
  final String status;
  final String message;
  final bool isHealthy;
  final bool lowConfidence;
  final double confidence; // 0..1
  final String source; // "model" | "heuristic"

  final String diseaseId;
  final String name;
  final String alsoKnownAs;
  final String description;

  final String severityLevel; // none | low | moderate | high
  final int affectedPercent; // 0..100

  final List<String> symptoms;
  final List<String> causes;
  final List<Solution> solutions;
  final List<String> prevention;
  final String disclaimer;

  const DiseaseResult({
    required this.status,
    required this.message,
    required this.isHealthy,
    required this.lowConfidence,
    required this.confidence,
    required this.source,
    required this.diseaseId,
    required this.name,
    required this.alsoKnownAs,
    required this.description,
    required this.severityLevel,
    required this.affectedPercent,
    required this.symptoms,
    required this.causes,
    required this.solutions,
    required this.prevention,
    required this.disclaimer,
  });

  bool get isOk => status == 'ok';

  /// Confidence as a whole percentage for display (e.g. 85).
  int get confidencePercent => (confidence * 100).round();

  factory DiseaseResult.fromJson(Map<String, dynamic> json) {
    final disease = (json['disease'] as Map?)?.cast<String, dynamic>() ?? {};
    final severity = (json['severity'] as Map?)?.cast<String, dynamic>() ?? {};

    return DiseaseResult(
      status: json['status']?.toString() ?? 'error',
      message: json['message']?.toString() ?? '',
      isHealthy: json['is_healthy'] == true,
      lowConfidence: json['low_confidence'] == true,
      confidence: _toDouble(json['confidence']),
      source: json['source']?.toString() ?? 'heuristic',
      diseaseId: disease['id']?.toString() ?? 'general_stress',
      name: disease['name']?.toString() ?? 'Unknown condition',
      alsoKnownAs: disease['also_known_as']?.toString() ?? '',
      description: disease['description']?.toString() ?? '',
      severityLevel: severity['level']?.toString() ?? 'low',
      affectedPercent: _toInt(severity['affected_percent']),
      symptoms: _toStringList(json['symptoms']),
      causes: _toStringList(json['causes']),
      solutions:
          (json['solutions'] as List?)
              ?.map((e) => Solution.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      prevention: _toStringList(json['prevention']),
      disclaimer: json['disclaimer']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [status, diseaseId, confidence, severityLevel];
}

/// One treatment/advice item, grouped by [type] so the UI can section them.
class Solution extends Equatable {
  final String type; // cultural | organic | chemical | monitoring
  final String title;
  final String detail;

  const Solution({
    required this.type,
    required this.title,
    required this.detail,
  });

  factory Solution.fromJson(Map<String, dynamic> json) => Solution(
    type: json['type']?.toString() ?? 'cultural',
    title: json['title']?.toString() ?? '',
    detail: json['detail']?.toString() ?? '',
  );

  @override
  List<Object?> get props => [type, title, detail];
}

List<String> _toStringList(dynamic v) =>
    (v as List?)?.map((e) => e.toString()).toList() ?? const [];

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0.0;
}

int _toInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}
