import 'package:dio/dio.dart';

import '../../core/networks/api_config.dart';
import '../../domain/entity/profile_entity.dart';

/// Talks to the Flask profile endpoints (/api/users/me). Requires a JWT.
class ProfileService {
  ProfileService({Dio? dio}) : _dio = dio ?? Dio(ApiConfig.options());

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

  /// The signed-in pilot's profile + flight stats + paired drone (if any).
  Future<(PilotProfileEntity, AssignedDroneEntity?)> fetchMe() async {
    final response = await _guard(
      () async => _dio.get(
        '${ApiConfig.baseUrl()}/api/users/me',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 &&
        data is Map<String, dynamic> &&
        data['user'] is Map<String, dynamic>) {
      final user = data['user'] as Map<String, dynamic>;
      final drone = user['drone'] is Map<String, dynamic>
          ? AssignedDroneEntity.fromJson(user['drone'] as Map<String, dynamic>)
          : null;
      return (PilotProfileEntity.fromJson(user), drone);
    }
    throw Exception(_messageOf(data, 'Could not load profile'));
  }

  /// Update editable profile fields; returns the fresh profile.
  Future<(PilotProfileEntity, AssignedDroneEntity?)> updateMe({
    String? username,
    String? phone,
    String? location,
    String? organisation,
    String? role,
  }) async {
    final response = await _guard(
      () async => _dio.put(
        '${ApiConfig.baseUrl()}/api/users/me',
        data: {
          if (username != null) 'username': username,
          if (phone != null) 'phone': phone,
          if (location != null) 'location': location,
          if (organisation != null) 'organisation': organisation,
          if (role != null) 'role': role,
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 &&
        data is Map<String, dynamic> &&
        data['user'] is Map<String, dynamic>) {
      final user = data['user'] as Map<String, dynamic>;
      final drone = user['drone'] is Map<String, dynamic>
          ? AssignedDroneEntity.fromJson(user['drone'] as Map<String, dynamic>)
          : null;
      return (PilotProfileEntity.fromJson(user), drone);
    }
    throw Exception(_messageOf(data, 'Could not update profile'));
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
