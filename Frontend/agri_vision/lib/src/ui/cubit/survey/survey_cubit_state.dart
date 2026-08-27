part of 'survey_cubit.dart';

enum SurveyStatus {
  initial,
  loading,
  ready,        // camera modes read; nothing flying
  starting,
  flying,
  summarising,
  summarised,
  authorising,
  spraying,
  failure,
}

class SurveyState extends Equatable {
  final SurveyStatus status;

  /// What the rig can fly, and whether the advisor is configured.
  final SurveyCapabilities capabilities;

  // ── the setup form ──────────────────────────────────────────────────────
  final CameraMode cameraMode;

  /// Whether the operator has picked a mode themselves. Without this, a later
  /// capabilities refresh would silently overwrite their choice with the
  /// default every time the screen reloaded.
  final bool cameraModeTouched;

  final DetectionTarget target;
  final String? crop;
  final String fieldName;

  // ── the flight ──────────────────────────────────────────────────────────
  final SurveyRun? run;
  final SurveyProgress progress;
  final List<String> warnings;
  final bool isShooting;
  final String? lastShotMessage;

  /// A failed poll, kept apart from [errorMessage]: the aircraft is still
  /// flying and the server is still scanning, so this is a note on the screen
  /// rather than a reason to tear it down.
  final String pollError;

  // ── the answer ──────────────────────────────────────────────────────────
  final SurveySummary? summary;
  final List<SurveyRun> history;

  // ── the spray ───────────────────────────────────────────────────────────
  final bool tankFilled;
  final double? tankLitres;
  final String? tankProduct;
  final String? option;
  final String? sprayMessage;

  final String errorMessage;

  const SurveyState({
    this.status = SurveyStatus.initial,
    this.capabilities = SurveyCapabilities.unknown,
    this.cameraMode = CameraMode.ipCamera,
    this.cameraModeTouched = false,
    this.target = DetectionTarget.both,
    this.crop,
    this.fieldName = '',
    this.run,
    this.progress = SurveyProgress.none,
    this.warnings = const [],
    this.isShooting = false,
    this.lastShotMessage,
    this.pollError = '',
    this.summary,
    this.history = const [],
    this.tankFilled = false,
    this.tankLitres,
    this.tankProduct,
    this.option,
    this.sprayMessage,
    this.errorMessage = '',
  });

  bool get isBusy =>
      status == SurveyStatus.loading ||
      status == SurveyStatus.starting ||
      status == SurveyStatus.summarising ||
      status == SurveyStatus.authorising;

  bool get isFlying => run?.isFlying == true;
  bool get hasSummary => summary != null;

  /// Whether the spray step should be offered at all. Three separate ways for
  /// a flight to be pointless: nothing worth spraying, nowhere to spray it, or
  /// no prescription to hand the aircraft.
  bool get canOfferSpray => summary?.canOfferSpray == true;

  /// The option the operator has chosen, falling back to the recommendation.
  String? get effectiveOption =>
      option ?? summary?.treatmentMap?.recommendedOption?.id;

  SurveyState copyWith({
    SurveyStatus? status,
    SurveyCapabilities? capabilities,
    CameraMode? cameraMode,
    bool? cameraModeTouched,
    DetectionTarget? target,
    String? crop,
    String? fieldName,
    SurveyRun? run,
    SurveyProgress? progress,
    List<String>? warnings,
    bool? isShooting,
    String? lastShotMessage,
    String? pollError,
    SurveySummary? summary,
    List<SurveyRun>? history,
    bool? tankFilled,
    double? tankLitres,
    String? tankProduct,
    String? option,
    String? sprayMessage,
    String? errorMessage,
    bool clearCrop = false,
    bool clearSummary = false,
    bool clearTank = false,
  }) {
    return SurveyState(
      status: status ?? this.status,
      capabilities: capabilities ?? this.capabilities,
      cameraMode: cameraMode ?? this.cameraMode,
      cameraModeTouched: cameraModeTouched ?? this.cameraModeTouched,
      target: target ?? this.target,
      crop: clearCrop ? null : (crop ?? this.crop),
      fieldName: fieldName ?? this.fieldName,
      run: run ?? this.run,
      progress: progress ?? this.progress,
      warnings: warnings ?? this.warnings,
      isShooting: isShooting ?? this.isShooting,
      lastShotMessage: lastShotMessage ?? this.lastShotMessage,
      // Cleared on every successful emit that does not set it: a stale poll
      // error left on screen after the link comes back is a lie.
      pollError: pollError ?? '',
      summary: clearSummary ? null : (summary ?? this.summary),
      history: history ?? this.history,
      tankFilled: clearTank ? false : (tankFilled ?? this.tankFilled),
      tankLitres: clearTank ? null : (tankLitres ?? this.tankLitres),
      tankProduct: clearTank ? null : (tankProduct ?? this.tankProduct),
      option: option ?? this.option,
      sprayMessage: sprayMessage ?? this.sprayMessage,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status,
    capabilities,
    cameraMode,
    cameraModeTouched,
    target,
    crop,
    fieldName,
    run,
    progress,
    warnings,
    isShooting,
    lastShotMessage,
    pollError,
    summary,
    history,
    tankFilled,
    tankLitres,
    tankProduct,
    option,
    sprayMessage,
    errorMessage,
  ];
}
