import 'package:equatable/equatable.dart';

import 'field_scan_result.dart';
// Both K-means paths — the multispectral index and the RGB detections — emit
// the same costed options, so the survey reuses the spray screen's model
// rather than defining a second one that would drift from it.
import 'spray_prescription.dart' show SprayOption;
import 'treatment_entity.dart';

/// Which cameras the aircraft flies with.
///
/// This is the branch that shapes the whole flight, not a preference:
///
///   [multispectral] — band cameras. Vegetation indices and a K-means zone
///                     map. Accurate about *where* the field is stressed and
///                     silent about *which* disease it is, because a single
///                     band is a greyscale image of one wavelength and not
///                     what the CNN was trained on.
///   [ipCamera]      — the ordinary RGB feed. The CNN runs on the video as the
///                     aircraft flies and names the disease; the map is
///                     K-means over the geotagged detections.
///   [both]          — both rigs. The CNN says what, the bands say where.
enum CameraMode {
  multispectral('multispectral', 'Multispectral'),
  ipCamera('rgb', 'IP camera'),
  both('both', 'Both');

  const CameraMode(this.id, this.label);

  final String id;
  final String label;

  static CameraMode fromId(String? id) {
    for (final mode in CameraMode.values) {
      if (mode.id == id) return mode;
    }
    return CameraMode.ipCamera;
  }

  bool get usesRgb => this != CameraMode.multispectral;
  bool get usesBands => this != CameraMode.ipCamera;
}

/// What the CNN is asked to look for on this pass.
///
/// [weed] is the "set the drone for weed detection" setting. It is not a
/// label: skipping the disease CNN roughly halves the per-frame cost, which is
/// the difference between a readout describing where the aircraft *is* and one
/// describing where it was.
enum DetectionTarget {
  disease('disease', 'Disease only'),
  weed('weed', 'Weeds only'),
  both('both', 'Disease + weeds');

  const DetectionTarget(this.id, this.label);

  final String id;
  final String label;

  static DetectionTarget fromId(String? id) {
    for (final target in DetectionTarget.values) {
      if (target.id == id) return target;
    }
    return DetectionTarget.both;
  }
}

/// One camera mode as the server reports it, including why it is unavailable.
///
/// The app disables a mode rather than letting the operator pick one and
/// discover at thirty metres that no camera is registered for it.
class CameraModeOption extends Equatable {
  final CameraMode mode;
  final String name;
  final String detail;
  final bool available;

  /// Empty when available; otherwise what is missing, in words.
  final String reason;
  final int cameraCount;

  const CameraModeOption({
    required this.mode,
    required this.name,
    required this.detail,
    required this.available,
    required this.reason,
    required this.cameraCount,
  });

  factory CameraModeOption.fromJson(Map<String, dynamic> json) {
    return CameraModeOption(
      mode: CameraMode.fromId(json['id']?.toString()),
      name: json['name']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
      available: json['available'] == true,
      reason: json['reason']?.toString() ?? '',
      cameraCount: (json['cameras'] as List?)?.length ?? 0,
    );
  }

  @override
  List<Object?> get props => [mode, available, cameraCount];
}

/// What this rig can fly, plus whether the crop advisor is configured.
class SurveyCapabilities extends Equatable {
  final List<CameraModeOption> cameraModes;
  final bool advisorAvailable;
  final String advisorMessage;

  /// Whether the pump can fly a genuinely reduced rate over moderate zones.
  /// On an on/off rig the saving comes only from the ground that is skipped,
  /// and the quoted number has to match.
  final bool variableRate;
  final String sprayMechanism;

  /// The flight link, and what its absence costs.
  ///
  /// Not a gate. Detection needs no drone — the CNN reads whatever the camera
  /// sends — so this exists to *say* what the survey will produce, not to
  /// stop it.
  final FlightLink flightLink;

  const SurveyCapabilities({
    required this.cameraModes,
    required this.advisorAvailable,
    required this.advisorMessage,
    required this.variableRate,
    required this.sprayMechanism,
    this.flightLink = FlightLink.unknown,
  });

  static const SurveyCapabilities unknown = SurveyCapabilities(
    cameraModes: [],
    advisorAvailable: false,
    advisorMessage: '',
    variableRate: false,
    sprayMechanism: '',
  );

  bool get hasAnyMode => cameraModes.any((option) => option.available);

  CameraModeOption? optionFor(CameraMode mode) {
    for (final option in cameraModes) {
      if (option.mode == mode) return option;
    }
    return null;
  }

  /// The mode to preselect: the richest one this rig can actually fly.
  CameraMode get defaultMode {
    for (final mode in [CameraMode.both, CameraMode.ipCamera, CameraMode.multispectral]) {
      if (optionFor(mode)?.available == true) return mode;
    }
    return CameraMode.ipCamera;
  }

  factory SurveyCapabilities.fromJson(Map<String, dynamic> json) {
    final advisor = (json['advisor'] as Map?)?.cast<String, dynamic>() ?? const {};
    final hardware =
        (json['spray_hardware'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SurveyCapabilities(
      cameraModes:
          (json['camera_modes'] as List?)
              ?.map((e) =>
                  CameraModeOption.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      advisorAvailable: advisor['available'] == true,
      advisorMessage: advisor['message']?.toString() ?? '',
      variableRate: hardware['variable_rate'] == true,
      sprayMechanism: hardware['mechanism']?.toString() ?? '',
      flightLink: FlightLink.fromJson(
        (json['flight_link'] as Map?)?.cast<String, dynamic>(),
      ),
    );
  }

  @override
  List<Object?> get props =>
      [cameraModes, advisorAvailable, variableRate, flightLink];
}

/// Whether a vehicle is on the link, and therefore whether this survey can
/// produce a map as well as a diagnosis.
///
/// The distinction is the whole point of the type. Detection works with a
/// camera and nothing else; position is what the aircraft adds. Without it
/// there is no K-means hotspot map and nothing to fly a spray mission
/// against — so the survey should still run, and should say so plainly rather
/// than promising a spray plan it cannot build.
class FlightLink extends Equatable {
  const FlightLink({
    required this.connected,
    required this.canMap,
    required this.detail,
    this.gpsFix,
  });

  /// A vehicle is answering heartbeats.
  final bool connected;

  /// Connected *and* holding a 3D fix — the bar for building a spray map.
  final bool canMap;

  /// The server's own one-line explanation, so the wording lives in one place.
  final String detail;

  final int? gpsFix;

  static const FlightLink unknown = FlightLink(
    connected: false,
    canMap: false,
    detail: '',
  );

  factory FlightLink.fromJson(Map<String, dynamic>? json) {
    if (json == null) return unknown;
    return FlightLink(
      connected: json['connected'] == true,
      canMap: json['can_map'] == true,
      detail: json['detail']?.toString() ?? '',
      gpsFix: (json['gps_fix'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props => [connected, canMap, detail, gpsFix];
}

/// One survey flight, from camera selection to a sprayed field.
class SurveyRun extends Equatable {
  final int id;
  final String sessionId;
  final String? fieldName;
  final CameraMode cameraMode;
  final DetectionTarget detectionTarget;
  final String? crop;
  final int? rgbCameraId;

  /// planned | flying | analysed | authorised | spraying | completed | cancelled
  final String status;

  final int framesScanned;
  final int diseasedFrames;
  final int? weedPercent;
  final int? healthScore;
  final String? dominantCondition;
  final int? prescriptionId;

  final bool tankFilled;
  final double? tankLitres;
  final String? tankProduct;
  final bool sprayAuthorised;
  final String? authorisedBy;
  final String? chosenOption;

  final DateTime? startedAt;
  final DateTime? finishedAt;

  const SurveyRun({
    required this.id,
    required this.sessionId,
    required this.fieldName,
    required this.cameraMode,
    required this.detectionTarget,
    required this.crop,
    required this.rgbCameraId,
    required this.status,
    required this.framesScanned,
    required this.diseasedFrames,
    required this.weedPercent,
    required this.healthScore,
    required this.dominantCondition,
    required this.prescriptionId,
    required this.tankFilled,
    required this.tankLitres,
    required this.tankProduct,
    required this.sprayAuthorised,
    required this.authorisedBy,
    required this.chosenOption,
    required this.startedAt,
    required this.finishedAt,
  });

  bool get isFlying => status == 'flying' || status == 'planned';
  bool get isFinished =>
      status == 'analysed' ||
      status == 'authorised' ||
      status == 'spraying' ||
      status == 'completed';
  bool get isSpraying => status == 'spraying';
  bool get canSpray => prescriptionId != null && isFinished;

  factory SurveyRun.fromJson(Map<String, dynamic> json) {
    final tank = (json['tank'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SurveyRun(
      id: int.tryParse('${json['id']}') ?? 0,
      sessionId: json['session_id']?.toString() ?? '',
      fieldName: json['field_name']?.toString(),
      cameraMode: CameraMode.fromId(json['camera_mode']?.toString()),
      detectionTarget: DetectionTarget.fromId(json['detection_target']?.toString()),
      crop: json['crop']?.toString(),
      rgbCameraId: json['rgb_camera_id'] == null
          ? null
          : int.tryParse('${json['rgb_camera_id']}'),
      status: json['status']?.toString() ?? 'planned',
      framesScanned: int.tryParse('${json['frames_scanned']}') ?? 0,
      diseasedFrames: int.tryParse('${json['diseased_frames']}') ?? 0,
      weedPercent: json['weed_percent'] == null
          ? null
          : int.tryParse('${json['weed_percent']}'),
      healthScore: json['health_score'] == null
          ? null
          : int.tryParse('${json['health_score']}'),
      dominantCondition: json['dominant_condition']?.toString(),
      prescriptionId: json['prescription_id'] == null
          ? null
          : int.tryParse('${json['prescription_id']}'),
      tankFilled: tank['filled'] == true,
      tankLitres: tank['litres'] == null
          ? null
          : double.tryParse('${tank['litres']}'),
      tankProduct: tank['product']?.toString(),
      sprayAuthorised: json['spray_authorised'] == true,
      authorisedBy: json['authorised_by']?.toString(),
      chosenOption: json['chosen_option']?.toString(),
      startedAt: DateTime.tryParse('${json['started_at']}'),
      finishedAt: DateTime.tryParse('${json['finished_at']}'),
    );
  }

  @override
  List<Object?> get props => [id, status, healthScore, prescriptionId];
}

/// The one number and one sentence at the top of the summary.
class CropHealth extends Equatable {
  /// 0–100, or null when nothing was scanned. Null is not zero: a flight that
  /// scanned nothing has *no* reading, and showing 0 would read as a dead crop.
  final int? score;

  /// good | fair | poor | critical | unknown
  final String band;
  final String headline;
  final String detail;

  /// False when too few frames were scanned for the percentages to describe a
  /// block rather than a few seconds of hovering.
  final bool confident;

  const CropHealth({
    required this.score,
    required this.band,
    required this.headline,
    required this.detail,
    required this.confident,
  });

  static const CropHealth unknown = CropHealth(
    score: null,
    band: 'unknown',
    headline: 'nothing was scanned on this pass',
    detail: '',
    confident: false,
  );

  bool get needsAction => band == 'poor' || band == 'critical';

  factory CropHealth.fromJson(Map<String, dynamic> json) {
    return CropHealth(
      score: json['score'] == null ? null : int.tryParse('${json['score']}'),
      band: json['band']?.toString() ?? 'unknown',
      headline: json['headline']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
      confident: json['confident'] == true,
    );
  }

  @override
  List<Object?> get props => [score, band, confident];
}

/// One condition found on the pass, with the treatment behind it.
class SurveyTreatment extends Equatable {
  final String condition;
  final String conditionId;
  final double frameShare;
  final String worstSeverity;
  final Treatment treatment;

  const SurveyTreatment({
    required this.condition,
    required this.conditionId,
    required this.frameShare,
    required this.worstSeverity,
    required this.treatment,
  });

  int get sharePercent => (frameShare * 100).round();

  factory SurveyTreatment.fromJson(Map<String, dynamic> json) {
    return SurveyTreatment(
      condition: json['condition']?.toString() ?? '',
      conditionId: json['condition_id']?.toString() ?? '',
      frameShare: double.tryParse('${json['frame_share']}') ?? 0,
      worstSeverity: json['worst_severity']?.toString() ?? 'none',
      // The treatment fields are merged into the same object server-side, so
      // the whole map parses as a Treatment.
      treatment: Treatment.fromJson(json),
    );
  }

  @override
  List<Object?> get props => [conditionId, frameShare, worstSeverity];
}

/// One step of the action plan.
///
/// The scan's own actions ("confirm X on the ground") are agronomy advice.
/// Rows carrying a [product] are the step that was previously missing between
/// advice and a flight: which chemical, in which tank.
class SurveyAction extends Equatable {
  final int order;
  final int priority;

  /// disease | weed | spray | no_spray | monitoring | context
  final String category;
  final String title;
  final String detail;
  final SprayProduct? product;
  final int? pass;

  /// For a `no_spray` row: what to do instead of flying.
  final List<String> instead;

  const SurveyAction({
    required this.order,
    required this.priority,
    required this.category,
    required this.title,
    required this.detail,
    required this.product,
    required this.pass,
    required this.instead,
  });

  bool get isSpray => category == 'spray';
  bool get isBlocked => category == 'no_spray';

  factory SurveyAction.fromJson(Map<String, dynamic> json) {
    final product = (json['product'] as Map?)?.cast<String, dynamic>();
    return SurveyAction(
      order: int.tryParse('${json['order']}') ?? 0,
      priority: int.tryParse('${json['priority']}') ?? 3,
      category: json['category']?.toString() ?? 'monitoring',
      title: json['title']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
      product: product == null ? null : SprayProduct.fromJson(product),
      pass: json['pass'] == null ? null : int.tryParse('${json['pass']}'),
      instead: (json['instead'] as List?)?.map((e) => '$e').toList() ?? const [],
    );
  }

  @override
  List<Object?> get props => [order, category, title];
}

/// One K-means zone on the treatment map.
class TreatmentZone extends Equatable {
  final int cluster;

  /// severe | moderate | healthy
  final String severity;
  final double? lat;
  final double? lon;
  final double radiusM;
  final int frames;
  final double meanIndex;

  const TreatmentZone({
    required this.cluster,
    required this.severity,
    required this.lat,
    required this.lon,
    required this.radiusM,
    required this.frames,
    required this.meanIndex,
  });

  bool get isTreated => severity == 'severe' || severity == 'moderate';

  factory TreatmentZone.fromJson(Map<String, dynamic> json) {
    return TreatmentZone(
      cluster: int.tryParse('${json['cluster']}') ?? 0,
      severity: json['severity']?.toString() ?? 'healthy',
      lat: double.tryParse('${json['lat']}'),
      lon: double.tryParse('${json['lon']}'),
      radiusM: double.tryParse('${json['radius_m']}') ?? 0,
      frames: int.tryParse('${json['frames'] ?? json['pixels']}') ?? 0,
      meanIndex: double.tryParse('${json['mean_index']}') ?? 0,
    );
  }

  @override
  List<Object?> get props => [cluster, severity, lat, lon];
}

/// The K-means map a spray run would follow.
class TreatmentMap extends Equatable {
  final int? prescriptionId;

  /// `multispectral` (K-means over a vegetation index) or `rgb_detections`
  /// (K-means over the CNN's geotagged verdicts). Shown, because the two are
  /// not equally strong evidence.
  final String source;
  final String indexName;
  final List<TreatmentZone> zones;
  final int patchCount;
  final List<SprayOption> options;
  final double? fieldHa;
  final String? mapUrl;
  final bool lowContrast;
  final List<String> notes;
  final List<String> assumptions;
  final bool canGeoreference;

  const TreatmentMap({
    required this.prescriptionId,
    required this.source,
    required this.indexName,
    required this.zones,
    required this.patchCount,
    required this.options,
    required this.fieldHa,
    required this.mapUrl,
    required this.lowContrast,
    required this.notes,
    required this.assumptions,
    required this.canGeoreference,
  });

  bool get isFlyable => canGeoreference && patchCount > 0;

  /// Everything except the blanket baseline — the choices actually on offer.
  List<SprayOption> get targetedOptions =>
      options.where((option) => !option.isBlanket).toList();

  SprayOption? get recommendedOption {
    for (final option in targetedOptions) {
      if (option.recommended) return option;
    }
    return targetedOptions.isEmpty ? null : targetedOptions.first;
  }

  factory TreatmentMap.fromJson(Map<String, dynamic> json) {
    final coverage = (json['coverage'] as Map?)?.cast<String, dynamic>() ?? const {};
    final outputs = (json['outputs'] as Map?)?.cast<String, dynamic>() ?? const {};
    return TreatmentMap(
      prescriptionId: json['prescription_id'] == null
          ? null
          : int.tryParse('${json['prescription_id']}'),
      source: json['source']?.toString() ?? '',
      indexName: json['index_name']?.toString() ?? '',
      zones:
          (json['clusters'] as List?)
              ?.map((e) => TreatmentZone.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      patchCount: int.tryParse('${json['patch_count']}') ?? 0,
      options:
          (json['options'] as List?)
              ?.map((e) => SprayOption.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      fieldHa: double.tryParse('${json['field_ha']}'),
      mapUrl: outputs['prescription_map']?.toString(),
      lowContrast: json['low_contrast'] == true,
      notes: (json['notes'] as List?)?.map((e) => '$e').toList() ?? const [],
      assumptions:
          (coverage['assumptions'] as List?)?.map((e) => '$e').toList() ?? const [],
      // Absent means the older multispectral shape, which only omits the key
      // when it *can* georeference.
      canGeoreference: coverage['can_georeference'] != false,
    );
  }

  @override
  List<Object?> get props => [prescriptionId, source, patchCount, zones];
}

/// Everything a finished survey produced.
class SurveySummary extends Equatable {
  final int runId;
  final CameraMode cameraMode;
  final DetectionTarget detectionTarget;
  final String? crop;
  final String? cropName;
  final String? fieldName;

  final CropHealth health;

  /// The raw field-level scan aggregate — conditions, hotspots, weed pressure.
  final FieldScanSummary? scan;

  final List<SurveyTreatment> treatments;
  final TankPlan tankPlan;
  final List<SurveyAction> actionPlan;
  final TreatmentMap? treatmentMap;

  final bool advisorAvailable;
  final List<String> notes;
  final String disclaimer;

  const SurveySummary({
    required this.runId,
    required this.cameraMode,
    required this.detectionTarget,
    required this.crop,
    required this.cropName,
    required this.fieldName,
    required this.health,
    required this.scan,
    required this.treatments,
    required this.tankPlan,
    required this.actionPlan,
    required this.treatmentMap,
    required this.advisorAvailable,
    required this.notes,
    required this.disclaimer,
  });

  /// Whether the "fill the tank and authorise" step should be offered at all.
  /// Three things must all be true, and each is a different way for a flight
  /// to be pointless: something to spray, somewhere to spray it, and a
  /// prescription the aircraft can be given.
  bool get canOfferSpray =>
      tankPlan.hasSomethingToSpray &&
      (treatmentMap?.isFlyable ?? false) &&
      treatmentMap?.prescriptionId != null;

  factory SurveySummary.fromJson(Map<String, dynamic> json) {
    final scan = (json['scan'] as Map?)?.cast<String, dynamic>();
    final map = (json['prescription'] as Map?)?.cast<String, dynamic>();
    final plan = (json['tank_plan'] as Map?)?.cast<String, dynamic>();
    final advisor = (json['advisor'] as Map?)?.cast<String, dynamic>() ?? const {};

    return SurveySummary(
      runId: int.tryParse('${json['run_id']}') ?? 0,
      cameraMode: CameraMode.fromId(json['camera_mode']?.toString()),
      detectionTarget: DetectionTarget.fromId(json['detection_target']?.toString()),
      crop: json['crop']?.toString(),
      cropName: json['crop_name']?.toString(),
      fieldName: json['field_name']?.toString(),
      health: CropHealth.fromJson(
        (json['health'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      scan: (scan == null || scan['status'] != 'ok')
          ? null
          : FieldScanSummary.fromJson(scan),
      treatments:
          (json['treatments'] as List?)
              ?.map((e) => SurveyTreatment.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      tankPlan: plan == null ? TankPlan.empty : TankPlan.fromJson(plan),
      actionPlan:
          (json['action_plan'] as List?)
              ?.map((e) => SurveyAction.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      treatmentMap: map == null ? null : TreatmentMap.fromJson(map),
      advisorAvailable: advisor['available'] == true,
      notes: (json['notes'] as List?)?.map((e) => '$e').toList() ?? const [],
      disclaimer: json['disclaimer']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [runId, health, treatments, tankPlan, treatmentMap];
}

/// The rolling readout while the aircraft is still over the field.
class SurveyProgress extends Equatable {
  final bool running;
  final int scanned;
  final int skipped;

  /// The most recent frame's verdict.
  final String? latestCondition;
  final double? latestConfidence;
  final String? latestSeverity;
  final int? latestWeedPercent;
  final double? lat;
  final double? lon;

  /// The rolling field-level answer over the analyser's window.
  final String rollingSummary;
  final int hotspots;

  /// live | reconnecting | stopped — a dropped link must say so rather than
  /// showing the last good frame as if it were current.
  final String streamState;
  final String? lastError;

  /// Multispectral shots taken so far during this run.
  final int shots;

  const SurveyProgress({
    required this.running,
    required this.scanned,
    required this.skipped,
    required this.latestCondition,
    required this.latestConfidence,
    required this.latestSeverity,
    required this.latestWeedPercent,
    required this.lat,
    required this.lon,
    required this.rollingSummary,
    required this.hotspots,
    required this.streamState,
    required this.lastError,
    required this.shots,
  });

  static const SurveyProgress none = SurveyProgress(
    running: false,
    scanned: 0,
    skipped: 0,
    latestCondition: null,
    latestConfidence: null,
    latestSeverity: null,
    latestWeedPercent: null,
    lat: null,
    lon: null,
    rollingSummary: '',
    hotspots: 0,
    streamState: 'stopped',
    lastError: null,
    shots: 0,
  );

  bool get signalLost => streamState == 'reconnecting' || streamState == 'error';
  bool get hasFix => lat != null && lon != null;

  factory SurveyProgress.fromJson(
    Map<String, dynamic>? analysis, {
    int shots = 0,
  }) {
    if (analysis == null) {
      return SurveyProgress.none.copyWith(shots: shots);
    }
    final latest = (analysis['latest'] as Map?)?.cast<String, dynamic>();
    final rolling = (analysis['rolling'] as Map?)?.cast<String, dynamic>();
    final stream = (analysis['stream'] as Map?)?.cast<String, dynamic>();
    final disease = (latest?['disease'] as Map?)?.cast<String, dynamic>();
    final weeds = (latest?['weeds'] as Map?)?.cast<String, dynamic>();
    final severity = (latest?['severity'] as Map?)?.cast<String, dynamic>();
    final coverage = double.tryParse('${weeds?['weed_coverage']}');

    return SurveyProgress(
      running: analysis['running'] == true,
      scanned: int.tryParse('${analysis['scanned']}') ?? 0,
      skipped: int.tryParse('${analysis['skipped']}') ?? 0,
      latestCondition: disease?['name']?.toString(),
      latestConfidence: double.tryParse('${disease?['confidence']}'),
      latestSeverity: severity?['level']?.toString(),
      latestWeedPercent: coverage == null ? null : (coverage * 100).round(),
      lat: double.tryParse('${latest?['lat']}'),
      lon: double.tryParse('${latest?['lon']}'),
      rollingSummary: rolling?['summary']?.toString() ?? '',
      hotspots: (rolling?['hotspots'] as List?)?.length ?? 0,
      streamState: stream?['state']?.toString() ?? 'stopped',
      lastError: analysis['last_error']?.toString(),
      shots: shots,
    );
  }

  SurveyProgress copyWith({int? shots}) {
    return SurveyProgress(
      running: running,
      scanned: scanned,
      skipped: skipped,
      latestCondition: latestCondition,
      latestConfidence: latestConfidence,
      latestSeverity: latestSeverity,
      latestWeedPercent: latestWeedPercent,
      lat: lat,
      lon: lon,
      rollingSummary: rollingSummary,
      hotspots: hotspots,
      streamState: streamState,
      lastError: lastError,
      shots: shots ?? this.shots,
    );
  }

  @override
  List<Object?> get props => [
    running,
    scanned,
    skipped,
    latestCondition,
    streamState,
    shots,
  ];
}
