import 'package:dio/dio.dart';

import '../../core/networks/api_config.dart';
import '../../domain/entity/alert_entity.dart';
import '../../domain/entity/field_report_entity.dart';

/// Talks to the Flask analysis-history endpoints (/api/analysis).
///
/// Every analyze-images run is persisted server-side; this service reads that
/// history back as field reports (Reports tab) and AI alerts (Alerts tab).
class ReportService {
  ReportService({Dio? dio}) : _dio = dio ?? Dio(ApiConfig.options());

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

  /// Persisted analysis runs, newest first.
  Future<List<FieldReportEntity>> fetchReports() async {
    final response = await _guard(
      () async => _dio.get(
        '${ApiConfig.baseUrl()}/api/analysis/reports',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return FieldReportEntity.fromJsonList(
        (data['reports'] as List?) ?? const [],
      );
    }
    throw Exception(_messageOf(data, 'Could not load reports'));
  }

  /// Active AI alerts, newest first. Returns (activeCount, alerts).
  Future<(int, List<AlertEntity>)> fetchAlerts() async {
    final response = await _guard(
      () async => _dio.get(
        '${ApiConfig.baseUrl()}/api/analysis/alerts',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      final alerts = AlertEntity.fromJsonList(
        (data['alerts'] as List?) ?? const [],
      );
      final count = data['active_count'] is num
          ? (data['active_count'] as num).round()
          : alerts.length;
      return (count, alerts);
    }
    throw Exception(_messageOf(data, 'Could not load alerts'));
  }

  /// Mark an alert as handled so it leaves the active list.
  Future<void> resolveAlert(String alertId) async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/analysis/alerts/$alertId/resolve',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );
    if (response.statusCode != 200) {
      throw Exception(_messageOf(response.data, 'Could not resolve alert'));
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
