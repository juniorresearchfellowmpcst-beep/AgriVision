import 'package:equatable/equatable.dart';

/// A camera hanging off the aircraft, as registered on the backend.
///
/// A multispectral rig is several of these — one row per band — because that
/// is how the sensors present themselves, and because the [band] is what lets
/// a shot be reassembled into the ordered stack the index maths needs.
class CameraFeed extends Equatable {
  final int id;
  final String name;

  /// `multispectral` | `rgb`
  final String role;

  /// blue | green | red | red_edge | nir. Null for an RGB camera.
  final String? band;

  final String url;

  /// Horizontal field of view. Without it a prescription can still be shown
  /// but cannot be turned into spray waypoints.
  final double? fovDeg;

  final bool enabled;

  const CameraFeed({
    required this.id,
    required this.name,
    required this.role,
    required this.band,
    required this.url,
    required this.fovDeg,
    required this.enabled,
  });

  bool get isMultispectral => role == 'multispectral';

  String get subtitle {
    final parts = <String>[
      if (band != null && band!.isNotEmpty) band!.replaceAll('_', ' '),
      if (fovDeg != null) '${fovDeg!.toStringAsFixed(0)}° FOV',
    ];
    return parts.isEmpty ? url : '${parts.join(' · ')} · $url';
  }

  factory CameraFeed.fromJson(Map<String, dynamic> json) => CameraFeed(
    id: _int(json['id']),
    name: json['name']?.toString() ?? 'Camera',
    role: json['role']?.toString() ?? 'rgb',
    band: (json['band']?.toString().isEmpty ?? true)
        ? null
        : json['band'].toString(),
    url: json['url']?.toString() ?? '',
    fovDeg: _doubleOrNull(json['fov_deg']),
    enabled: json['enabled'] != false,
  );

  @override
  List<Object?> get props => [id, name, role, band, url, fovDeg, enabled];
}

/// What the camera registry says the rig can currently do.
class CameraRegistry extends Equatable {
  final List<CameraFeed> cameras;
  final List<String> multispectralBands;

  /// A spray prescription needs at least a red + NIR pair to compute an index.
  final bool readyForMultispectral;
  final bool hasRgb;

  const CameraRegistry({
    this.cameras = const [],
    this.multispectralBands = const [],
    this.readyForMultispectral = false,
    this.hasRgb = false,
  });

  bool get isEmpty => cameras.isEmpty;

  factory CameraRegistry.fromJson(Map<String, dynamic> json) => CameraRegistry(
    cameras:
        (json['cameras'] as List?)
            ?.map((e) => CameraFeed.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        const [],
    multispectralBands:
        (json['multispectral_bands'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
    readyForMultispectral: json['ready_for_multispectral'] == true,
    hasRgb: json['has_rgb'] == true,
  );

  @override
  List<Object?> get props => [cameras, readyForMultispectral, hasRgb];
}

/// One stored still, with where the aircraft was when the shutter fired.
class CaptureFrameEntity extends Equatable {
  final int id;
  final String sessionId;
  final String shotId;
  final String role;
  final String? band;
  final String? previewUrl;
  final double? lat;
  final double? lon;
  final double? altM;
  final bool hasFix;

  const CaptureFrameEntity({
    required this.id,
    required this.sessionId,
    required this.shotId,
    required this.role,
    required this.band,
    required this.previewUrl,
    required this.lat,
    required this.lon,
    required this.altM,
    required this.hasFix,
  });

  String get label => band?.replaceAll('_', ' ').toUpperCase() ?? 'RGB';

  factory CaptureFrameEntity.fromJson(Map<String, dynamic> json) =>
      CaptureFrameEntity(
        id: _int(json['id']),
        sessionId: json['session_id']?.toString() ?? '',
        shotId: json['shot_id']?.toString() ?? '',
        role: json['role']?.toString() ?? 'rgb',
        band: (json['band']?.toString().isEmpty ?? true)
            ? null
            : json['band'].toString(),
        previewUrl: json['preview_url']?.toString(),
        lat: _doubleOrNull(json['lat']),
        lon: _doubleOrNull(json['lon']),
        altM: _doubleOrNull(json['alt_m']),
        hasFix: json['has_fix'] == true,
      );

  @override
  List<Object?> get props => [id, shotId, band, previewUrl];
}

/// One trigger of the shutter across every camera — the unit a prescription
/// is computed from.
class CaptureShot extends Equatable {
  final String sessionId;
  final String shotId;
  final List<CaptureFrameEntity> frames;
  final List<String> bands;

  /// True when the shot carries the red + NIR pair a prescription needs.
  final bool analysable;
  final bool hasFix;
  final DateTime? capturedAt;

  /// Per-camera failures. A dead band is reported, not silently dropped.
  final Map<String, String> errors;

  const CaptureShot({
    required this.sessionId,
    required this.shotId,
    this.frames = const [],
    this.bands = const [],
    this.analysable = false,
    this.hasFix = false,
    this.capturedAt,
    this.errors = const {},
  });

  List<CaptureFrameEntity> get rgbFrames =>
      frames.where((f) => f.role == 'rgb').toList();

  factory CaptureShot.fromJson(Map<String, dynamic> json) {
    final frames =
        (json['frames'] as List?)
            ?.map((e) => CaptureFrameEntity.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        const <CaptureFrameEntity>[];

    return CaptureShot(
      sessionId: json['session_id']?.toString() ?? '',
      shotId: json['shot_id']?.toString() ?? '',
      frames: frames,
      bands:
          (json['bands'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      analysable: json['analysable'] == true,
      hasFix: json['has_fix'] == true || frames.any((f) => f.hasFix),
      capturedAt: DateTime.tryParse(json['captured_at']?.toString() ?? ''),
      errors: (json['errors'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ) ??
          const {},
    );
  }

  @override
  List<Object?> get props => [shotId, bands, analysable, frames.length];
}

/// A flight / field visit's worth of captures.
class CaptureSession extends Equatable {
  final String sessionId;
  final int frames;
  final int shots;
  final String? fieldName;
  final DateTime? lastAt;

  const CaptureSession({
    required this.sessionId,
    required this.frames,
    required this.shots,
    this.fieldName,
    this.lastAt,
  });

  factory CaptureSession.fromJson(Map<String, dynamic> json) => CaptureSession(
    sessionId: json['session_id']?.toString() ?? '',
    frames: _int(json['frames']),
    shots: _int(json['shots']),
    fieldName: json['field_name']?.toString(),
    lastAt: DateTime.tryParse(json['last_at']?.toString() ?? ''),
  );

  @override
  List<Object?> get props => [sessionId, frames, shots];
}

/// Result of testing a camera URL before saving it.
class CameraProbe extends Equatable {
  final bool reachable;
  final String message;
  final int? width;
  final int? height;
  final int? latencyMs;

  const CameraProbe({
    required this.reachable,
    required this.message,
    this.width,
    this.height,
    this.latencyMs,
  });

  factory CameraProbe.fromJson(Map<String, dynamic> json) => CameraProbe(
    reachable: json['reachable'] == true,
    message: json['message']?.toString() ?? '',
    width: json['width'] == null ? null : _int(json['width']),
    height: json['height'] == null ? null : _int(json['height']),
    latencyMs: json['latency_ms'] == null ? null : _int(json['latency_ms']),
  );

  @override
  List<Object?> get props => [reachable, message, width, height];
}

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double? _doubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}
