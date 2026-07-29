import 'package:dio/dio.dart';

import '../../core/networks/api_config.dart';
import '../../domain/entity/mission_entity.dart';
import '../../domain/entity/telemetry_entity.dart';

/// Talks to the Flask MAVLink endpoints (/api/mavlink).
///
/// This is the bridge between a mission planned on the map and a vehicle that
/// actually flies it: the backend holds the MAVLink link (to real hardware or
/// a SITL simulator), and this service opens it, writes the waypoint list to
/// the flight controller, launches, and streams telemetry back.
class MavlinkService {
  MavlinkService({Dio? dio}) : _dio = dio ?? Dio(ApiConfig.options());

  final Dio _dio;

  /// Runs [request], converting transport failures (no Wi-Fi, server down)
  /// into a short human-readable [Exception] the UI can display.
  Future<Response> _guard(Future<Response> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw Exception(ApiConfig.friendlyDioError(e));
    }
  }

  /// Link health + latest telemetry. Polled by the live mission screen.
  Future<MavlinkStatusEntity> fetchStatus() async {
    final response = await _guard(
      () async => _dio.get(
        '${ApiConfig.baseUrl()}/api/mavlink/status',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return MavlinkStatusEntity.fromJson(data);
    }
    throw Exception(_messageOf(data, 'Could not read vehicle status'));
  }

  /// Open the link. [url] is a pymavlink connection string; leaving it null
  /// uses the backend's configured `MAVLINK_URL` (the simulator by default).
  Future<MavlinkStatusEntity> connect({String? url, int? baud}) async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/mavlink/connect',
        data: {
          if (url != null && url.trim().isNotEmpty) 'url': url.trim(),
          if (baud != null) 'baud': baud,
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return MavlinkStatusEntity.fromJson(data);
    }
    throw Exception(_messageOf(data, 'Could not connect to the vehicle'));
  }

  Future<MavlinkStatusEntity> disconnect() async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/mavlink/disconnect',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return MavlinkStatusEntity.fromJson(data);
    }
    throw Exception(_messageOf(data, 'Could not close the link'));
  }

  /// Write the planned survey path to the flight controller.
  ///
  /// The backend adds the home/takeoff/RTL items around these waypoints, so
  /// what goes up is a complete flyable mission, not just the survey legs.
  /// Returns the number of mission items the vehicle accepted.
  Future<int> uploadMission({
    required List<WaypointModel> waypoints,
    required MissionSettings settings,
    String? name,
    int? missionId,
    double? speedMs,
  }) async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/mavlink/mission',
        data: {
          if (name != null) 'name': name,
          if (missionId != null) 'mission_id': missionId,
          'altitude_m': settings.altitude,
          'speed_ms': speedMs ?? settings.speed,
          'waypoints': [
            for (final w in waypoints)
              {'lat': w.position.latitude, 'lon': w.position.longitude},
          ],
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      final uploaded = data['uploaded'];
      return uploaded is num ? uploaded.toInt() : 0;
    }
    throw Exception(_messageOf(data, 'Could not upload the mission'));
  }

  /// Launch: AUTO + arm + mission start.
  Future<MavlinkStatusEntity> startMission({int? missionId}) async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/mavlink/start',
        data: {if (missionId != null) 'mission_id': missionId},
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return MavlinkStatusEntity.fromJson(data);
    }
    throw Exception(_messageOf(data, 'Could not start the mission'));
  }

  /// One flight action: arm, disarm, takeoff, rtl, land, hold, auto, guided.
  Future<MavlinkStatusEntity> sendCommand(
    String action, {
    double? altitudeM,
    int? missionId,
  }) async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/mavlink/command',
        data: {
          'action': action,
          if (altitudeM != null) 'altitude_m': altitudeM,
          if (missionId != null) 'mission_id': missionId,
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return MavlinkStatusEntity.fromJson(data);
    }
    throw Exception(_messageOf(data, "Vehicle rejected '$action'"));
  }

  String _messageOf(dynamic data, String fallback) {
    if (data is Map) {
      // 'message' is ours; 'msg' is flask-jwt-extended (e.g. token expired).
      final message = data['message'] ?? data['msg'];
      if (message != null) return message.toString();
    }
    return fallback;
  }
}
