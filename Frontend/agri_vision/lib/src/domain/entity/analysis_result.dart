import 'package:equatable/equatable.dart';

/// Result of the backend `/api/preprocessing/analyze-images` call.
///
/// Mirrors the JSON the Flask `PreprocessingService.analyze_images` returns:
/// the field-health report, the high/medium/low risk zoning, the prioritised
/// action plan, per-index summaries, and URLs to the generated preview images.
class AnalysisResult extends Equatable {
  final String status;
  final String message;
  final String? jobId;
  final bool calibrated;
  final String? primaryIndex;
  final List<String> bandsUsed;

  // Report
  final int? healthScore; // 0..100
  final String healthLabel; // healthy | moderate | poor | unknown
  final String riskSummary;
  final Map<String, double> riskDistribution; // {high, medium, low} -> fraction
  final List<IndexSummary> indexSummaries;
  final List<ReportFlag> flags;

  // Action plan
  final List<ActionItem> actionPlan;

  // Preview image URLs (absolute, fetchable with Image.network)
  final String? riskMapUrl;
  final String? falseColorUrl;
  final Map<String, String> indexPreviewUrls; // index key -> preview url

  const AnalysisResult({
    required this.status,
    required this.message,
    required this.calibrated,
    required this.healthLabel,
    required this.riskSummary,
    required this.riskDistribution,
    required this.indexSummaries,
    required this.flags,
    required this.actionPlan,
    required this.bandsUsed,
    required this.indexPreviewUrls,
    this.jobId,
    this.primaryIndex,
    this.healthScore,
    this.riskMapUrl,
    this.falseColorUrl,
  });

  bool get isOk => status == 'ok';

  double get highRisk => riskDistribution['high'] ?? 0;
  double get mediumRisk => riskDistribution['medium'] ?? 0;
  double get lowRisk => riskDistribution['low'] ?? 0;

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    final report = (json['report'] as Map?)?.cast<String, dynamic>() ?? {};
    final outputs = (json['outputs'] as Map?)?.cast<String, dynamic>() ?? {};

    final dist = <String, double>{};
    (report['risk_distribution'] as Map?)?.forEach((k, v) {
      dist['$k'] = _toDouble(v);
    });

    final previews = <String, String>{};
    (outputs['index_previews'] as Map?)?.forEach((k, v) {
      if (v != null) previews['$k'] = '$v';
    });

    return AnalysisResult(
      status: json['status']?.toString() ?? 'error',
      message: json['message']?.toString() ?? '',
      jobId: json['job_id']?.toString(),
      calibrated: json['calibrated'] == true,
      primaryIndex: json['primary_index']?.toString(),
      bandsUsed:
          (json['bands_used'] as List?)?.map((e) => '$e').toList() ?? const [],
      healthScore: report['health_score'] == null
          ? null
          : _toInt(report['health_score']),
      healthLabel: report['health_label']?.toString() ?? 'unknown',
      riskSummary: report['risk_summary']?.toString() ?? '',
      riskDistribution: dist,
      indexSummaries:
          (report['index_summaries'] as List?)
              ?.map((e) => IndexSummary.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      flags:
          (report['flags'] as List?)
              ?.map((e) => ReportFlag.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      actionPlan:
          (json['action_plan'] as List?)
              ?.map((e) => ActionItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      riskMapUrl: outputs['risk_map']?.toString(),
      falseColorUrl: outputs['false_color']?.toString(),
      indexPreviewUrls: previews,
    );
  }

  @override
  List<Object?> get props => [status, jobId, healthScore, riskDistribution];
}

/// One index's headline reading (e.g. NDVI mean 0.41, status "good").
class IndexSummary extends Equatable {
  final String index;
  final String name;
  final double mean;
  final String status; // good | moderate | poor
  final String? category;

  const IndexSummary({
    required this.index,
    required this.name,
    required this.mean,
    required this.status,
    this.category,
  });

  factory IndexSummary.fromJson(Map<String, dynamic> json) => IndexSummary(
    index: json['index']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    mean: _toDouble(json['mean']),
    status: json['status']?.toString() ?? 'unknown',
    category: json['category']?.toString(),
  );

  @override
  List<Object?> get props => [index, mean, status];
}

/// A flagged issue detected in the report (e.g. low chlorophyll).
class ReportFlag extends Equatable {
  final String severity; // high | medium
  final String issue;
  final String? index;

  const ReportFlag({required this.severity, required this.issue, this.index});

  factory ReportFlag.fromJson(Map<String, dynamic> json) => ReportFlag(
    severity: json['severity']?.toString() ?? 'medium',
    issue: json['issue']?.toString() ?? '',
    index: json['index']?.toString(),
  );

  @override
  List<Object?> get props => [severity, issue, index];
}

/// One prioritised recommendation from the action plan.
class ActionItem extends Equatable {
  final int order;
  final int priority; // 1 (highest) .. 3
  final String title;
  final String detail;
  final String? category;

  const ActionItem({
    required this.order,
    required this.priority,
    required this.title,
    required this.detail,
    this.category,
  });

  factory ActionItem.fromJson(Map<String, dynamic> json) => ActionItem(
    order: _toInt(json['order'] ?? 0),
    priority: _toInt(json['priority'] ?? 3),
    title: json['title']?.toString() ?? '',
    detail: json['detail']?.toString() ?? '',
    category: json['category']?.toString(),
  );

  @override
  List<Object?> get props => [order, title];
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0.0;
}

int _toInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}
