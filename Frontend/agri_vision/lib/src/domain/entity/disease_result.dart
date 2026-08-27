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

  /// The crop the model recognised (e.g. "Tomato"), empty when the heuristic
  /// answered — it works from colour alone and cannot know the species.
  final String crop;

  /// The model's raw class label, e.g. `tomato___late_blight`. Empty on the
  /// heuristic path. Kept so a diagnosis can be traced back to a class.
  final String label;

  /// The knowledge-base entry the advice below came from. [name] is the
  /// specific finding; this is the category whose treatment text is shown.
  final String categoryName;

  /// True when the model returned a class this app has no mapping for.
  final bool unmapped;

  /// Ranked alternatives, most likely first. Empty on the heuristic path.
  final List<DiseasePrediction> predictions;

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
    required this.crop,
    required this.label,
    required this.categoryName,
    required this.unmapped,
    required this.predictions,
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

  /// Whether the headline [name] differs from the advice [categoryName].
  /// When it does, the UI should say so: the farmer is reading blight advice
  /// under a "Tomato Late Blight" heading and should know the guidance is the
  /// general one for that category.
  bool get advicesUnderCategory =>
      categoryName.isNotEmpty && categoryName != name;

  /// The runner-up class, but only when it is genuinely in play.
  ///
  /// A second place at 2% is noise and clutters the diagnosis; a second place
  /// at 40% is the whole story. The threshold keeps the line meaningful rather
  /// than always-on.
  DiseasePrediction? get runnerUp {
    if (predictions.length < 2) return null;
    final second = predictions[1];
    return second.confidence >= 0.15 ? second : null;
  }

  factory DiseaseResult.fromJson(Map<String, dynamic> json) {
    final disease = (json['disease'] as Map?)?.cast<String, dynamic>() ?? {};
    final severity = (json['severity'] as Map?)?.cast<String, dynamic>() ?? {};
    final category = (disease['category'] as Map?)?.cast<String, dynamic>() ?? {};

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
      crop: disease['crop']?.toString() ?? '',
      label: disease['label']?.toString() ?? '',
      categoryName: category['name']?.toString() ?? '',
      unmapped: disease['unmapped'] == true,
      predictions:
          (json['predictions'] as List?)
              ?.map((e) => DiseasePrediction.fromJson(
                    (e as Map).cast<String, dynamic>(),
                  ))
              .toList() ??
          const [],
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

/// One ranked class from the model, used to show a close runner-up.
///
/// A near-tie matters on a leaf photo: early and late blight look similar in a
/// single frame but call for different urgency, so the second-place class is
/// information the farmer should see rather than something to hide.
class DiseasePrediction extends Equatable {
  final String label;
  final String name;
  final double confidence;

  const DiseasePrediction({
    required this.label,
    required this.name,
    required this.confidence,
  });

  int get confidencePercent => (confidence * 100).round();

  factory DiseasePrediction.fromJson(Map<String, dynamic> json) =>
      DiseasePrediction(
        label: json['label']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        confidence: _toDouble(json['confidence']),
      );

  @override
  List<Object?> get props => [label, name, confidence];
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
