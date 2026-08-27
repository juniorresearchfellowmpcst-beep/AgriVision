import 'package:equatable/equatable.dart';

/// What the backend says about one camera it is holding open.
///
/// This is the difference between "the app is showing a picture" and "the
/// aircraft is sending one". The video widget knows whether *its* socket is
/// healthy; only the server knows whether the camera is.
class LiveStreamStatus extends Equatable {
  final String key;
  final String name;

  /// `starting` | `live` | `reconnecting` | `stopped`
  final String state;

  /// The server's own verdict: live *and* the newest frame is recent. Trust
  /// this over [state], which can say `live` about a feed that stalled a
  /// moment ago.
  final bool live;

  final int viewers;
  final double fps;
  final int frames;
  final int reconnects;
  final double? frameAgeS;
  final int? width;
  final int? height;
  final String? lastError;

  const LiveStreamStatus({
    this.key = '',
    this.name = '',
    this.state = 'stopped',
    this.live = false,
    this.viewers = 0,
    this.fps = 0,
    this.frames = 0,
    this.reconnects = 0,
    this.frameAgeS,
    this.width,
    this.height,
    this.lastError,
  });

  String get resolution =>
      (width == null || height == null) ? '—' : '${width}x$height';

  /// One line for a status chip, in the operator's terms.
  String get label => switch (state) {
    'live' => live ? '${fps.toStringAsFixed(0)} fps' : 'Stalled',
    'starting' => 'Connecting',
    'reconnecting' => 'Reconnecting',
    _ => 'Offline',
  };

  factory LiveStreamStatus.fromJson(Map<String, dynamic> json) =>
      LiveStreamStatus(
        key: json['key']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        state: json['state']?.toString() ?? 'stopped',
        live: json['live'] == true,
        viewers: _int(json['viewers']),
        fps: _double(json['fps']),
        frames: _int(json['frames']),
        reconnects: _int(json['reconnects']),
        frameAgeS: _doubleOrNull(json['frame_age_s']),
        width: _intOrNull(json['width']),
        height: _intOrNull(json['height']),
        lastError: _stringOrNull(json['last_error']),
      );

  @override
  List<Object?> get props => [
    key,
    state,
    live,
    viewers,
    fps,
    frames,
    reconnects,
    frameAgeS,
    lastError,
  ];
}

/// One frame the live analyser scanned, reduced to the verdict.
class LiveScan extends Equatable {
  final String frameId;
  final String? cropName;
  final bool isHealthy;

  /// `none` | `low` | `moderate` | `high`
  final String severityLevel;
  final String diseaseName;
  final double diseaseConfidence;

  /// Where the detector's answer came from — `model` or `heuristic`. Shown
  /// because a heuristic guess and a trained model's answer do not deserve
  /// the same weight in a spraying decision.
  final String diseaseSource;

  final double weedCoverage;
  final String weedPressure;
  final int weedPatches;

  final double? lat;
  final double? lon;

  const LiveScan({
    this.frameId = '',
    this.cropName,
    this.isHealthy = true,
    this.severityLevel = 'none',
    this.diseaseName = '',
    this.diseaseConfidence = 0,
    this.diseaseSource = 'heuristic',
    this.weedCoverage = 0,
    this.weedPressure = 'none',
    this.weedPatches = 0,
    this.lat,
    this.lon,
  });

  bool get hasFix => lat != null && lon != null;

  String get weedPercent => '${(weedCoverage * 100).toStringAsFixed(1)}%';

  factory LiveScan.fromJson(Map<String, dynamic> json) {
    final disease = _map(json['disease']);
    final weeds = _map(json['weeds']);
    final severity = _map(json['severity']);
    final pressure = _map(weeds['pressure']);

    return LiveScan(
      frameId: json['frame_id']?.toString() ?? '',
      cropName: _stringOrNull(json['crop_name']),
      isHealthy: json['is_healthy'] == true,
      severityLevel: severity['level']?.toString() ?? 'none',
      diseaseName: disease['name']?.toString() ?? '',
      diseaseConfidence: _double(disease['confidence']),
      diseaseSource: disease['source']?.toString() ?? 'heuristic',
      weedCoverage: _double(weeds['weed_coverage']),
      weedPressure: pressure['level']?.toString() ?? 'none',
      weedPatches: _int(weeds['patches']),
      lat: _doubleOrNull(json['lat']),
      lon: _doubleOrNull(json['lon']),
    );
  }

  @override
  List<Object?> get props => [
    frameId,
    isHealthy,
    severityLevel,
    diseaseName,
    diseaseConfidence,
    weedCoverage,
    weedPressure,
    lat,
    lon,
  ];
}

/// A spot the rolling analysis flagged, with coordinates worth flying back to.
class LiveHotspot extends Equatable {
  final double lat;
  final double lon;
  final String? condition;
  final String? severity;
  final String? weedPressure;

  const LiveHotspot({
    required this.lat,
    required this.lon,
    this.condition,
    this.severity,
    this.weedPressure,
  });

  static LiveHotspot? fromJson(Map<String, dynamic> json) {
    final lat = _doubleOrNull(json['lat']);
    final lon = _doubleOrNull(json['lon']);
    // A hotspot with no fix cannot be flown back to, and a marker at (0, 0)
    // off the coast of Africa is worse than no marker.
    if (lat == null || lon == null) return null;
    return LiveHotspot(
      lat: lat,
      lon: lon,
      condition: _stringOrNull(json['condition']),
      severity: _stringOrNull(json['severity']),
      weedPressure: _stringOrNull(json['weed_pressure']),
    );
  }

  @override
  List<Object?> get props => [lat, lon, condition, severity, weedPressure];
}

/// The field-level answer over the analyser's rolling window.
class LiveRollup extends Equatable {
  final int frames;
  final String summary;
  final double meanWeedCoverage;
  final double maxWeedCoverage;
  final String weedPressure;
  final double diseaseIncidence;
  final String? dominantProblem;
  final List<LiveHotspot> hotspots;
  final List<String> actions;

  const LiveRollup({
    this.frames = 0,
    this.summary = '',
    this.meanWeedCoverage = 0,
    this.maxWeedCoverage = 0,
    this.weedPressure = 'none',
    this.diseaseIncidence = 0,
    this.dominantProblem,
    this.hotspots = const [],
    this.actions = const [],
  });

  bool get isEmpty => frames == 0;

  factory LiveRollup.fromJson(Map<String, dynamic> json) {
    final weed = _map(json['weed']);
    final dominant = _map(json['dominant_problem']);

    return LiveRollup(
      frames: _int(json['frames']),
      summary: json['summary']?.toString() ?? '',
      meanWeedCoverage: _double(weed['mean_coverage']),
      maxWeedCoverage: _double(weed['max_coverage']),
      weedPressure: weed['level']?.toString() ?? 'none',
      diseaseIncidence: _double(json['disease_incidence']),
      dominantProblem: _stringOrNull(dominant['name']),
      hotspots: ((json['hotspots'] as List?) ?? const [])
          .map((e) => LiveHotspot.fromJson(Map<String, dynamic>.from(e as Map)))
          .whereType<LiveHotspot>()
          .toList(),
      actions: ((json['actions'] as List?) ?? const [])
          .map(
            (e) => e is Map
                ? (e['action'] ?? e['detail'] ?? e['title'] ?? '').toString()
                : e.toString(),
          )
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }

  @override
  List<Object?> get props => [
    frames,
    summary,
    meanWeedCoverage,
    maxWeedCoverage,
    weedPressure,
    diseaseIncidence,
    dominantProblem,
    hotspots,
    actions,
  ];
}

/// Everything the backend reports about one running live analysis.
class LiveAnalysis extends Equatable {
  final String cameraKey;
  final String cameraName;
  final bool running;
  final String? crop;
  final String? fieldName;
  final double intervalS;

  /// Frames currently in the rolling window (not the total ever scanned).
  final int window;
  final int scanned;

  /// Frames the analyser could not use — a feed gap, or an unreadable frame.
  /// Shown because a summary built from 4 of 40 frames is a different claim
  /// from one built from all 40.
  final int skipped;

  final LiveScan? latest;
  final LiveRollup rolling;
  final LiveStreamStatus? stream;
  final String? lastError;

  const LiveAnalysis({
    this.cameraKey = '',
    this.cameraName = '',
    this.running = false,
    this.crop,
    this.fieldName,
    this.intervalS = 3,
    this.window = 0,
    this.scanned = 0,
    this.skipped = 0,
    this.latest,
    this.rolling = const LiveRollup(),
    this.stream,
    this.lastError,
  });

  factory LiveAnalysis.fromJson(Map<String, dynamic> json) => LiveAnalysis(
    cameraKey: json['camera_key']?.toString() ?? '',
    cameraName: json['camera_name']?.toString() ?? '',
    running: json['running'] == true,
    crop: _stringOrNull(json['crop']),
    fieldName: _stringOrNull(json['field_name']),
    intervalS: _double(json['interval_s']),
    window: _int(json['window']),
    scanned: _int(json['scanned']),
    skipped: _int(json['skipped']),
    latest: json['latest'] is Map
        ? LiveScan.fromJson(Map<String, dynamic>.from(json['latest'] as Map))
        : null,
    rolling: json['rolling'] is Map
        ? LiveRollup.fromJson(Map<String, dynamic>.from(json['rolling'] as Map))
        : const LiveRollup(),
    stream: json['stream'] is Map
        ? LiveStreamStatus.fromJson(
            Map<String, dynamic>.from(json['stream'] as Map),
          )
        : null,
    lastError: _stringOrNull(json['last_error']),
  );

  @override
  List<Object?> get props => [
    cameraKey,
    running,
    crop,
    fieldName,
    intervalS,
    window,
    scanned,
    skipped,
    latest,
    rolling,
    stream,
    lastError,
  ];
}

// ── json helpers ─────────────────────────────────────────────────────────

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

int _int(dynamic value) => _intOrNull(value) ?? 0;

int? _intOrNull(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

double _double(dynamic value) => _doubleOrNull(value) ?? 0;

double? _doubleOrNull(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

String? _stringOrNull(dynamic value) {
  final text = value?.toString().trim();
  return (text == null || text.isEmpty || text == 'null') ? null : text;
}
