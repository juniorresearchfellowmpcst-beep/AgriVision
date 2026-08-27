import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/data/survey/survey_service.dart';
import 'package:agri_vision/src/domain/entity/survey_entity.dart';

part 'survey_cubit_state.dart';

/// Drives one survey flight from camera selection to an authorised spray.
///
/// App-scoped, and that is not an optimisation: a survey outlives every screen
/// it is watched from. The scanning runs on the *server*, so walking away from
/// the in-flight page stops the polling, not the flight — and coming back
/// adopts the run that kept going meanwhile.
///
/// The one thing this cubit will not do is shorten the consent chain. Filling
/// the tank and authorising the spray are two separate calls to
/// [confirmTank] and [authoriseSpray], the server checks both again, and
/// `start` is a third flag on top — because each is a different mistake to
/// make, and collapsing them would make all three easy to make at once.
class SurveyCubit extends Cubit<SurveyState> {
  SurveyCubit({SurveyService? service})
    : _service = service ?? SurveyService(),
      super(const SurveyState());

  final SurveyService _service;
  Timer? _poll;

  /// How often the in-flight screen re-reads the run. Matched to the server's
  /// sampling interval: polling faster shows the same numbers again over a
  /// field connection that has better things to carry.
  static const Duration _pollInterval = Duration(seconds: 3);

  @override
  Future<void> close() {
    _poll?.cancel();
    return super.close();
  }

  // ── setup ───────────────────────────────────────────────────────────────

  /// Read what this rig can fly, and adopt any run already in the air.
  Future<void> load({bool refresh = false}) async {
    if (state.capabilities.cameraModes.isNotEmpty && !refresh) return;

    emit(state.copyWith(status: SurveyStatus.loading, errorMessage: ''));
    try {
      final capabilities = await _service.fetchCapabilities();
      if (isClosed) return;

      final runs = await _service.fetchRuns();
      if (isClosed) return;

      emit(
        state.copyWith(
          status: SurveyStatus.ready,
          capabilities: capabilities,
          history: runs.runs,
          // Preselect the richest mode this rig can actually fly, rather than
          // a default the operator then has to change.
          cameraMode: state.cameraModeTouched
              ? state.cameraMode
              : capabilities.defaultMode,
        ),
      );

      // A run still in the air belongs to this aircraft, whichever phone
      // started it. Adopting it is what makes the app usable from a second
      // handset mid-flight.
      if (runs.active != null && runs.active!.isFlying) {
        emit(state.copyWith(run: runs.active));
        watch(runs.active!.id);
      }
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: SurveyStatus.failure,
          errorMessage: _clean(e),
        ),
      );
    }
  }

  void selectCameraMode(CameraMode mode) => emit(
    state.copyWith(cameraMode: mode, cameraModeTouched: true, errorMessage: ''),
  );

  void selectTarget(DetectionTarget target) =>
      emit(state.copyWith(target: target));

  void selectCrop(String? cropId) =>
      emit(state.copyWith(crop: cropId, clearCrop: cropId == null));

  void setFieldName(String value) => emit(state.copyWith(fieldName: value));

  // ── the flight ──────────────────────────────────────────────────────────

  Future<void> start() async {
    final option = state.capabilities.optionFor(state.cameraMode);
    if (option != null && !option.available) {
      // Caught here as well as server-side: the button should already be
      // disabled, and if it was not, the reason is more useful than a 409.
      emit(
        state.copyWith(
          status: SurveyStatus.failure,
          errorMessage: option.reason,
        ),
      );
      return;
    }

    emit(state.copyWith(status: SurveyStatus.starting, errorMessage: ''));
    try {
      final started = await _service.start(
        cameraMode: state.cameraMode,
        target: state.target,
        crop: state.crop,
        fieldName: state.fieldName,
      );
      if (isClosed) return;

      emit(
        state.copyWith(
          status: SurveyStatus.flying,
          run: started.run,
          warnings: started.warnings,
          clearSummary: true,
          progress: SurveyProgress.none,
        ),
      );
      watch(started.run.id);
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(status: SurveyStatus.failure, errorMessage: _clean(e)),
      );
    }
  }

  /// Adopt a run and start polling it.
  void watch(int runId) {
    _poll?.cancel();
    _refresh(runId);
    _poll = Timer.periodic(_pollInterval, (_) => _refresh(runId));
  }

  void stopWatching() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _refresh(int runId) async {
    try {
      final status = await _service.status(runId);
      if (isClosed) return;
      emit(state.copyWith(run: status.run, progress: status.progress));

      // The run ended somewhere else — another handset finished it, or it was
      // cancelled. Stop polling rather than asking forever.
      if (!status.run.isFlying) stopWatching();
    } catch (e) {
      if (isClosed) return;
      // A dropped poll is not a failed survey: the aircraft is still flying
      // and the server is still scanning. Surface it without tearing down the
      // screen the operator is watching.
      emit(state.copyWith(pollError: _clean(e)));
    }
  }

  Future<void> shoot() async {
    final run = state.run;
    if (run == null) return;
    emit(state.copyWith(isShooting: true, errorMessage: ''));
    try {
      final message = await _service.shoot(run.id);
      if (isClosed) return;
      emit(state.copyWith(isShooting: false, lastShotMessage: message));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(isShooting: false, errorMessage: _clean(e)));
    }
  }

  // ── the summary ─────────────────────────────────────────────────────────

  Future<void> finish() async {
    final run = state.run;
    if (run == null) return;

    stopWatching();
    emit(state.copyWith(status: SurveyStatus.summarising, errorMessage: ''));
    try {
      final finished = await _service.finish(run.id);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: SurveyStatus.summarised,
          run: finished.run,
          summary: finished.summary,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(status: SurveyStatus.failure, errorMessage: _clean(e)),
      );
    }
  }

  /// Re-open a finished run from the history list.
  Future<void> openSummary(int runId) async {
    emit(state.copyWith(status: SurveyStatus.summarising, errorMessage: ''));
    try {
      final opened = await _service.summary(runId);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: SurveyStatus.summarised,
          run: opened.run,
          summary: opened.summary,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(status: SurveyStatus.failure, errorMessage: _clean(e)),
      );
    }
  }

  Future<void> cancel() async {
    final run = state.run;
    if (run == null) return;
    stopWatching();
    try {
      await _service.cancel(run.id);
    } catch (_) {
      // Cancelling is a local intention; a failed call should not trap the
      // operator on a screen for a flight they have already walked away from.
    }
    if (isClosed) return;
    emit(const SurveyState().copyWith(capabilities: state.capabilities));
  }

  // ── the spray ───────────────────────────────────────────────────────────

  /// The farmer says the tank is filled. A statement about the aircraft.
  void confirmTank({required double? litres, required String? product}) => emit(
    state.copyWith(
      tankFilled: true,
      tankLitres: litres,
      tankProduct: product,
      errorMessage: '',
    ),
  );

  void clearTank() => emit(state.copyWith(tankFilled: false, clearTank: true));

  void selectOption(String optionId) => emit(state.copyWith(option: optionId));

  /// The farmer gives permission, and the plan goes to the aircraft.
  ///
  /// [start] is separate again: uploading the mission is safe on the bench,
  /// and launching it is not.
  Future<void> authoriseSpray({
    required String authorisedBy,
    bool start = true,
  }) async {
    final run = state.run;
    final summary = state.summary;
    if (run == null || summary == null) return;

    if (!state.tankFilled) {
      emit(
        state.copyWith(
          errorMessage:
              'Confirm the tank is filled first — the aircraft will fly the '
              'whole prescription whether or not there is anything in it.',
        ),
      );
      return;
    }

    emit(state.copyWith(status: SurveyStatus.authorising, errorMessage: ''));
    try {
      final result = await _service.authorise(
        runId: run.id,
        tankFilled: true,
        authorised: true,
        option: state.option ??
            summary.treatmentMap?.recommendedOption?.id ??
            'severe_only',
        tankLitres: state.tankLitres,
        tankProduct: state.tankProduct,
        authorisedBy: authorisedBy,
        start: start,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          status: SurveyStatus.spraying,
          run: result.run.id == 0 ? run : result.run,
          sprayMessage: result.message,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      // The authorisation itself is recorded server-side even when the upload
      // fails, so the farmer is not asked to confirm the tank a second time.
      emit(
        state.copyWith(
          status: SurveyStatus.summarised,
          errorMessage: _clean(e),
        ),
      );
    }
  }

  /// Back to a clean setup screen, keeping what the rig can do.
  void reset() {
    stopWatching();
    emit(
      const SurveyState().copyWith(
        capabilities: state.capabilities,
        history: state.history,
        status: SurveyStatus.ready,
      ),
    );
  }

  String _clean(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}
