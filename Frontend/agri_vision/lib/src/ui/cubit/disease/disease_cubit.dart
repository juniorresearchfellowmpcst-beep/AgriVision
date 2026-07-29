import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/core/utils/plant_photo_picker.dart';
import 'package:agri_vision/src/data/disease/disease_service.dart';
import 'package:agri_vision/src/domain/entity/disease_result.dart';
import 'package:agri_vision/src/domain/entity/disease_scan_entity.dart';
import 'package:agri_vision/src/domain/entity/media_file.dart';

part 'disease_cubit_state.dart';

/// Drives the "scan a plant for disease" flow: take/pick a photo → upload →
/// show the identified condition + treatment solution.
///
/// Follows the same lightweight, page-scoped pattern as [AnalysisCubit]: the
/// cubit owns a [DiseaseService] and emits immutable [DiseaseState] snapshots,
/// so the UI is a pure function of state across mobile / web.
class DiseaseCubit extends Cubit<DiseaseState> {
  DiseaseCubit({DiseaseService? service})
    : _service = service ?? DiseaseService(),
      super(const DiseaseState());

  final DiseaseService _service;

  /// Take a photo with the camera, then identify it.
  Future<void> captureAndIdentify({String? fieldName}) =>
      _pickThen(PlantPhotoPicker.capture, fieldName: fieldName);

  /// Pick a photo from the gallery, then identify it.
  Future<void> pickAndIdentify({String? fieldName}) =>
      _pickThen(PlantPhotoPicker.fromGallery, fieldName: fieldName);

  Future<void> _pickThen(
    Future<MediaFile?> Function() pick, {
    String? fieldName,
  }) async {
    MediaFile? image;
    try {
      image = await pick();
    } catch (e) {
      emit(
        state.copyWith(
          status: DiseaseStatus.failure,
          errorMessage:
              'Could not open the camera/gallery. Check app permissions.\n$e',
        ),
      );
      return;
    }

    if (image == null) return; // user cancelled — keep current state

    emit(
      state.copyWith(
        status: DiseaseStatus.analyzing,
        image: image,
        clearResult: true,
        resultFromHistory: false,
        errorMessage: '',
      ),
    );

    try {
      final result = await _service.identify(image, fieldName: fieldName);
      if (!result.isOk) {
        emit(
          state.copyWith(
            status: DiseaseStatus.failure,
            errorMessage: result.message.isNotEmpty
                ? result.message
                : 'Could not identify the plant condition.',
          ),
        );
        return;
      }
      emit(state.copyWith(status: DiseaseStatus.success, result: result));
      // The scan was just recorded server-side — pull it into the list.
      await loadHistory(refresh: true);
    } catch (e) {
      emit(
        state.copyWith(
          status: DiseaseStatus.failure,
          errorMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  // ── History ─────────────────────────────────────────────────────────────

  /// Past scans. A history failure is silent: it must not bury the diagnosis
  /// the operator is actually looking at behind a network error.
  Future<void> loadHistory({bool refresh = false}) async {
    if (state.historyLoading) return;
    if (state.hasHistory && !refresh) return;

    emit(state.copyWith(historyLoading: true));
    try {
      final scans = await _service.fetchScans();
      emit(state.copyWith(scans: scans, historyLoading: false));
    } catch (_) {
      emit(state.copyWith(historyLoading: false));
    }
  }

  /// Re-open a past scan's full diagnosis.
  Future<void> openScan(int scanId) async {
    emit(
      state.copyWith(
        status: DiseaseStatus.analyzing,
        clearResult: true,
        clearImage: true,
        errorMessage: '',
      ),
    );
    try {
      final result = await _service.fetchScan(scanId);
      emit(
        state.copyWith(
          status: DiseaseStatus.success,
          result: result,
          resultFromHistory: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: DiseaseStatus.failure,
          errorMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  /// Clear the current scan and start over, keeping the loaded history.
  void reset() => emit(
    DiseaseState(scans: state.scans),
  );
}
