part of 'field_scan_cubit.dart';

enum FieldScanStatus { initial, scanning, success, failure }

class FieldScanState extends Equatable {
  final FieldScanStatus status;

  final List<CropOption> crops;
  final String? selectedCrop;
  final String fieldName;

  /// Which engine answers each half — `model` once a trained CNN is
  /// configured server-side, `heuristic` otherwise.
  final Map<String, String> engines;

  /// Single-frame mode.
  final MediaFile? image;
  final FieldScanResult? result;

  /// Whole-pass mode.
  final String? sessionId;
  final FieldScanSummary? summary;
  final List<FieldScanResult> frames;

  final String errorMessage;

  const FieldScanState({
    this.status = FieldScanStatus.initial,
    this.crops = const [],
    this.selectedCrop,
    this.fieldName = '',
    this.engines = const {},
    this.image,
    this.result,
    this.sessionId,
    this.summary,
    this.frames = const [],
    this.errorMessage = '',
  });

  bool get isBusy => status == FieldScanStatus.scanning;
  bool get hasResult => result != null;
  bool get hasSummary => summary != null;
  bool get usesTrainedModel =>
      engines['disease'] == 'model' || engines['weed'] == 'model';

  CropOption? get crop {
    for (final option in crops) {
      if (option.id == selectedCrop) return option;
    }
    return null;
  }

  FieldScanState copyWith({
    FieldScanStatus? status,
    List<CropOption>? crops,
    String? selectedCrop,
    String? fieldName,
    Map<String, String>? engines,
    MediaFile? image,
    FieldScanResult? result,
    String? sessionId,
    FieldScanSummary? summary,
    List<FieldScanResult>? frames,
    String? errorMessage,
    bool clearCrop = false,
    bool clearImage = false,
    bool clearResult = false,
    bool clearSummary = false,
  }) {
    return FieldScanState(
      status: status ?? this.status,
      crops: crops ?? this.crops,
      selectedCrop: clearCrop ? null : (selectedCrop ?? this.selectedCrop),
      fieldName: fieldName ?? this.fieldName,
      engines: engines ?? this.engines,
      image: clearImage ? null : (image ?? this.image),
      result: clearResult ? null : (result ?? this.result),
      sessionId: sessionId ?? this.sessionId,
      summary: clearSummary ? null : (summary ?? this.summary),
      frames: clearSummary ? const [] : (frames ?? this.frames),
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status,
    crops,
    selectedCrop,
    fieldName,
    engines,
    image,
    result,
    sessionId,
    summary,
    frames,
    errorMessage,
  ];
}
