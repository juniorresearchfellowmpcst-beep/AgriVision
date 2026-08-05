import 'package:dio/dio.dart';

import '../../core/networks/api_config.dart';
import '../../domain/entity/spray_prescription.dart';

/// Talks to the Flask targeted-spray endpoints (`/api/spray`).
///
/// The three calls are deliberately separate steps, and the app must keep them
/// that way:
///
///   [prescribe] — cluster the capture and cost the options. Changes nothing.
///   [plan]      — build the exact mission for a chosen option. Still nothing
///                 has been sent to the aircraft.
///   [execute]   — upload it, and only launch when `start` is true.
///
/// That is what makes the operator the one who commands the spray: every step
/// before the last is reversible, and the last one is a deliberate act.
class SprayService {
  SprayService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            ApiConfig.options(
              // Clustering a full-resolution capture takes a moment.
              receiveTimeout: const Duration(seconds: 90),
              sendTimeout: const Duration(seconds: 90),
            ),
          );

  final Dio _dio;

  Future<Response> _guard(Future<Response> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw Exception(ApiConfig.friendlyDioError(e));
    }
  }

  /// Cluster one multispectral shot into spray zones and cost the options.
  Future<SprayPrescription> prescribe({
    required String shotId,
    int k = 3,
    String? index,
    double? doseLPerHa,
    double? fovDeg,
    double? fieldAreaHa,
  }) async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/spray/prescribe',
        data: {
          'shot_id': shotId,
          'k': k,
          if (index != null && index.isNotEmpty) 'index': index,
          if (doseLPerHa != null) 'dose_l_per_ha': doseLPerHa,
          if (fovDeg != null) 'fov_deg': fovDeg,
          if (fieldAreaHa != null) 'field_area_ha': fieldAreaHa,
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return SprayPrescription.fromJson(data);
    }
    throw Exception(_messageOf(data, 'Could not build a spray prescription'));
  }

  /// What the aircraft would fly for [option] — without sending anything.
  Future<SprayPlan> plan({
    required int prescriptionId,
    required String option,
    double? altitudeM,
    double? speedMs,
  }) async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/spray/prescriptions/$prescriptionId/plan',
        data: {
          'option': option,
          if (altitudeM != null) 'altitude_m': altitudeM,
          if (speedMs != null) 'speed_ms': speedMs,
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return SprayPlan.fromJson(data);
    }
    throw Exception(_messageOf(data, 'Could not build the spray plan'));
  }

  /// Send the spray mission to the aircraft.
  ///
  /// [start] is what actually opens a valve over a field, so it is opt-in and
  /// separate from the upload. Returns the backend's message.
  Future<String> execute({
    required int prescriptionId,
    required String option,
    bool start = false,
    double? altitudeM,
    double? speedMs,
  }) async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/spray/prescriptions/$prescriptionId/execute',
        data: {
          'option': option,
          'start': start,
          if (altitudeM != null) 'altitude_m': altitudeM,
          if (speedMs != null) 'speed_ms': speedMs,
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return data['message']?.toString() ?? 'Spray mission sent.';
    }
    throw Exception(_messageOf(data, 'Could not send the spray mission'));
  }

  /// Shut the valve now and hold position — the in-flight abort.
  Future<String> stop({bool hold = true}) async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/spray/stop',
        data: {'hold': hold},
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return data['message']?.toString() ?? 'Spray stopped.';
    }
    throw Exception(_messageOf(data, 'Could not stop the spray'));
  }

  Future<List<SprayPrescriptionSummary>> fetchHistory({String? sessionId}) async {
    final response = await _guard(
      () async => _dio.get(
        '${ApiConfig.baseUrl()}/api/spray/prescriptions',
        queryParameters: {
          if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return ((data['prescriptions'] as List?) ?? const [])
          .map((e) =>
              SprayPrescriptionSummary.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    throw Exception(_messageOf(data, 'Could not load spray history'));
  }

  /// Re-open a past prescription with all of its patches and options.
  Future<SprayPrescription> fetchPrescription(int prescriptionId) async {
    final response = await _guard(
      () async => _dio.get(
        '${ApiConfig.baseUrl()}/api/spray/prescriptions/$prescriptionId',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 &&
        data is Map<String, dynamic> &&
        data['prescription'] is Map) {
      final row = Map<String, dynamic>.from(data['prescription'] as Map);
      final detail = Map<String, dynamic>.from((row['detail'] as Map?) ?? {});
      // The stored detail is the full prescription payload; keep its id so the
      // plan/execute calls have something to address.
      detail['prescription_id'] = row['id'];
      return SprayPrescription.fromJson(detail);
    }
    throw Exception(_messageOf(data, 'Could not open that prescription'));
  }

  String _messageOf(dynamic data, String fallback) {
    if (data is Map) {
      final message = data['message'] ?? data['msg'];
      if (message != null) return message.toString();
    }
    return fallback;
  }
}
