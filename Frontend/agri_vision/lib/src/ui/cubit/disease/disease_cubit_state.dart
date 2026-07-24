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

  const DiseaseState({
    this.status = DiseaseStatus.initial,
    this.image,
    this.result,
    this.errorMessage = '',
  });

  bool get isBusy => status == DiseaseStatus.analyzing;
  bool get hasResult => status == DiseaseStatus.success && result != null;
  bool get hasImage => image != null;

  DiseaseState copyWith({
    DiseaseStatus? status,
    MediaFile? image,
    DiseaseResult? result,
    String? errorMessage,
    bool clearResult = false,
  }) {
    return DiseaseState(
      status: status ?? this.status,
      image: image ?? this.image,
      result: clearResult ? null : (result ?? this.result),
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, image, result, errorMessage];
}
