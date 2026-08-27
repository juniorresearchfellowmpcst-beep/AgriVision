part of 'live_feed_cubit.dart';

enum LiveFeedStatus {
  initial,
  loading,
  ready,

  /// The backend has the camera registry but no relay — an older server.
  unsupported,
}

class LiveFeedState extends Equatable {
  final LiveFeedStatus status;

  /// Null until a camera has been chosen; the video widget is not built
  /// before then, so there is no socket to a camera nobody picked.
  final int? cameraId;
  final String cameraName;

  /// Null when nothing is scanning this feed — which is the normal state on
  /// first open, not an error.
  final LiveAnalysis? analysis;

  /// The start request is in flight. Separate from [status] so the video
  /// keeps playing while the scan spins up.
  final bool starting;

  final bool loaded;
  final String errorMessage;

  const LiveFeedState({
    this.status = LiveFeedStatus.initial,
    this.cameraId,
    this.cameraName = '',
    this.analysis,
    this.starting = false,
    this.loaded = false,
    this.errorMessage = '',
  });

  bool get isBusy => status == LiveFeedStatus.loading;
  bool get isAnalysing => analysis?.running == true;
  bool get canStream => status == LiveFeedStatus.ready && cameraId != null;

  LiveScan? get latest => analysis?.latest;
  LiveRollup get rolling => analysis?.rolling ?? const LiveRollup();

  /// What the *server* says about the camera, as opposed to what the video
  /// widget's own socket is doing.
  LiveStreamStatus? get stream => analysis?.stream;

  /// True once enough of the window is real scans to be worth reading as a
  /// field-level claim rather than a first impression.
  bool get rollupIsMeaningful => rolling.frames >= 3;

  LiveFeedState copyWith({
    LiveFeedStatus? status,
    int? cameraId,
    String? cameraName,
    LiveAnalysis? analysis,
    bool? starting,
    bool? loaded,
    String? errorMessage,
    bool clearAnalysis = false,
  }) {
    return LiveFeedState(
      status: status ?? this.status,
      cameraId: cameraId ?? this.cameraId,
      cameraName: cameraName ?? this.cameraName,
      analysis: clearAnalysis ? null : (analysis ?? this.analysis),
      starting: starting ?? this.starting,
      loaded: loaded ?? this.loaded,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status,
    cameraId,
    cameraName,
    analysis,
    starting,
    loaded,
    errorMessage,
  ];
}
