part of 'crop_cubit.dart';

enum CropStatus { initial, loading, ready, scanning, scanned, failure }

class CropState extends Equatable {
  final CropStatus status;

  /// The picker grid. Crops only — weed work belongs to the drone, which can
  /// see a whole block, so there is no weeds tile here any more.
  final List<CropCatalogItem> crops;

  final String? selectedCrop;
  final CropDetail? detail;

  final String fieldName;

  final MediaFile? image;
  final CropScanResult? result;

  final String errorMessage;

  const CropState({
    this.status = CropStatus.initial,
    this.crops = const [],
    this.selectedCrop,
    this.detail,
    this.fieldName = '',
    this.image,
    this.result,
    this.errorMessage = '',
  });

  bool get isBusy =>
      status == CropStatus.loading || status == CropStatus.scanning;
  bool get isScanning => status == CropStatus.scanning;
  bool get hasResult => result != null;

  CropCatalogItem? get selected {
    for (final crop in crops) {
      if (crop.id == selectedCrop) return crop;
    }
    return null;
  }

  CropState copyWith({
    CropStatus? status,
    List<CropCatalogItem>? crops,
    String? selectedCrop,
    CropDetail? detail,
    String? fieldName,
    MediaFile? image,
    CropScanResult? result,
    String? errorMessage,
    bool clearCrop = false,
    bool clearDetail = false,
    bool clearResult = false,
  }) {
    return CropState(
      status: status ?? this.status,
      crops: crops ?? this.crops,
      selectedCrop: clearCrop ? null : (selectedCrop ?? this.selectedCrop),
      detail: clearDetail ? null : (detail ?? this.detail),
      fieldName: fieldName ?? this.fieldName,
      image: clearResult ? null : (image ?? this.image),
      result: clearResult ? null : (result ?? this.result),
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status,
    crops,
    selectedCrop,
    detail,
    fieldName,
    image,
    result,
    errorMessage,
  ];
}
