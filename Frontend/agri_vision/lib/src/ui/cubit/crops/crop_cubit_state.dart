part of 'crop_cubit.dart';

enum CropStatus { initial, loading, ready, scanning, scanned, failure }

class CropState extends Equatable {
  final CropStatus status;

  /// The picker grid.
  final List<CropCatalogItem> crops;

  /// The Weeds tile. Kept apart from [crops] so nothing iterating crops to run
  /// a disease model is ever handed a non-crop.
  final CropCatalogItem? weedsOption;

  final String? selectedCrop;

  /// When the Weeds tile is open, which crop the list is narrowed to. Without
  /// one the app can measure weed pressure but cannot name a herbicide.
  final String? weedCrop;

  final CropDetail? detail;
  final ScanMode mode;
  final String fieldName;

  final MediaFile? image;
  final CropScanResult? result;

  final String errorMessage;

  const CropState({
    this.status = CropStatus.initial,
    this.crops = const [],
    this.weedsOption,
    this.selectedCrop,
    this.weedCrop,
    this.detail,
    this.mode = ScanMode.both,
    this.fieldName = '',
    this.image,
    this.result,
    this.errorMessage = '',
  });

  bool get isBusy =>
      status == CropStatus.loading || status == CropStatus.scanning;
  bool get isScanning => status == CropStatus.scanning;
  bool get hasResult => result != null;
  bool get isWeedsSelected => selectedCrop == 'weeds';

  /// Every tile in the grid, weeds last — a farmer opens the picker looking
  /// for their crop, and the weed option is the one they reach for second.
  List<CropCatalogItem> get tiles => [
    ...crops,
    if (weedsOption != null) weedsOption!,
  ];

  CropCatalogItem? get selected {
    for (final crop in tiles) {
      if (crop.id == selectedCrop) return crop;
    }
    return null;
  }

  CropState copyWith({
    CropStatus? status,
    List<CropCatalogItem>? crops,
    CropCatalogItem? weedsOption,
    String? selectedCrop,
    String? weedCrop,
    CropDetail? detail,
    ScanMode? mode,
    String? fieldName,
    MediaFile? image,
    CropScanResult? result,
    String? errorMessage,
    bool clearCrop = false,
    bool clearWeedCrop = false,
    bool clearDetail = false,
    bool clearResult = false,
  }) {
    return CropState(
      status: status ?? this.status,
      crops: crops ?? this.crops,
      weedsOption: weedsOption ?? this.weedsOption,
      selectedCrop: clearCrop ? null : (selectedCrop ?? this.selectedCrop),
      weedCrop: clearWeedCrop ? null : (weedCrop ?? this.weedCrop),
      detail: clearDetail ? null : (detail ?? this.detail),
      mode: mode ?? this.mode,
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
    weedsOption,
    selectedCrop,
    weedCrop,
    detail,
    mode,
    fieldName,
    image,
    result,
    errorMessage,
  ];
}
