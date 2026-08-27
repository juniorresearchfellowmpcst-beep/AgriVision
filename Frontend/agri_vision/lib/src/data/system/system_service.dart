import 'package:dio/dio.dart';

import '../../core/networks/api_config.dart';
import '../../domain/entity/system_links_entity.dart';

/// Reads the backend's own connection information.
///
/// The one call in the app that answers "what address is the server on, and
/// what do I type into Mission Planner?" — questions that otherwise send an
/// operator to `ipconfig` on a laptop they may not be standing next to.
class SystemService {
  SystemService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            ApiConfig.options(
              // The links call enumerates network interfaces, which is fast,
              // but the device may be on a flaky field network. Fail early so
              // the settings screen shows its error state rather than a
              // spinner that never resolves.
              receiveTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(seconds: 10),
            ),
          );

  final Dio _dio;

  /// Where this backend is reachable, and where a ground station should send.
  Future<SystemLinksEntity> fetchLinks() async {
    final response = await _guard(
      () => _dio.get(
        '${ApiConfig.baseUrl()}/api/system/links',
        options: Options(headers: {}),
      ),
    );

    final data = response.data;
    if (response.statusCode != 200 || data is! Map) {
      throw Exception(_messageOf(data, 'Could not read the server address.'));
    }
    return SystemLinksEntity.fromJson(data.cast<String, dynamic>());
  }

  /// Every module's state in one call, for the settings diagnostics row.
  Future<SystemHealth> fetchHealth() async {
    final response = await _guard(
      () => _dio.get('${ApiConfig.baseUrl()}/api/system/health'),
    );

    final data = response.data;
    if (response.statusCode != 200 || data is! Map) {
      throw Exception(_messageOf(data, 'Could not reach the server.'));
    }
    return SystemHealth.fromJson(data.cast<String, dynamic>());
  }

  /// Turn a transport failure into the same readable message every other
  /// service produces, so the settings screen has one error style.
  Future<Response> _guard(Future<Response> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw Exception(ApiConfig.friendlyDioError(e));
    }
  }

  String _messageOf(dynamic data, String fallback) {
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    return fallback;
  }
}

/// Aggregate readiness from `GET /api/system/health`.
class SystemHealth {
  const SystemHealth({
    required this.ok,
    required this.degraded,
    required this.modules,
  });

  final bool ok;

  /// Names of the modules that failed to report. Empty when all are healthy.
  final List<String> degraded;

  /// Per-module detail, keyed by module name.
  final Map<String, Map<String, dynamic>> modules;

  /// The engine answering disease scans: `model` or `heuristic`.
  String get diseaseEngine =>
      modules['disease']?['engine']?.toString() ?? 'unknown';

  bool get mavlinkAvailable => modules['mavlink']?['available'] == true;

  int get camerasEnabled {
    final value = modules['cameras']?['enabled'];
    return value is num ? value.toInt() : 0;
  }

  factory SystemHealth.fromJson(Map<String, dynamic> json) {
    final raw = (json['modules'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SystemHealth(
      ok: json['status']?.toString() == 'ok',
      degraded:
          (json['degraded'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      modules: {
        for (final entry in raw.entries)
          entry.key: (entry.value as Map?)?.cast<String, dynamic>() ?? {},
      },
    );
  }

  static const empty = SystemHealth(ok: false, degraded: [], modules: {});
}
