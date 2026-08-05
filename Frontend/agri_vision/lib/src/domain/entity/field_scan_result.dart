import 'package:equatable/equatable.dart';

/// One canopy frame scanned for weeds and disease (`/api/fieldscan/analyze`).
class FieldScanResult extends Equatable {
  final String status;
  final int? scanId;
  final String? crop;
  final String? cropName;

  final WeedFinding weeds;
  final DiseaseFinding disease;

  final String severityLevel; // none | low | moderate | high
  final int affectedPercent;
  final bool isHealthy;

  final List<ScanAction> actions;
  final String? overlayUrl;
  final String disclaimer;

  /// Where the frame was taken, when it came from a geotagged capture.
  final double? lat;
  final double? lon;

  const FieldScanResult({
    required this.status,
    required this.scanId,
    required this.crop,
    required this.cropName,
    required this.weeds,
    required this.disease,
    required this.severityLevel,
    required this.affectedPercent,
    required this.isHealthy,
    required this.actions,
    required this.overlayUrl,
    required this.disclaimer,
    this.lat,
    this.lon,
  });

  bool get isOk => status == 'ok';

  factory FieldScanResult.fromJson(Map<String, dynamic> json) {
    final severity = (json['severity'] as Map?)?.cast<String, dynamic>() ?? {};

    return FieldScanResult(
      status: json['status']?.toString() ?? 'error',
      scanId: json['scan_id'] == null ? null : _int(json['scan_id']),
      crop: json['crop']?.toString(),
      cropName: json['crop_name']?.toString(),
      weeds: WeedFinding.fromJson(
        (json['weeds'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      disease: DiseaseFinding.fromJson(
        (json['disease'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      severityLevel: severity['level']?.toString() ?? 'none',
      affectedPercent: _int(severity['affected_percent']),
      isHealthy: json['is_healthy'] == true,
      actions:
          (json['actions'] as List?)
              ?.map((e) => ScanAction.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      overlayUrl: json['overlay_url']?.toString(),
      disclaimer: json['disclaimer']?.toString() ?? '',
      lat: _doubleOrNull(json['lat']),
      lon: _doubleOrNull(json['lon']),
    );
  }

  @override
  List<Object?> get props => [status, scanId, disease, weeds, severityLevel];
}

/// The weed half of a scan.
class WeedFinding extends Equatable {
  /// Weed cover as a share of the ground (0..1).
  final double coverage;
  final int percent;
  final String level; // none | low | moderate | high
  final String advice;

  /// How the weeds were told apart from the crop — this is what the number's
  /// reliability rests on, so the UI shows it rather than hiding it.
  /// `inter-row` (row geometry) | `appearance` (colour/texture) |
  /// `inconclusive` | `none`
  final String method;
  final bool rowStructureFound;
  final double confidence;
  final String note;
  final int patchCount;
  final List<LikelyWeed> likelyWeeds;

  const WeedFinding({
    required this.coverage,
    required this.percent,
    required this.level,
    required this.advice,
    required this.method,
    required this.rowStructureFound,
    required this.confidence,
    required this.note,
    required this.patchCount,
    required this.likelyWeeds,
  });

  bool get needsAction => level == 'moderate' || level == 'high';

  String get methodLabel => switch (method) {
    'inter-row' => 'Crop-row geometry',
    'appearance' => 'Colour & texture (indicative)',
    'inconclusive' => 'Inconclusive',
    _ => 'No vegetation',
  };

  factory WeedFinding.fromJson(Map<String, dynamic> json) {
    final pressure = (json['pressure'] as Map?)?.cast<String, dynamic>() ?? {};
    final rows = (json['row_structure'] as Map?)?.cast<String, dynamic>() ?? {};

    return WeedFinding(
      coverage: _double(json['weed_coverage']),
      percent: _int(pressure['percent']),
      level: pressure['level']?.toString() ?? 'none',
      advice: pressure['advice']?.toString() ?? '',
      method: json['method']?.toString() ?? 'none',
      rowStructureFound: rows['found'] == true,
      confidence: _double(json['confidence']),
      note: json['note']?.toString() ?? '',
      patchCount: (json['patches'] as List?)?.length ?? 0,
      likelyWeeds:
          (json['likely_weeds'] as List?)
              ?.whereType<Map>()
              .map((e) => LikelyWeed.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
    );
  }

  @override
  List<Object?> get props => [coverage, level, method, patchCount];
}

/// A weed the crop is known to attract, with how to tell it apart.
class LikelyWeed extends Equatable {
  final String id;
  final String name;
  final String localName;
  final String type; // grass | sedge | broadleaf
  final List<String> identify;
  final List<String> control;

  const LikelyWeed({
    required this.id,
    required this.name,
    required this.localName,
    required this.type,
    required this.identify,
    required this.control,
  });

  factory LikelyWeed.fromJson(Map<String, dynamic> json) => LikelyWeed(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    localName: json['local_name']?.toString() ?? '',
    type: json['type']?.toString() ?? '',
    identify: _stringList(json['identify']),
    control: _stringList(json['control']),
  );

  @override
  List<Object?> get props => [id, name, type];
}

/// The disease half of a scan.
class DiseaseFinding extends Equatable {
  final String id;
  final String name;
  final String pathogen;
  final List<String> symptoms;
  final String favours;
  final List<String> management;
  final String severityNote;
  final double confidence;

  /// `model` when a trained CNN answered, `heuristic` otherwise. Worth showing:
  /// the two are not equally trustworthy.
  final String source;
  final String note;
  final List<String> alternatives;

  const DiseaseFinding({
    required this.id,
    required this.name,
    required this.pathogen,
    required this.symptoms,
    required this.favours,
    required this.management,
    required this.severityNote,
    required this.confidence,
    required this.source,
    required this.note,
    required this.alternatives,
  });

  int get confidencePercent => (confidence * 100).round();
  bool get isHealthy => id == 'healthy';

  factory DiseaseFinding.fromJson(Map<String, dynamic> json) => DiseaseFinding(
    id: json['id']?.toString() ?? 'general_stress',
    name: json['name']?.toString() ?? 'Unknown',
    pathogen: json['pathogen']?.toString() ?? '',
    symptoms: _stringList(json['symptoms']),
    favours: json['favours']?.toString() ?? '',
    management: _stringList(json['management']),
    severityNote: json['severity_note']?.toString() ?? '',
    confidence: _double(json['confidence']),
    source: json['source']?.toString() ?? 'heuristic',
    note: json['note']?.toString() ?? '',
    alternatives:
        (json['alternatives'] as List?)
            ?.whereType<Map>()
            .map((e) => e['name']?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .toList() ??
        const [],
  );

  @override
  List<Object?> get props => [id, confidence, source];
}

/// One recommended action, lowest [priority] number first.
class ScanAction extends Equatable {
  final int order;
  final int priority;
  final String category; // disease | weed | spray | monitoring | context
  final String title;
  final String detail;

  const ScanAction({
    required this.order,
    required this.priority,
    required this.category,
    required this.title,
    required this.detail,
  });

  factory ScanAction.fromJson(Map<String, dynamic> json) => ScanAction(
    order: _int(json['order']),
    priority: _int(json['priority']),
    category: json['category']?.toString() ?? 'monitoring',
    title: json['title']?.toString() ?? '',
    detail: json['detail']?.toString() ?? '',
  );

  @override
  List<Object?> get props => [order, category, title];
}

/// The field-level answer after a whole low-pace pass.
class FieldScanSummary extends Equatable {
  final String sessionId;
  final String? crop;
  final int frames;
  final String weedLevel;
  final int weedPercent;
  final int framesAboveModerate;
  final List<ConditionCount> conditions;
  final ConditionCount? dominantProblem;
  final int diseasedFrames;
  final double diseaseIncidence;
  final List<Hotspot> hotspots;
  final String summary;
  final List<ScanAction> actions;

  const FieldScanSummary({
    required this.sessionId,
    required this.crop,
    required this.frames,
    required this.weedLevel,
    required this.weedPercent,
    required this.framesAboveModerate,
    required this.conditions,
    required this.dominantProblem,
    required this.diseasedFrames,
    required this.diseaseIncidence,
    required this.hotspots,
    required this.summary,
    required this.actions,
  });

  factory FieldScanSummary.fromJson(
    Map<String, dynamic> json, {
    String sessionId = '',
  }) {
    final weed = (json['weed'] as Map?)?.cast<String, dynamic>() ?? {};
    final dominant = (json['dominant_problem'] as Map?)?.cast<String, dynamic>();

    return FieldScanSummary(
      sessionId: sessionId,
      crop: json['crop']?.toString(),
      frames: _int(json['frames']),
      weedLevel: weed['level']?.toString() ?? 'none',
      weedPercent: _int(weed['percent']),
      framesAboveModerate: _int(weed['frames_above_moderate']),
      conditions:
          (json['conditions'] as List?)
              ?.map((e) => ConditionCount.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      dominantProblem: dominant == null ? null : ConditionCount.fromJson(dominant),
      diseasedFrames: _int(json['diseased_frames']),
      diseaseIncidence: _double(json['disease_incidence']),
      hotspots:
          (json['hotspots'] as List?)
              ?.map((e) => Hotspot.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      summary: json['summary']?.toString() ?? '',
      actions:
          (json['actions'] as List?)
              ?.map((e) => ScanAction.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
    );
  }

  @override
  List<Object?> get props => [sessionId, frames, weedLevel, diseasedFrames];
}

class ConditionCount extends Equatable {
  final String id;
  final String name;
  final int frames;
  final double frameShare;
  final String worstSeverity;

  const ConditionCount({
    required this.id,
    required this.name,
    required this.frames,
    required this.frameShare,
    required this.worstSeverity,
  });

  int get sharePercent => (frameShare * 100).round();

  factory ConditionCount.fromJson(Map<String, dynamic> json) => ConditionCount(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    frames: _int(json['frames']),
    frameShare: _double(json['frame_share']),
    worstSeverity: json['worst_severity']?.toString() ?? 'none',
  );

  @override
  List<Object?> get props => [id, frames, frameShare];
}

/// A frame bad enough to be worth a targeted pass, with its coordinates.
class Hotspot extends Equatable {
  final double lat;
  final double lon;
  final String? condition;
  final String? severity;
  final String? weedPressure;

  const Hotspot({
    required this.lat,
    required this.lon,
    this.condition,
    this.severity,
    this.weedPressure,
  });

  factory Hotspot.fromJson(Map<String, dynamic> json) => Hotspot(
    lat: _double(json['lat']),
    lon: _double(json['lon']),
    condition: json['condition']?.toString(),
    severity: json['severity']?.toString(),
    weedPressure: json['weed_pressure']?.toString(),
  );

  @override
  List<Object?> get props => [lat, lon, condition];
}

/// A crop the scanner knows, for the picker.
class CropOption extends Equatable {
  final String id;
  final String name;
  final String localName;
  final String season;
  final int diseaseCount;

  const CropOption({
    required this.id,
    required this.name,
    required this.localName,
    required this.season,
    required this.diseaseCount,
  });

  factory CropOption.fromJson(Map<String, dynamic> json) => CropOption(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    localName: json['local_name']?.toString() ?? '',
    season: json['season']?.toString() ?? '',
    diseaseCount: _int(json['disease_count']),
  );

  @override
  List<Object?> get props => [id, name];
}

List<String> _stringList(dynamic value) =>
    (value as List?)?.map((e) => e.toString()).toList() ?? const [];

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
