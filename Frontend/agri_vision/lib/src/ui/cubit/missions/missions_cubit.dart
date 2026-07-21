import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/data/mission/mission_service.dart';
import 'package:agri_vision/src/domain/entity/mission_entity.dart';
import 'package:agri_vision/src/domain/entity/mission_report.dart';

part 'missions_cubit_state.dart';

/// Mission history + planning actions.
///
/// The list feeds Home ("Recent Missions") and Reports; the imperative
/// helpers ([planFromKml], [startMission], [completeMission]) are called by
/// the Mission Planning screen and throw on failure so the page can surface
/// the error, then refresh the list here.
class MissionsCubit extends Cubit<MissionsState> {
  MissionsCubit({MissionService? service})
    : _service = service ?? MissionService(),
      super(const MissionsState());

  final MissionService _service;

  Future<void> load({bool refresh = false}) async {
    if (state.status == MissionsStatus.loading) return;
    if (state.status == MissionsStatus.success && !refresh) return;

    emit(state.copyWith(status: MissionsStatus.loading, errorMessage: ''));
    try {
      final missions = await _service.fetchMissions();
      emit(state.copyWith(status: MissionsStatus.success, missions: missions));
    } catch (e) {
      emit(
        state.copyWith(
          status: MissionsStatus.failure,
          errorMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  /// Ask the backend planner for a survey path over the KML field boundary.
  Future<List<WaypointModel>> planFromKml({
    required String kmlText,
    required MissionSettings settings,
  }) {
    return _service.planFromKml(
      kmlText: kmlText,
      altitudeM: settings.altitude.toDouble(),
      lineSpacingM: settings.lineSpacing,
    );
  }

  /// Save a planned mission (without flying it). Returns the backend id.
  Future<int> saveMission({
    required String name,
    required List<WaypointModel> waypoints,
    required MissionSettings settings,
    required double areaHa,
  }) async {
    final id = await _service.saveMission(
      name: name,
      waypoints: waypoints,
      settings: settings,
      areaHa: areaHa,
    );
    await load(refresh: true);
    return id;
  }

  /// Save + mark in-flight, just before the live mission screen opens.
  Future<int> startMission({
    required String name,
    required List<WaypointModel> waypoints,
    required MissionSettings settings,
    required double areaHa,
    required MissionMode mode,
  }) async {
    final id = await _service.saveMission(
      name: name,
      waypoints: waypoints,
      settings: settings,
      areaHa: areaHa,
      mode: mode.name,
    );
    await _service.updateStatus(missionId: id, status: 'in_progress');
    await load(refresh: true);
    return id;
  }

  /// Close out a flight when the live screen is left.
  Future<void> completeMission({
    required int missionId,
    String status = 'done',
    double? durationMin,
  }) async {
    await _service.updateStatus(
      missionId: missionId,
      status: status,
      durationMin: durationMin,
    );
    await load(refresh: true);
  }
}
