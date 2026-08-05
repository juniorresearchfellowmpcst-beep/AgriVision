import 'package:dio/dio.dart';

import '../../core/networks/api_config.dart';
import '../../domain/entity/field_scan_result.dart';
import '../../domain/entity/media_file.dart';

/// Talks to the Flask weed + disease field-scan endpoints (`/api/fieldscan`).
///
/// Two ways in, one engine behind them: [analyze] scans a single canopy frame
/// the phone already holds, and [scanSession] scans every RGB frame a low-pace
/// mission recorded and rolls them up into one answer about the field. The
/// second is what the feature is really for — one frame is an anecdote.
class FieldScanService {
  FieldScanService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            ApiConfig.options(
              // Scanning a whole pass runs the detector over dozens of frames.
              receiveTimeout: const Duration(seconds: 120),
              sendTimeout: const Duration(seconds: 120),
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

  /// The crops the scanner knows — MP's main cropping system.
  Future<List<CropOption>> fetchCrops() async {
    final response = await _guard(
      () async => _dio.get('${ApiConfig.baseUrl()}/api/fieldscan/catalog'),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return ((data['crops'] as List?) ?? const [])
          .map((e) => CropOption.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    throw Exception(_messageOf(data, 'Could not load the crop list'));
  }

  /// Which engine is answering — `model` once a trained CNN is configured on
  /// the server, `heuristic` otherwise. Shown so a result can be read for
  /// what it is.
  Future<Map<String, String>> fetchEngines() async {
    final response = await _guard(
      () async => _dio.get('${ApiConfig.baseUrl()}/api/fieldscan/health'),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      final engines = (data['engines'] as Map?) ?? const {};
      return engines.map((key, value) => MapEntry('$key', '$value'));
    }
    return const {};
  }

  /// Scan one canopy frame for weeds and disease.
  Future<FieldScanResult> analyze(
    MediaFile image, {
    String? crop,
    String? fieldName,
    double? lat,
    double? lon,
  }) async {
    final form = FormData();
    if (crop != null && crop.isNotEmpty) {
      form.fields.add(MapEntry('crop', crop));
    }
    if (fieldName != null && fieldName.isNotEmpty) {
      form.fields.add(MapEntry('field_name', fieldName));
    }
    if (lat != null) form.fields.add(MapEntry('lat', '$lat'));
    if (lon != null) form.fields.add(MapEntry('lon', '$lon'));

    form.files.add(
      MapEntry(
        'image',
        MultipartFile.fromBytes(
          image.bytes,
          filename: image.name,
          contentType: image.mimeType != null
              ? DioMediaType.parse(image.mimeType!)
              : null,
        ),
      ),
    );

    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/fieldscan/analyze',
        data: form,
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return FieldScanResult.fromJson(data);
    }
    throw Exception(_messageOf(data, 'Could not scan that frame'));
  }

  /// Scan every RGB frame from a capture session and summarise the field.
  Future<({FieldScanSummary summary, List<FieldScanResult> frames})> scanSession({
    required String sessionId,
    String? crop,
    int? limit,
  }) async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/fieldscan/session',
        data: {
          'session_id': sessionId,
          if (crop != null && crop.isNotEmpty) 'crop': crop,
          if (limit != null) 'limit': limit,
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return (
        summary: FieldScanSummary.fromJson(
          Map<String, dynamic>.from((data['summary'] as Map?) ?? {}),
          sessionId: sessionId,
        ),
        frames: ((data['frames'] as List?) ?? const [])
            .map((e) => FieldScanResult.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
    }
    throw Exception(_messageOf(data, 'Could not scan that pass'));
  }

  /// Re-derive a pass's summary from the scans already recorded — cheap,
  /// because it reads stored verdicts rather than re-running the detector.
  Future<FieldScanSummary> fetchSummary(String sessionId) async {
    final response = await _guard(
      () async => _dio.get(
        '${ApiConfig.baseUrl()}/api/fieldscan/summary',
        queryParameters: {'session_id': sessionId},
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return FieldScanSummary.fromJson(
        Map<String, dynamic>.from((data['summary'] as Map?) ?? {}),
        sessionId: sessionId,
      );
    }
    throw Exception(_messageOf(data, 'Could not load that pass'));
  }

  String _messageOf(dynamic data, String fallback) {
    if (data is Map) {
      final message = data['message'] ?? data['msg'];
      if (message != null) return message.toString();
    }
    return fallback;
  }
}
