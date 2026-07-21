import 'package:dio/dio.dart';

import '../../core/networks/api_config.dart';
import '../../domain/entity/profile_entity.dart';

/// Talks to the Flask drone endpoints (/api/drones).
///
/// Home + Profile read the paired unit's live status from here; pairing binds
/// a drone to the signed-in user (JWT attached automatically when present).
class DroneService {
  DroneService({Dio? dio}) : _dio = dio ?? Dio(ApiConfig.options());

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

  /// The drone the app should display (paired unit, or the shared demo unit).
  Future<AssignedDroneEntity> fetchStatus() async {
    final response = await _guard(
      () async => _dio.get(
        '${ApiConfig.baseUrl()}/api/drones/status',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 &&
        data is Map<String, dynamic> &&
        data['drone'] is Map<String, dynamic>) {
      return AssignedDroneEntity.fromJson(data['drone'] as Map<String, dynamic>);
    }
    throw Exception(_messageOf(data, 'Could not load drone status'));
  }

  /// Pair the signed-in user with a drone by serial number.
  Future<AssignedDroneEntity> pair({required String serialNumber}) async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/drones/pair',
        data: {'serial_number': serialNumber.trim()},
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 &&
        data is Map<String, dynamic> &&
        data['drone'] is Map<String, dynamic>) {
      return AssignedDroneEntity.fromJson(data['drone'] as Map<String, dynamic>);
    }
    throw Exception(_messageOf(data, 'Could not pair drone'));
  }

  Future<void> unpair() async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/drones/unpair',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );
    if (response.statusCode != 200) {
      throw Exception(_messageOf(response.data, 'Could not unpair drone'));
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
