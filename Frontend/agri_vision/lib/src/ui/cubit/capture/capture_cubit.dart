import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/data/capture/capture_service.dart';
import 'package:agri_vision/src/domain/entity/capture_entity.dart';
import 'package:agri_vision/src/domain/entity/media_file.dart';

part 'capture_cubit_state.dart';

/// Drives the live-capture screen: register the drone's cameras, trigger them,
/// and keep the shots of the current flight together.
///
/// App-scoped, like [DroneCubit] and [MavlinkCubit], because a capture session
/// outlives the screen: the operator shoots on the capture page, walks over to
/// the spray page to prescribe from it, and comes back to shoot again — all of
/// which should land in the same session.
class CaptureCubit extends Cubit<CaptureState> {
  CaptureCubit({CaptureService? service})
    : _service = service ?? CaptureService(),
      super(const CaptureState());

  final CaptureService _service;

  // ── camera registry ─────────────────────────────────────────────────────

  Future<void> load({bool refresh = false}) async {
    if (state.status == CaptureStatus.loading) return;
    if (state.loaded && !refresh) return;

    emit(state.copyWith(status: CaptureStatus.loading, errorMessage: ''));
    try {
      final registry = await _service.fetchCameras();
      emit(
        state.copyWith(
          status: CaptureStatus.ready,
          registry: registry,
          loaded: true,
        ),
      );
      await loadShots();
    } catch (e) {
      emit(
        state.copyWith(status: CaptureStatus.failure, errorMessage: _clean(e)),
      );
    }
  }

  Future<bool> addCamera({
    required String name,
    required String role,
    required String url,
    String? band,
    double? fovDeg,
  }) async {
    try {
      await _service.addCamera(
        name: name,
        role: role,
        url: url,
        band: band,
        fovDeg: fovDeg,
      );
      await load(refresh: true);
      return true;
    } catch (e) {
      emit(state.copyWith(errorMessage: _clean(e)));
      return false;
    }
  }

  Future<void> removeCamera(int cameraId) async {
    try {
      await _service.deleteCamera(cameraId);
      await load(refresh: true);
    } catch (e) {
      emit(state.copyWith(errorMessage: _clean(e)));
    }
  }

  /// Probe a feed before saving it, so a typo is caught on the bench rather
  /// than in the field. Never throws — a dead camera is a result to show.
  Future<CameraProbe> testCamera({int? cameraId, String? url}) async {
    try {
      return await _service.testCamera(cameraId: cameraId, url: url);
    } catch (e) {
      return CameraProbe(reachable: false, message: _clean(e));
    }
  }

  // ── capture ─────────────────────────────────────────────────────────────

  void setFieldName(String value) => emit(state.copyWith(fieldName: value));

  /// Start a fresh session — a new flight, or a new block.
  void newSession() => emit(
    state.copyWith(clearSession: true, shots: const [], clearLastShot: true),
  );

  Future<void> shoot() async {
    if (state.isCapturing) return;
    emit(state.copyWith(status: CaptureStatus.capturing, errorMessage: ''));

    try {
      final shot = await _service.shoot(
        sessionId: state.sessionId,
        fieldName: state.fieldName,
      );
      emit(
        state.copyWith(
          status: CaptureStatus.ready,
          sessionId: shot.sessionId,
          lastShot: shot,
          shots: [shot, ...state.shots],
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(status: CaptureStatus.failure, errorMessage: _clean(e)),
      );
    }
  }

  /// Store frames the phone already holds, as if the cameras had taken them.
  Future<void> uploadFrames(Map<String, MediaFile> bands) async {
    if (bands.isEmpty || state.isCapturing) return;
    emit(state.copyWith(status: CaptureStatus.capturing, errorMessage: ''));

    try {
      final shot = await _service.uploadFrames(
        bands: bands,
        sessionId: state.sessionId,
        fieldName: state.fieldName,
      );
      emit(
        state.copyWith(
          status: CaptureStatus.ready,
          sessionId: shot.sessionId,
          lastShot: shot,
          shots: [shot, ...state.shots],
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(status: CaptureStatus.failure, errorMessage: _clean(e)),
      );
    }
  }

  /// Shots already recorded. A history failure stays quiet: it must not bury
  /// the capture the operator just took behind a network error.
  Future<void> loadShots() async {
    try {
      final shots = await _service.fetchShots(sessionId: state.sessionId);
      if (isClosed) return;
      emit(state.copyWith(shots: shots));
    } catch (_) {
      // Ignored on purpose — see above.
    }
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');
}
