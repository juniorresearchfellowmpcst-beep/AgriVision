import 'package:equatable/equatable.dart';

/// A K-means spray prescription for one multispectral capture.
///
/// Mirrors `POST /api/spray/prescribe`. The clustering splits the field into
/// severe / moderate / healthy zones, the patches are what a boom can actually
/// target, and the [options] are the choice put to the operator — each one
/// costed against a blanket pass so the pesticide saving is a number, not a
/// claim.
class SprayPrescription extends Equatable {
  final int? id;
  final String status;
  final String sessionId;
  final String shotId;
  final String? fieldName;

  final String index;
  final String indexName;
  final int k;
  final bool calibrated;

  /// True when the field is so uniform that the "worst" cluster may not mean
  /// anything — the UI must say so before anyone sprays on it.
  final bool lowContrast;

  final List<SprayCluster> clusters;

  /// Share of the field each class covers after patch cleanup (0..1).
  final Map<String, double> fractions;
  final Map<String, double?> areasHa;
  final double? fieldHa;

  final List<SprayPatch> patches;
  final List<SprayOption> options;
  final SprayCoverage coverage;

  final double dosePerHa;
  final String? prescriptionMapUrl;
  final List<String> notes;

  const SprayPrescription({
    required this.id,
    required this.status,
    required this.sessionId,
    required this.shotId,
    required this.fieldName,
    required this.index,
    required this.indexName,
    required this.k,
    required this.calibrated,
    required this.lowContrast,
    required this.clusters,
    required this.fractions,
    required this.areasHa,
    required this.fieldHa,
    required this.patches,
    required this.options,
    required this.coverage,
    required this.dosePerHa,
    required this.prescriptionMapUrl,
    required this.notes,
  });

  bool get isOk => status == 'ok';

  /// A prescription can only be flown when the capture had a fix and the
  /// camera's field of view is known.
  bool get canFly => coverage.georeferenced && patches.isNotEmpty;

  double percentOf(String severity) => (fractions[severity] ?? 0) * 100;

  int patchCountFor(String severity) =>
      patches.where((p) => p.severity == severity).length;

  factory SprayPrescription.fromJson(Map<String, dynamic> json) {
    final outputs = (json['outputs'] as Map?)?.cast<String, dynamic>() ?? {};

    return SprayPrescription(
      id: json['prescription_id'] == null ? null : _int(json['prescription_id']),
      status: json['status']?.toString() ?? 'error',
      sessionId: json['session_id']?.toString() ?? '',
      shotId: json['shot_id']?.toString() ?? '',
      fieldName: json['field_name']?.toString(),
      index: json['index']?.toString() ?? 'ndvi',
      indexName: json['index_name']?.toString() ?? 'NDVI',
      k: _int(json['k'] ?? 3),
      calibrated: json['calibrated'] == true,
      lowContrast: json['low_contrast'] == true,
      clusters:
          (json['clusters'] as List?)
              ?.map((e) => SprayCluster.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      fractions: _doubleMap(json['targeted_fractions']),
      areasHa: _nullableDoubleMap(json['areas_ha']),
      fieldHa: _doubleOrNull(json['field_ha']),
      patches:
          (json['patches'] as List?)
              ?.map((e) => SprayPatch.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      options:
          (json['options'] as List?)
              ?.map((e) => SprayOption.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      coverage: SprayCoverage.fromJson(
        (json['coverage'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      dosePerHa: _double(json['dose_l_per_ha']),
      prescriptionMapUrl: outputs['prescription_map']?.toString(),
      notes:
          (json['notes'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
    );
  }

  @override
  List<Object?> get props => [id, shotId, index, fractions, patches.length];
}

/// One K-means cluster and the severity it was mapped to.
class SprayCluster extends Equatable {
  final int cluster;
  final String severity;
  final double meanIndex;
  final double areaFraction;

  const SprayCluster({
    required this.cluster,
    required this.severity,
    required this.meanIndex,
    required this.areaFraction,
  });

  factory SprayCluster.fromJson(Map<String, dynamic> json) => SprayCluster(
    cluster: _int(json['cluster']),
    severity: json['severity']?.toString() ?? 'healthy',
    meanIndex: _double(json['mean_index']),
    areaFraction: _double(json['area_fraction']),
  );

  @override
  List<Object?> get props => [cluster, severity, meanIndex];
}

/// A contiguous affected area big enough for a boom to target.
class SprayPatch extends Equatable {
  final int id;
  final String severity;
  final double? areaHa;
  final double? radiusM;
  final double? lat;
  final double? lon;

  const SprayPatch({
    required this.id,
    required this.severity,
    required this.areaHa,
    required this.radiusM,
    required this.lat,
    required this.lon,
  });

  bool get hasPosition => lat != null && lon != null;

  factory SprayPatch.fromJson(Map<String, dynamic> json) => SprayPatch(
    id: _int(json['id']),
    severity: json['severity']?.toString() ?? 'severe',
    areaHa: _doubleOrNull(json['area_ha']),
    radiusM: _doubleOrNull(json['radius_m']),
    lat: _doubleOrNull(json['lat']),
    lon: _doubleOrNull(json['lon']),
  );

  @override
  List<Object?> get props => [id, severity, lat, lon];
}

/// One spray choice, costed against a blanket pass over the same block.
class SprayOption extends Equatable {
  final String id; // severe_only | severe_moderate | blanket
  final String label;
  final String detail;
  final List<String> levels;
  final int treatedPercent;
  final int savingPercent;
  final double? treatedHa;
  final double? chemicalL;
  final double? blanketL;
  final double? savedL;
  final bool recommended;

  const SprayOption({
    required this.id,
    required this.label,
    required this.detail,
    required this.levels,
    required this.treatedPercent,
    required this.savingPercent,
    required this.treatedHa,
    required this.chemicalL,
    required this.blanketL,
    required this.savedL,
    required this.recommended,
  });

  /// The blanket row exists as a baseline to compare against, not as
  /// something the aircraft can be told to fly from a prescription.
  bool get isBlanket => id == 'blanket';

  factory SprayOption.fromJson(Map<String, dynamic> json) => SprayOption(
    id: json['id']?.toString() ?? '',
    label: json['label']?.toString() ?? '',
    detail: json['detail']?.toString() ?? '',
    levels:
        (json['levels'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    treatedPercent: _int(json['treated_percent']),
    savingPercent: _int(json['saving_percent']),
    treatedHa: _doubleOrNull(json['treated_ha']),
    chemicalL: _doubleOrNull(json['chemical_l']),
    blanketL: _doubleOrNull(json['blanket_l']),
    savedL: _doubleOrNull(json['saved_l']),
    recommended: json['recommended'] == true,
  );

  @override
  List<Object?> get props => [id, treatedPercent, savingPercent, recommended];
}

/// Whether the capture can be turned into coordinates, and on what assumptions.
class SprayCoverage extends Equatable {
  final bool georeferenced;
  final double? gsdM;
  final List<double> coverageM;
  final bool headingAssumedNorth;
  final List<String> missing;
  final List<String> assumptions;

  const SprayCoverage({
    required this.georeferenced,
    required this.gsdM,
    required this.coverageM,
    required this.headingAssumedNorth,
    required this.missing,
    required this.assumptions,
  });

  factory SprayCoverage.fromJson(Map<String, dynamic> json) => SprayCoverage(
    georeferenced: json['georeferenced'] == true,
    gsdM: _doubleOrNull(json['gsd_m']),
    coverageM:
        (json['coverage_m'] as List?)?.map((e) => _double(e)).toList() ??
        const [],
    headingAssumedNorth: json['heading_assumed_north'] == true,
    missing:
        (json['missing'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
    assumptions:
        (json['assumptions'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
  );

  @override
  List<Object?> get props => [georeferenced, gsdM, missing];
}

/// The mission a chosen option would fly, plus what it would actually cost.
class SprayPlan extends Equatable {
  final int prescriptionId;
  final String option;
  final List<String> levels;
  final int patches;
  final int waypoints;
  final double pathLengthM;
  final double estimatedMinutes;
  final String mechanism;

  /// False on an on/off pump — the reduced rate over moderate zones is not
  /// something that rig can deliver, and the saving below reflects that.
  final bool variableRate;
  final double swathM;

  final int treatedPercent;
  final int savingPercent;
  final double? chemicalL;
  final double? blanketL;
  final double? savedL;

  const SprayPlan({
    required this.prescriptionId,
    required this.option,
    required this.levels,
    required this.patches,
    required this.waypoints,
    required this.pathLengthM,
    required this.estimatedMinutes,
    required this.mechanism,
    required this.variableRate,
    required this.swathM,
    required this.treatedPercent,
    required this.savingPercent,
    required this.chemicalL,
    required this.blanketL,
    required this.savedL,
  });

  factory SprayPlan.fromJson(Map<String, dynamic> json) {
    final summary = (json['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final economics = (json['economics'] as Map?)?.cast<String, dynamic>() ?? {};

    return SprayPlan(
      prescriptionId: _int(json['prescription_id']),
      option: json['option']?.toString() ?? '',
      levels:
          (json['levels'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      patches: _int(summary['patches']),
      waypoints: _int(summary['nav_waypoints']),
      pathLengthM: _double(summary['path_length_m']),
      estimatedMinutes: _double(summary['estimated_minutes']),
      mechanism: summary['mechanism']?.toString() ?? 'sprayer',
      variableRate: summary['variable_rate'] == true,
      swathM: _double(summary['swath_m']),
      treatedPercent: _int(economics['treated_percent']),
      savingPercent: _int(economics['saving_percent']),
      chemicalL: _doubleOrNull(economics['chemical_l']),
      blanketL: _doubleOrNull(economics['blanket_l']),
      savedL: _doubleOrNull(economics['saved_l']),
    );
  }

  @override
  List<Object?> get props => [prescriptionId, option, patches, savingPercent];
}

/// A past prescription, for the history list.
class SprayPrescriptionSummary extends Equatable {
  final int id;
  final String? fieldName;
  final String sessionId;
  final String shotId;
  final String status;
  final String? chosenOption;
  final int? savingPercent;
  final int patchCount;
  final DateTime? createdAt;

  const SprayPrescriptionSummary({
    required this.id,
    required this.fieldName,
    required this.sessionId,
    required this.shotId,
    required this.status,
    required this.chosenOption,
    required this.savingPercent,
    required this.patchCount,
    required this.createdAt,
  });

  factory SprayPrescriptionSummary.fromJson(Map<String, dynamic> json) =>
      SprayPrescriptionSummary(
        id: _int(json['id']),
        fieldName: json['field_name']?.toString(),
        sessionId: json['session_id']?.toString() ?? '',
        shotId: json['shot_id']?.toString() ?? '',
        status: json['status']?.toString() ?? 'proposed',
        chosenOption: json['chosen_option']?.toString(),
        savingPercent: json['saving_percent'] == null
            ? null
            : _int(json['saving_percent']),
        patchCount: _int(json['patch_count']),
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      );

  @override
  List<Object?> get props => [id, status, chosenOption, savingPercent];
}

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double _double(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0.0;
}

double? _doubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

Map<String, double> _doubleMap(dynamic value) {
  if (value is! Map) return const {};
  return value.map((key, v) => MapEntry(key.toString(), _double(v)));
}

Map<String, double?> _nullableDoubleMap(dynamic value) {
  if (value is! Map) return const {};
  return value.map((key, v) => MapEntry(key.toString(), _doubleOrNull(v)));
}
