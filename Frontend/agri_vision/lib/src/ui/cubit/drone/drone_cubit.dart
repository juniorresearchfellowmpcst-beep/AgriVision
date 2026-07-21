import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/data/drone/drone_service.dart';
import 'package:agri_vision/src/domain/entity/profile_entity.dart';

part 'drone_cubit_state.dart';

/// Live status of the paired drone / GCS unit, shown on Home, Profile and the
/// mission screens. Same lightweight pattern as [AnalysisCubit]: the cubit
/// owns a [DroneService] and emits immutable snapshots.
class DroneCubit extends Cubit<DroneState> {
  DroneCubit({DroneService? service})
    : _service = service ?? DroneService(),
      super(const DroneState());

  final DroneService _service;

  Future<void> load({bool refresh = false}) async {
    if (state.status == DroneStatus.loading) return;
    if (state.status == DroneStatus.success && !refresh) return;

    emit(state.copyWith(status: DroneStatus.loading, errorMessage: ''));
    try {
      final drone = await _service.fetchStatus();
      emit(state.copyWith(status: DroneStatus.success, drone: drone));
    } catch (e) {
      emit(
        state.copyWith(
          status: DroneStatus.failure,
          errorMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  /// Pair with a drone by serial number (used from Settings).
  Future<void> pair(String serialNumber) async {
    emit(state.copyWith(status: DroneStatus.loading, errorMessage: ''));
    try {
      final drone = await _service.pair(serialNumber: serialNumber);
      emit(state.copyWith(status: DroneStatus.success, drone: drone));
    } catch (e) {
      emit(
        state.copyWith(
          status: DroneStatus.failure,
          errorMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }
}
