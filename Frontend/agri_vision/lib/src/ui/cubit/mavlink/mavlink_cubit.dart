import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/data/mavlink/mavlink_service.dart';
import 'package:agri_vision/src/domain/entity/mission_entity.dart';
import 'package:agri_vision/src/domain/entity/telemetry_entity.dart';

part 'mavlink_cubit_state.dart';

/// The link to the actual aircraft.
///
/// Held app-scoped (like [DroneCubit]) because a flight outlives any one
/// screen: Mission Planning connects and uploads, the Live Mission screen
/// polls telemetry and sends RTL/Land, and both need the same link state.
///
/// Telemetry polling is explicit — [startPolling] on entering a live screen,
/// [stopPolling] on leaving — so the app isn't hitting the backend every
/// second while someone is editing waypoints.
class MavlinkCubit extends Cubit<MavlinkState> {
  MavlinkCubit({MavlinkService? service})
    : _service = service ?? MavlinkService(),
      super(const MavlinkState());

  final MavlinkService _service;
  Timer? _poll;

  /// 2 Hz: fast enough for a moving map marker, light enough for a phone on
  /// field Wi-Fi. The backend already has the data cached in memory.
  static const _pollInterval = Duration(milliseconds: 500);

  @override
  Future<void> close() {
    _poll?.cancel();
    return super.close();
  }

  // ── Link lifecycle ────────────────────────────────────────────────────

  /// One-shot status read (used on screen entry to show the link chip).
  Future<void> refresh() async {
    try {
      final status = await _service.fetchStatus();
      emit(state.copyWith(status: _phaseFor(status), link: status, errorMessage: ''));
    } catch (e) {
      emit(
        state.copyWith(
          status: MavlinkPhase.failure,
          errorMessage: _clean(e),
        ),
      );
    }
  }

  /// Open the MAVLink link. [url] null means "use the backend's MAVLINK_URL".
  Future<void> connect({String? url, int? baud}) async {
    emit(state.copyWith(status: MavlinkPhase.connecting, errorMessage: ''));
    try {
      final status = await _service.connect(url: url, baud: baud);
      emit(state.copyWith(status: _phaseFor(status), link: status));
    } catch (e) {
      emit(
        state.copyWith(status: MavlinkPhase.failure, errorMessage: _clean(e)),
      );
    }
  }

  Future<void> disconnect() async {
    stopPolling();
    try {
      final status = await _service.disconnect();
      emit(
        state.copyWith(
          status: MavlinkPhase.disconnected,
          link: status,
          errorMessage: '',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(status: MavlinkPhase.failure, errorMessage: _clean(e)),
      );
    }
  }

  // ── Telemetry polling ─────────────────────────────────────────────────

  /// Watch the link until [stopPolling].
  ///
  /// Polls regardless of the current state on purpose: "is there a link?" is
  /// exactly the question, and skipping the poll while disconnected means a
  /// link that comes up (or drops) is never noticed. [interval] lets a screen
  /// that only needs a live/not-live answer poll gently, while the live
  /// mission map asks often enough to move a marker smoothly.
  void startPolling({Duration interval = _pollInterval}) {
    _poll?.cancel();
    unawaited(refresh());
    _poll = Timer.periodic(interval, (_) async {
      if (isClosed) return;
      try {
        final status = await _service.fetchStatus();
        if (isClosed) return;
        emit(state.copyWith(status: _phaseFor(status), link: status));
      } catch (_) {
        // A dropped poll is not a link failure — the next tick may succeed.
        // Heartbeat age in the snapshot already tells the UI if it went stale.
      }
    });
  }

  void stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  // ── Flight actions ────────────────────────────────────────────────────

  /// Write the planned survey path to the flight controller.
  /// Returns the number of mission items accepted; throws with a readable
  /// message so the calling screen can show it.
  Future<int> uploadMission({
    required List<WaypointModel> waypoints,
    required MissionSettings settings,
    String? name,
    int? missionId,
    double? speedMs,
  }) async {
    final uploaded = await _service.uploadMission(
      waypoints: waypoints,
      settings: settings,
      name: name,
      missionId: missionId,
      speedMs: speedMs,
    );
    await refresh();
    return uploaded;
  }

  /// Launch the uploaded mission (AUTO + arm + start).
  Future<void> startMission({int? missionId}) async {
    final status = await _service.startMission(missionId: missionId);
    emit(state.copyWith(status: _phaseFor(status), link: status));
    startPolling();
  }

  /// Send one in-flight action: rtl, land, hold, arm, disarm, takeoff.
  Future<void> command(String action, {double? altitudeM, int? missionId}) async {
    final status = await _service.sendCommand(
      action,
      altitudeM: altitudeM,
      missionId: missionId,
    );
    emit(state.copyWith(status: _phaseFor(status), link: status));
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  MavlinkPhase _phaseFor(MavlinkStatusEntity status) {
    if (!status.available) return MavlinkPhase.unavailable;
    if (!status.connected) return MavlinkPhase.disconnected;
    return status.alive ? MavlinkPhase.connected : MavlinkPhase.stale;
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');
}
