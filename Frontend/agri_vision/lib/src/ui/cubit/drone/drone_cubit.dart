import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/data/drone/drone_service.dart';
import 'package:agri_vision/src/domain/entity/profile_entity.dart';

part 'drone_cubit_state.dart';

/// Live status of the paired drone / GCS unit, shown on Home, Profile and the
/// mission screens. Same lightweight pattern as [AnalysisCubit]: the cubit
/// owns a [DroneService] and emits immutable snapshots.
///
/// A null [DroneState.drone] is meaningful — no aircraft is paired — and is
/// emitted as such so screens show the connect flow rather than filler.
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
      emit(
        state.copyWith(
          status: DroneStatus.success,
          drone: drone,
          clearDrone: drone == null,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: DroneStatus.failure,
          errorMessage: _clean(e),
        ),
      );
    }
  }

  /// Pair with a drone by serial number (used from the connect sheet).
  /// A serial the server hasn't seen registers that aircraft under [name].
  ///
  /// The server's own wording is kept in [DroneState.lastMessage] — it is the
  /// only thing that distinguishes "paired with your aircraft" from "created a
  /// new one because that serial was unknown", and the operator needs to see
  /// which happened.
  Future<void> pair(String serialNumber, {String? name, String? model}) async {
    emit(state.copyWith(status: DroneStatus.loading, errorMessage: ''));
    try {
      final (drone, message, registered) = await _service.pair(
        serialNumber: serialNumber,
        name: name,
        model: model,
      );
      emit(
        state.copyWith(
          status: DroneStatus.success,
          drone: drone,
          lastMessage: message,
          registeredNewDrone: registered,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(status: DroneStatus.failure, errorMessage: _clean(e)),
      );
    }
  }

  /// Release the paired aircraft. The state goes back to "nothing paired",
  /// which is what the screens key their empty state off.
  Future<void> unpair() async {
    emit(state.copyWith(status: DroneStatus.loading, errorMessage: ''));
    try {
      await _service.unpair();
      emit(
        state.copyWith(status: DroneStatus.success, clearDrone: true),
      );
    } catch (e) {
      emit(
        state.copyWith(status: DroneStatus.failure, errorMessage: _clean(e)),
      );
    }
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');
}
