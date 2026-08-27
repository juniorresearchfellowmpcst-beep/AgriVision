import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/core/utils/plant_photo_picker.dart';
import 'package:agri_vision/src/data/crops/crop_catalog_service.dart';
import 'package:agri_vision/src/domain/entity/crop_catalog.dart';
import 'package:agri_vision/src/domain/entity/media_file.dart';

part 'crop_cubit_state.dart';

/// Drives the crop picker and the phone-camera scan.
///
/// This is the drone-free half of the app, and it is deliberately short: pick
/// a crop, point the phone, read the answer. No flight, no session, no
/// prescription — a photo of one plant cannot say where in the block the
/// problem is, and the result screen says so rather than offering a spray run
/// it cannot honestly plan.
class CropCubit extends Cubit<CropState> {
  CropCubit({CropCatalogService? service})
    : _service = service ?? CropCatalogService(),
      super(const CropState());

  final CropCatalogService _service;

  // ── the picker ──────────────────────────────────────────────────────────

  Future<void> load({bool refresh = false}) async {
    if (state.crops.isNotEmpty && !refresh) return;

    emit(state.copyWith(status: CropStatus.loading, errorMessage: ''));
    try {
      // The current month is passed so the picker marks and sorts by what is
      // actually in the ground — in August a farmer here is looking at soybean
      // and paddy, not wheat.
      final catalog = await _service.fetchCatalog(month: DateTime.now().month);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: CropStatus.ready,
          crops: catalog.crops,
          weedsOption: catalog.weeds,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(status: CropStatus.failure, errorMessage: _clean(e)),
      );
    }
  }

  /// Open one crop from the grid.
  Future<void> openCrop(String cropId) async {
    emit(
      state.copyWith(
        status: CropStatus.loading,
        selectedCrop: cropId,
        clearDetail: true,
        clearResult: true,
        errorMessage: '',
        // Selecting the Weeds tile *is* choosing what to look for.
        mode: cropId == 'weeds' ? ScanMode.weed : state.mode,
      ),
    );
    try {
      final detail = cropId == 'weeds'
          ? await _service.fetchWeeds()
          : await _service.fetchCrop(cropId);
      if (isClosed) return;
      emit(state.copyWith(status: CropStatus.ready, detail: detail));
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(status: CropStatus.failure, errorMessage: _clean(e)),
      );
    }
  }

  /// Narrow the weed list to one crop's usual suspects.
  ///
  /// Worth doing even after the Weeds tile was tapped: without a crop the app
  /// can measure weed pressure but cannot name a herbicide, because the same
  /// product that clears wheat kills soybean.
  Future<void> narrowWeedsTo(String? cropId) async {
    emit(state.copyWith(weedCrop: cropId, clearWeedCrop: cropId == null));
    try {
      final detail = await _service.fetchWeeds(cropId: cropId);
      if (isClosed) return;
      emit(state.copyWith(detail: detail));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(errorMessage: _clean(e)));
    }
  }

  void selectMode(ScanMode mode) => emit(state.copyWith(mode: mode));

  void setFieldName(String value) => emit(state.copyWith(fieldName: value));

  void clearSelection() => emit(
    state.copyWith(
      clearCrop: true,
      clearDetail: true,
      clearResult: true,
      errorMessage: '',
    ),
  );

  // ── the scan ────────────────────────────────────────────────────────────

  Future<void> captureAndScan() => _pickThen(PlantPhotoPicker.capture);

  Future<void> pickAndScan() => _pickThen(PlantPhotoPicker.fromGallery);

  Future<void> _pickThen(Future<MediaFile?> Function() pick) async {
    MediaFile? image;
    try {
      image = await pick();
    } catch (e) {
      emit(
        state.copyWith(
          status: CropStatus.failure,
          errorMessage:
              'Could not open the camera or gallery. Check the app\'s '
              'permissions in Settings.\n$e',
        ),
      );
      return;
    }
    if (image == null) return; // cancelled — leave the screen as it was

    emit(
      state.copyWith(
        status: CropStatus.scanning,
        image: image,
        clearResult: true,
        errorMessage: '',
      ),
    );

    try {
      final result = await _service.scan(
        image,
        // The Weeds tile is not a crop. Selecting it means "look for weeds",
        // and the crop stays whatever the farmer narrowed the list to.
        crop: state.selectedCrop == 'weeds' ? state.weedCrop : state.selectedCrop,
        mode: state.mode,
        fieldName: state.fieldName,
      );
      if (isClosed) return;
      emit(state.copyWith(status: CropStatus.scanned, result: result));
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(status: CropStatus.failure, errorMessage: _clean(e)),
      );
    }
  }

  void clearResult() => emit(
    state.copyWith(status: CropStatus.ready, clearResult: true, errorMessage: ''),
  );

  String _clean(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}
