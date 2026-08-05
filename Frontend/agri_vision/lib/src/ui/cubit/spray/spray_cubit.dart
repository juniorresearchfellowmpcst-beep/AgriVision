import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/data/spray/spray_service.dart';
import 'package:agri_vision/src/domain/entity/spray_prescription.dart';

part 'spray_cubit_state.dart';

/// Drives the spray-prescription screen.
///
/// The state machine mirrors the decision the operator is making, and keeps
/// the steps apart on purpose:
///
///   prescribe  → the field is clustered and the options are costed
///   selectOption → the exact mission for that choice is built, still local
///   execute    → the mission goes to the aircraft; `start` launches it
///
/// Nothing here sends a command to hardware except [execute], and [execute]
/// only launches when the page explicitly asks it to.
class SprayCubit extends Cubit<SprayState> {
  SprayCubit({SprayService? service})
    : _service = service ?? SprayService(),
      super(const SprayState());

  final SprayService _service;

  /// Cluster a captured shot into spray zones and cost the options.
  Future<void> prescribe({
    required String shotId,
    int k = 3,
    double? doseLPerHa,
    double? fovDeg,
    double? fieldAreaHa,
  }) async {
    emit(
      state.copyWith(
        status: SprayStatus.prescribing,
        errorMessage: '',
        message: '',
        clearPrescription: true,
        clearPlan: true,
        clearOption: true,
      ),
    );

    try {
      final prescription = await _service.prescribe(
        shotId: shotId,
        k: k,
        doseLPerHa: doseLPerHa,
        fovDeg: fovDeg,
        fieldAreaHa: fieldAreaHa,
      );
      emit(
        state.copyWith(status: SprayStatus.ready, prescription: prescription),
      );
      await loadHistory(refresh: true);
    } catch (e) {
      emit(state.copyWith(status: SprayStatus.failure, errorMessage: _clean(e)));
    }
  }

  /// Choose a spray option and build the mission it would fly.
  ///
  /// The plan comes back with the saving re-costed against the rig's actual
  /// hardware — an on/off pump cannot deliver a reduced rate over the moderate
  /// zones, and the number shown to the farmer has to match what will happen.
  Future<void> selectOption(String optionId) async {
    final prescription = state.prescription;
    if (prescription?.id == null) return;

    emit(
      state.copyWith(
        status: SprayStatus.planning,
        selectedOption: optionId,
        errorMessage: '',
        message: '',
        clearPlan: true,
      ),
    );

    try {
      final plan = await _service.plan(
        prescriptionId: prescription!.id!,
        option: optionId,
      );
      emit(state.copyWith(status: SprayStatus.planned, plan: plan));
    } catch (e) {
      emit(
        state.copyWith(
          status: SprayStatus.failure,
          errorMessage: _clean(e),
          clearOption: true,
        ),
      );
    }
  }

  /// Send the plan to the aircraft. [start] launches it as well.
  Future<void> execute({bool start = false}) async {
    final prescription = state.prescription;
    final option = state.selectedOption;
    if (prescription?.id == null || option == null) return;

    emit(state.copyWith(status: SprayStatus.sending, errorMessage: '', message: ''));
    try {
      final message = await _service.execute(
        prescriptionId: prescription!.id!,
        option: option,
        start: start,
      );
      emit(
        state.copyWith(
          status: start ? SprayStatus.spraying : SprayStatus.uploaded,
          message: message,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          // Fall back to 'planned', not 'failure': the plan is still valid and
          // the operator should be able to retry without re-clustering.
          status: SprayStatus.planned,
          errorMessage: _clean(e),
        ),
      );
    }
  }

  /// Shut the valve now and hold position.
  Future<void> stopSpray() async {
    try {
      final message = await _service.stop();
      emit(state.copyWith(status: SprayStatus.planned, message: message));
    } catch (e) {
      emit(state.copyWith(errorMessage: _clean(e)));
    }
  }

  Future<void> loadHistory({bool refresh = false}) async {
    if (state.history.isNotEmpty && !refresh) return;
    try {
      final history = await _service.fetchHistory();
      if (isClosed) return;
      emit(state.copyWith(history: history));
    } catch (_) {
      // A history failure must not bury the prescription on screen.
    }
  }

  /// Re-open a prescription the operator approved earlier.
  Future<void> openPrescription(int prescriptionId) async {
    emit(
      state.copyWith(
        status: SprayStatus.prescribing,
        errorMessage: '',
        message: '',
        clearPlan: true,
        clearOption: true,
      ),
    );
    try {
      final prescription = await _service.fetchPrescription(prescriptionId);
      emit(
        state.copyWith(status: SprayStatus.ready, prescription: prescription),
      );
    } catch (e) {
      emit(state.copyWith(status: SprayStatus.failure, errorMessage: _clean(e)));
    }
  }

  void reset() => emit(SprayState(history: state.history));

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');
}
