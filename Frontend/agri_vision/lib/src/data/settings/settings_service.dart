import 'package:dio/dio.dart';

import '../../core/networks/api_config.dart';
import '../../domain/entity/settings_entity.dart';

/// Talks to the Flask preferences + sync endpoints (/api/users/me/...).
///
/// Preferences are stored server-side, so the toggles a pilot sets on the
/// phone are the same ones the tablet in the truck comes back with.
class SettingsService {
  SettingsService({Dio? dio}) : _dio = dio ?? Dio(ApiConfig.options());

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

  Future<UserPreferencesEntity> fetchPreferences() async {
    final response = await _guard(
      () async => _dio.get(
        '${ApiConfig.baseUrl()}/api/users/me/preferences',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 &&
        data is Map<String, dynamic> &&
        data['preferences'] is Map) {
      return UserPreferencesEntity.fromJson(
        Map<String, dynamic>.from(data['preferences'] as Map),
      );
    }
    throw Exception(_messageOf(data, 'Could not load settings'));
  }

  /// Partial update — send only what changed. Returns the full fresh set so
  /// the UI never has to assume the write landed as requested.
  Future<UserPreferencesEntity> updatePreferences(
    Map<String, bool> changes,
  ) async {
    final response = await _guard(
      () async => _dio.put(
        '${ApiConfig.baseUrl()}/api/users/me/preferences',
        data: changes,
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 &&
        data is Map<String, dynamic> &&
        data['preferences'] is Map) {
      return UserPreferencesEntity.fromJson(
        Map<String, dynamic>.from(data['preferences'] as Map),
      );
    }
    throw Exception(_messageOf(data, 'Could not save the setting'));
  }

  /// What the server holds per record type, for the SYNC QUEUE section.
  Future<List<SyncItemEntity>> fetchSyncStatus() async {
    final response = await _guard(
      () async => _dio.get(
        '${ApiConfig.baseUrl()}/api/users/me/sync-status',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return SyncItemEntity.fromJsonList((data['items'] as List?) ?? const []);
    }
    throw Exception(_messageOf(data, 'Could not load sync status'));
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
