part of 'analysis_cubit.dart';

enum AnalysisStatus {
  initial, // nothing selected yet
  ready, // images selected, ready to analyze
  uploading, // request in flight
  success, // result available
  failure, // something went wrong
}

/// Canonical band keys in the order the backend expects them.
const List<String> kBands = ['blue', 'green', 'red', 'red_edge', 'nir'];

class AnalysisState extends Equatable {
  final AnalysisStatus status;
  final List<MediaFile> images;
  final List<MediaFile> panelImages;

  /// Which band each picked image is assigned to: `fileName -> band key`.
  /// Empty entries mean "let the backend auto-detect from the filename".
  final Map<String, String> fileBand;

  final bool calibrate;
  final AnalysisResult? result;
  final String errorMessage;

  const AnalysisState({
    this.status = AnalysisStatus.initial,
    this.images = const [],
    this.panelImages = const [],
    this.fileBand = const {},
    this.calibrate = false,
    this.result,
    this.errorMessage = '',
  });

  bool get isBusy => status == AnalysisStatus.uploading;
  bool get hasResult => status == AnalysisStatus.success && result != null;
  bool get canAnalyze => images.isNotEmpty && !isBusy;

  /// band key -> fileName, inverted from [fileBand] for the API `band_map`.
  Map<String, String> get bandMap {
    final map = <String, String>{};
    fileBand.forEach((file, band) => map[band] = file);
    return map;
  }

  /// True once every picked image has a band assigned (a clean 1:1 mapping).
  bool get allBandsAssigned =>
      images.isNotEmpty &&
      images.every((f) => fileBand[f.name] != null);

  AnalysisState copyWith({
    AnalysisStatus? status,
    List<MediaFile>? images,
    List<MediaFile>? panelImages,
    Map<String, String>? fileBand,
    bool? calibrate,
    AnalysisResult? result,
    String? errorMessage,
  }) {
    return AnalysisState(
      status: status ?? this.status,
      images: images ?? this.images,
      panelImages: panelImages ?? this.panelImages,
      fileBand: fileBand ?? this.fileBand,
      calibrate: calibrate ?? this.calibrate,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status,
    images,
    panelImages,
    fileBand,
    calibrate,
    result,
    errorMessage,
  ];
}
