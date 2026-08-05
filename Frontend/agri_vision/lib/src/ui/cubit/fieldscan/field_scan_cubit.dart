import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/core/utils/plant_photo_picker.dart';
import 'package:agri_vision/src/data/fieldscan/field_scan_service.dart';
import 'package:agri_vision/src/domain/entity/field_scan_result.dart';
import 'package:agri_vision/src/domain/entity/media_file.dart';

part 'field_scan_cubit_state.dart';

/// Drives the weed + disease field scan.
///
/// Two modes, and the difference matters agronomically:
///
///   [scanPhoto]   — one frame. Quick "what is this?", but one frame is an
///                   anecdote.
///   [scanSession] — every RGB frame a low-pace pass recorded, rolled up into
///                   a field-level answer with hotspot coordinates.
///
/// The crop is part of the diagnosis, not decoration: the same yellowing means
/// yellow rust in wheat and yellow mosaic in soybean, so [selectCrop] is asked
/// for before a scan rather than after.
class FieldScanCubit extends Cubit<FieldScanState> {
  FieldScanCubit({FieldScanService? service})
    : _service = service ?? FieldScanService(),
      super(const FieldScanState());

  final FieldScanService _service;

  Future<void> load({bool refresh = false}) async {
    if (state.crops.isNotEmpty && !refresh) return;
    try {
      final crops = await _service.fetchCrops();
      final engines = await _service.fetchEngines();
      if (isClosed) return;
      emit(state.copyWith(crops: crops, engines: engines));
    } catch (e) {
      emit(state.copyWith(errorMessage: _clean(e)));
    }
  }

  void selectCrop(String? cropId) => emit(
    state.copyWith(selectedCrop: cropId, clearCrop: cropId == null),
  );

  void setFieldName(String value) => emit(state.copyWith(fieldName: value));

  // ── one frame ───────────────────────────────────────────────────────────

  Future<void> captureAndScan() => _pickThen(PlantPhotoPicker.capture);

  Future<void> pickAndScan() => _pickThen(PlantPhotoPicker.fromGallery);

  Future<void> _pickThen(Future<MediaFile?> Function() pick) async {
    MediaFile? image;
    try {
      image = await pick();
    } catch (e) {
      emit(
        state.copyWith(
          status: FieldScanStatus.failure,
          errorMessage:
              'Could not open the camera/gallery. Check app permissions.\n$e',
        ),
      );
      return;
    }
    if (image == null) return; // cancelled — keep the current state

    emit(
      state.copyWith(
        status: FieldScanStatus.scanning,
        image: image,
        errorMessage: '',
        clearResult: true,
        clearSummary: true,
      ),
    );

    try {
      final result = await _service.analyze(
        image,
        crop: state.selectedCrop,
        fieldName: state.fieldName,
      );
      if (!result.isOk) {
        emit(
          state.copyWith(
            status: FieldScanStatus.failure,
            errorMessage: 'Could not scan that frame.',
          ),
        );
        return;
      }
      emit(state.copyWith(status: FieldScanStatus.success, result: result));
    } catch (e) {
      emit(
        state.copyWith(status: FieldScanStatus.failure, errorMessage: _clean(e)),
      );
    }
  }

  // ── a whole low-pace pass ───────────────────────────────────────────────

  Future<void> scanSession(String sessionId) async {
    emit(
      state.copyWith(
        status: FieldScanStatus.scanning,
        sessionId: sessionId,
        errorMessage: '',
        clearResult: true,
        clearSummary: true,
        clearImage: true,
      ),
    );

    try {
      final scan = await _service.scanSession(
        sessionId: sessionId,
        crop: state.selectedCrop,
      );
      emit(
        state.copyWith(
          status: FieldScanStatus.success,
          summary: scan.summary,
          frames: scan.frames,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(status: FieldScanStatus.failure, errorMessage: _clean(e)),
      );
    }
  }

  void reset() => emit(
    FieldScanState(
      crops: state.crops,
      engines: state.engines,
      selectedCrop: state.selectedCrop,
      fieldName: state.fieldName,
    ),
  );

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');
}
