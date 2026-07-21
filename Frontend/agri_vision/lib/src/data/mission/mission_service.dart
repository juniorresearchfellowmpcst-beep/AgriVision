import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../core/networks/api_config.dart';
import '../../domain/entity/mission_entity.dart';
import '../../domain/entity/mission_report.dart';

/// Talks to the Flask mission endpoints (/api/mission).
///
/// Two jobs:
///   * planning — send KML text, get back a ready-to-fly survey path
///   * history  — save planned missions and track their lifecycle so the
///     Home/Reports screens list real flights.
class MissionService {
  MissionService({Dio? dio}) : _dio = dio ?? Dio(ApiConfig.options());

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

  /// Plan a survey path from raw KML text. Returns the waypoints the backend
  /// lawnmower-planner produced (server is the source of truth for spacing).
  Future<List<WaypointModel>> planFromKml({
    required String kmlText,
    double altitudeM = 60.0,
    double lineSpacingM = 20.0,
  }) async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/mission/upload-kml',
        data: {
          'kml': kmlText,
          'altitude_m': altitudeM,
          'line_spacing_m': lineSpacingM,
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      final waypoints = (data['mission']?['waypoints'] as List?) ?? const [];
      return [
        for (final (i, wp) in waypoints.whereType<Map>().indexed)
          WaypointModel(
            id: (wp['seq'] is num ? (wp['seq'] as num).toInt() : i) + 1,
            position: LatLng(
              (wp['lat'] as num).toDouble(),
              (wp['lon'] as num).toDouble(),
            ),
          ),
      ];
    }
    throw Exception(_messageOf(data, 'Mission planning failed'));
  }

  /// Persist a planned mission; returns its backend id.
  Future<int> saveMission({
    required String name,
    required List<WaypointModel> waypoints,
    required MissionSettings settings,
    required double areaHa,
    String? mode,
  }) async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/mission/missions',
        data: {
          'name': name.trim(),
          'mode': mode,
          'area_ha': areaHa,
          'altitude_m': settings.altitude,
          'speed_ms': settings.speed,
          'overlap_pct': settings.overlap,
          'line_spacing_m': settings.lineSpacing,
          'waypoints': [
            for (final w in waypoints)
              {'lat': w.position.latitude, 'lon': w.position.longitude},
          ],
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 201 &&
        data is Map<String, dynamic> &&
        data['mission']?['id'] is num) {
      return (data['mission']['id'] as num).toInt();
    }
    throw Exception(_messageOf(data, 'Could not save mission'));
  }

  /// Mission history, newest first.
  Future<List<MissionReportEntity>> fetchMissions() async {
    final response = await _guard(
      () async => _dio.get(
        '${ApiConfig.baseUrl()}/api/mission/missions',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return MissionReportEntity.fromJsonList(
        (data['missions'] as List?) ?? const [],
      );
    }
    throw Exception(_messageOf(data, 'Could not load missions'));
  }

  /// Move a mission through its lifecycle (in_progress → done | partial ...).
  Future<void> updateStatus({
    required int missionId,
    required String status,
    double? durationMin,
  }) async {
    final response = await _guard(
      () async => _dio.patch(
        '${ApiConfig.baseUrl()}/api/mission/missions/$missionId/status',
        data: {
          'status': status,
          if (durationMin != null) 'duration_min': durationMin,
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );
    if (response.statusCode != 200) {
      throw Exception(_messageOf(response.data, 'Could not update mission'));
    }
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
