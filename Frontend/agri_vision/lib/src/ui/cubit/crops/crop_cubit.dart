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
///
/// **Always a disease scan.** The phone path used to offer disease / weed /
/// both. Weed pressure is a measurement over ground — what share of a *field*
/// is weedy — and one close-up photo cannot answer it honestly; the number it
/// produced described the patch the farmer happened to be standing over. Weed
/// detection lives on the drone, which can see the whole block. Asking the
/// farmer to choose up front was also asking them to answer the question they
/// opened the camera to have answered.
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
      // catalog.weeds is deliberately dropped: the picker shows crops only.
      emit(
        state.copyWith(
          status: CropStatus.ready,
          crops: catalog.crops,
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
      ),
    );
    try {
      final detail = await _service.fetchCrop(cropId);
      if (isClosed) return;
      emit(state.copyWith(status: CropStatus.ready, detail: detail));
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(status: CropStatus.failure, errorMessage: _clean(e)),
      );
    }
  }

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
        crop: state.selectedCrop,
        // Disease, always — see the class doc. The backend still accepts the
        // other modes; the drone uses them.
        mode: ScanMode.disease,
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
