part of 'disease_cubit.dart';

enum DiseaseStatus {
  initial, // nothing captured yet
  analyzing, // photo taken, request in flight
  success, // result available
  failure, // something went wrong
}

class DiseaseState extends Equatable {
  final DiseaseStatus status;

  /// The photo currently being analysed / last analysed (shown as a preview).
  final MediaFile? image;
  final DiseaseResult? result;
  final String errorMessage;

  /// Past scans from the backend, newest first.
  final List<DiseaseScanEntity> scans;

  final bool historyLoading;

  /// Set when the shown result was re-opened from history rather than just
  /// scanned — the page has no photo bytes for those, so it must not claim to.
  final bool resultFromHistory;

  const DiseaseState({
    this.status = DiseaseStatus.initial,
    this.image,
    this.result,
    this.errorMessage = '',
    this.scans = const [],
    this.historyLoading = false,
    this.resultFromHistory = false,
  });

  bool get isBusy => status == DiseaseStatus.analyzing;
  bool get hasResult => status == DiseaseStatus.success && result != null;
  bool get hasImage => image != null;
  bool get hasHistory => scans.isNotEmpty;

  DiseaseState copyWith({
    DiseaseStatus? status,
    MediaFile? image,
    DiseaseResult? result,
    String? errorMessage,
    List<DiseaseScanEntity>? scans,
    bool? historyLoading,
    bool? resultFromHistory,
    bool clearResult = false,
    bool clearImage = false,
  }) {
    return DiseaseState(
      status: status ?? this.status,
      image: clearImage ? null : (image ?? this.image),
      result: clearResult ? null : (result ?? this.result),
      errorMessage: errorMessage ?? this.errorMessage,
      scans: scans ?? this.scans,
      historyLoading: historyLoading ?? this.historyLoading,
      resultFromHistory: resultFromHistory ?? this.resultFromHistory,
    );
  }

  @override
  List<Object?> get props => [
    status,
    image,
    result,
    errorMessage,
    scans,
    historyLoading,
    resultFromHistory,
  ];
}
