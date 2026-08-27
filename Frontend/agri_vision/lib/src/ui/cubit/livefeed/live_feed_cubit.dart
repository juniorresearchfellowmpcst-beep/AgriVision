import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/data/capture/live_feed_service.dart';
import 'package:agri_vision/src/domain/entity/live_feed_entity.dart';

part 'live_feed_cubit_state.dart';

/// Drives the live feed screen: which camera is on screen, and what the
/// backend's rolling scan of it currently says.
///
/// The video itself is not in here. [MjpegView] owns that socket, because a
/// stream of frames is not state a cubit should be re-emitting sixty times a
/// second — every emit would rebuild the page around the picture.
///
/// What *is* in here is the analysis, and the important property is that it
/// belongs to the **server**, not to this screen. The backend samples the feed
/// on its own timer, so closing this page stops the polling but not the
/// scanning: the operator can walk over to the map, come back, and the rolling
/// summary has kept advancing over the ground the aircraft covered meanwhile.
class LiveFeedCubit extends Cubit<LiveFeedState> {
  LiveFeedCubit({LiveFeedService? service})
    : _service = service ?? LiveFeedService(),
      super(const LiveFeedState());

  final LiveFeedService _service;
  Timer? _poll;

  /// How often the readout is refreshed. Half the analyser's own interval, so
  /// a new scan is picked up promptly without asking for answers that cannot
  /// have changed yet.
  static const _pollEvery = Duration(seconds: 2);

  @override
  Future<void> close() {
    _poll?.cancel();
    return super.close();
  }

  // ── which camera ───────────────────────────────────────────────────────

  /// Point the screen at a camera. Safe to call repeatedly with the same id.
  Future<void> watch(int cameraId, {String? cameraName}) async {
    if (state.cameraId == cameraId && state.loaded) return;

    _poll?.cancel();
    emit(
      LiveFeedState(
        cameraId: cameraId,
        cameraName: cameraName ?? '',
        status: LiveFeedStatus.loading,
      ),
    );

    final supported = await _service.supportsLiveVideo();
    if (isClosed) return;

    if (!supported) {
      emit(
        state.copyWith(
          status: LiveFeedStatus.unsupported,
          loaded: true,
          errorMessage:
              'This backend does not serve live video. Update the server, or '
              'use Capture to take stills instead.',
        ),
      );
      return;
    }

    emit(state.copyWith(status: LiveFeedStatus.ready, loaded: true));

    // An analysis may already be running from a previous visit to this page,
    // or from another handset watching the same aircraft. Adopt it rather
    // than showing "not scanning" over a scan that is very much happening.
    await refresh();
    if (state.analysis?.running == true) _startPolling();
  }

  void stopWatching() {
    _poll?.cancel();
    _poll = null;
  }

  // ── analysis ───────────────────────────────────────────────────────────

  Future<bool> startAnalysis({
    String? crop,
    String? fieldName,
    double intervalS = 3,
  }) async {
    final cameraId = state.cameraId;
    if (cameraId == null) return false;

    emit(state.copyWith(starting: true, errorMessage: ''));
    try {
      final analysis = await _service.startAnalysis(
        cameraId,
        crop: crop,
        fieldName: fieldName,
        intervalS: intervalS,
      );
      if (isClosed) return false;
      emit(state.copyWith(analysis: analysis, starting: false));
      _startPolling();
      return true;
    } catch (e) {
      if (isClosed) return false;
      emit(state.copyWith(starting: false, errorMessage: _clean(e)));
      return false;
    }
  }

  Future<void> stopAnalysis() async {
    final cameraId = state.cameraId;
    if (cameraId == null) return;

    _poll?.cancel();
    _poll = null;
    try {
      await _service.stopAnalysis(cameraId);
    } catch (e) {
      emit(state.copyWith(errorMessage: _clean(e)));
    }
    if (isClosed) return;
    emit(state.copyWith(clearAnalysis: true));
  }

  /// Read the current state of the scan once.
  Future<void> refresh() async {
    final cameraId = state.cameraId;
    if (cameraId == null) return;

    try {
      final analysis = await _service.fetchAnalysis(cameraId);
      if (isClosed) return;
      emit(
        analysis == null
            ? state.copyWith(clearAnalysis: true, errorMessage: '')
            : state.copyWith(analysis: analysis, errorMessage: ''),
      );
    } catch (e) {
      if (isClosed) return;
      // A dropped poll is not worth an error banner over a working video
      // feed; the next tick will either recover or the failure will persist
      // into the readout the operator can see is stale.
      emit(state.copyWith(errorMessage: _clean(e)));
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollEvery, (_) {
      if (isClosed) return;
      refresh();
    });
  }

  String _clean(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}
