import 'package:dio/dio.dart';

import '../../core/networks/api_config.dart';
import '../../domain/entity/profile_entity.dart';

/// Talks to the Flask pilot-credentials endpoints (/api/credentials).
///
/// Licences, certificates and clearances are personal paperwork, so every call
/// here needs a JWT. The backend recomputes valid / expiring / expired from
/// the stored expiry on each read — the app never derives the badge itself.
class CredentialService {
  CredentialService({Dio? dio}) : _dio = dio ?? Dio(ApiConfig.options());

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

  /// The pilot's credentials. Returns (credentials, expiringCount, expiredCount).
  Future<(List<PilotCredentialEntity>, int, int)> fetchCredentials() async {
    final response = await _guard(
      () async => _dio.get(
        '${ApiConfig.baseUrl()}/api/credentials',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      int count(String key) => data[key] is num ? (data[key] as num).toInt() : 0;
      return (
        PilotCredentialEntity.fromJsonList(
          (data['credentials'] as List?) ?? const [],
        ),
        count('expiring_count'),
        count('expired_count'),
      );
    }
    throw Exception(_messageOf(data, 'Could not load credentials'));
  }

  /// Update one credential's number, issuer or dates.
  Future<PilotCredentialEntity> updateCredential({
    required int id,
    String? identifier,
    String? issuer,
    String? label,
    DateTime? issuedOn,
    DateTime? expiresOn,
    bool clearExpiry = false,
  }) async {
    String? iso(DateTime? d) =>
        d == null ? null : d.toIso8601String().substring(0, 10);

    final response = await _guard(
      () async => _dio.put(
        '${ApiConfig.baseUrl()}/api/credentials/$id',
        data: {
          if (identifier != null) 'identifier': identifier,
          if (issuer != null) 'issuer': issuer,
          if (label != null) 'label': label,
          if (issuedOn != null) 'issued_on': iso(issuedOn),
          // An explicit null clears the expiry; omitting the key leaves it.
          if (expiresOn != null || clearExpiry)
            'expires_on': clearExpiry ? null : iso(expiresOn),
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 &&
        data is Map<String, dynamic> &&
        data['credential'] is Map) {
      return PilotCredentialEntity.fromJson(
        Map<String, dynamic>.from(data['credential'] as Map),
      );
    }
    throw Exception(_messageOf(data, 'Could not update the credential'));
  }

  /// Add a credential the seeded list doesn't cover.
  Future<PilotCredentialEntity> addCredential({
    required String label,
    String kind = 'other',
    String? identifier,
    DateTime? expiresOn,
  }) async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/credentials',
        data: {
          'label': label,
          'kind': kind,
          if (identifier != null) 'identifier': identifier,
          if (expiresOn != null)
            'expires_on': expiresOn.toIso8601String().substring(0, 10),
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 201 &&
        data is Map<String, dynamic> &&
        data['credential'] is Map) {
      return PilotCredentialEntity.fromJson(
        Map<String, dynamic>.from(data['credential'] as Map),
      );
    }
    throw Exception(_messageOf(data, 'Could not add the credential'));
  }

  Future<void> deleteCredential(int id) async {
    final response = await _guard(
      () async => _dio.delete(
        '${ApiConfig.baseUrl()}/api/credentials/$id',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );
    if (response.statusCode != 200) {
      throw Exception(
        _messageOf(response.data, 'Could not remove the credential'),
      );
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
