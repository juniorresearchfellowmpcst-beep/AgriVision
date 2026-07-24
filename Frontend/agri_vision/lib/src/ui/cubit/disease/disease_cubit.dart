import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/core/utils/plant_photo_picker.dart';
import 'package:agri_vision/src/data/disease/disease_service.dart';
import 'package:agri_vision/src/domain/entity/disease_result.dart';
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
  Future<void> captureAndIdentify() => _pickThen(PlantPhotoPicker.capture);

  /// Pick a photo from the gallery, then identify it.
  Future<void> pickAndIdentify() => _pickThen(PlantPhotoPicker.fromGallery);

  Future<void> _pickThen(Future<MediaFile?> Function() pick) async {
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
        errorMessage: '',
      ),
    );

    try {
      final result = await _service.identify(image);
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
    } catch (e) {
      emit(
        state.copyWith(
          status: DiseaseStatus.failure,
          errorMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  /// Clear everything and start over.
  void reset() => emit(const DiseaseState());
}
