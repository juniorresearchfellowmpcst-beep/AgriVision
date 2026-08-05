part of 'capture_cubit.dart';

enum CaptureStatus {
  initial,
  loading, // reading the camera registry
  ready,
  capturing, // shutter fired, waiting on the feeds
  failure,
}

class CaptureState extends Equatable {
  final CaptureStatus status;
  final CameraRegistry registry;

  /// The flight / field visit the shots below belong to. Null until the first
  /// shot, because the backend is what names a session.
  final String? sessionId;

  /// Block name stamped on every frame, so history is searchable later.
  final String fieldName;

  final CaptureShot? lastShot;
  final List<CaptureShot> shots;

  final bool loaded;
  final String errorMessage;

  const CaptureState({
    this.status = CaptureStatus.initial,
    this.registry = const CameraRegistry(),
    this.sessionId,
    this.fieldName = '',
    this.lastShot,
    this.shots = const [],
    this.loaded = false,
    this.errorMessage = '',
  });

  bool get isBusy => status == CaptureStatus.loading;
  bool get isCapturing => status == CaptureStatus.capturing;
  bool get hasCameras => registry.cameras.isNotEmpty;

  /// A prescription needs a red + NIR pair; say so before the operator flies.
  bool get canPrescribe => registry.readyForMultispectral;

  /// The most recent shot that can actually be clustered.
  CaptureShot? get analysableShot {
    for (final shot in [if (lastShot != null) lastShot!, ...shots]) {
      if (shot.analysable) return shot;
    }
    return null;
  }

  int get rgbShotCount => shots.where((s) => s.rgbFrames.isNotEmpty).length;

  CaptureState copyWith({
    CaptureStatus? status,
    CameraRegistry? registry,
    String? sessionId,
    String? fieldName,
    CaptureShot? lastShot,
    List<CaptureShot>? shots,
    bool? loaded,
    String? errorMessage,
    bool clearSession = false,
    bool clearLastShot = false,
  }) {
    return CaptureState(
      status: status ?? this.status,
      registry: registry ?? this.registry,
      sessionId: clearSession ? null : (sessionId ?? this.sessionId),
      fieldName: fieldName ?? this.fieldName,
      lastShot: clearLastShot ? null : (lastShot ?? this.lastShot),
      shots: shots ?? this.shots,
      loaded: loaded ?? this.loaded,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status,
    registry,
    sessionId,
    fieldName,
    lastShot,
    shots,
    loaded,
    errorMessage,
  ];
}
