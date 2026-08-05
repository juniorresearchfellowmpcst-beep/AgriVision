import 'package:dio/dio.dart';

import '../../core/networks/api_config.dart';
import '../../domain/entity/capture_entity.dart';
import '../../domain/entity/media_file.dart';

/// Talks to the Flask camera-capture endpoints (`/api/capture`).
///
/// The backend, not the phone, holds the camera connections: a drone's IP
/// cameras live on the aircraft's own network, which the operator's handset
/// may not even be on. So "capture" is a request the server carries out on
/// every registered feed at once, and what comes back are stored, geotagged
/// frames the prescription and field-scan endpoints can then read.
class CaptureService {
  CaptureService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            ApiConfig.options(
              // A shot opens several RTSP streams; the server bounds itself,
              // but give it room to answer rather than timing out mid-grab.
              receiveTimeout: const Duration(seconds: 45),
              sendTimeout: const Duration(seconds: 45),
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

  // ── camera registry ─────────────────────────────────────────────────────

  Future<CameraRegistry> fetchCameras() async {
    final response = await _guard(
      () async => _dio.get(
        '${ApiConfig.baseUrl()}/api/capture/cameras',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return CameraRegistry.fromJson(data);
    }
    throw Exception(_messageOf(data, 'Could not load the camera list'));
  }

  Future<CameraFeed> addCamera({
    required String name,
    required String role,
    required String url,
    String? band,
    double? fovDeg,
  }) async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/capture/cameras',
        data: {
          'name': name,
          'role': role,
          'url': url,
          if (band != null && band.isNotEmpty) 'band': band,
          if (fovDeg != null) 'fov_deg': fovDeg,
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 201 && data is Map<String, dynamic>) {
      return CameraFeed.fromJson(
        Map<String, dynamic>.from(data['camera'] as Map),
      );
    }
    throw Exception(_messageOf(data, 'Could not add the camera'));
  }

  Future<void> deleteCamera(int cameraId) async {
    final response = await _guard(
      () async => _dio.delete(
        '${ApiConfig.baseUrl()}/api/capture/cameras/$cameraId',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );
    if (response.statusCode != 200) {
      throw Exception(_messageOf(response.data, 'Could not remove the camera'));
    }
  }

  /// Is this feed live? Answers either way — an unreachable camera is
  /// information the settings sheet needs to show, not an error to swallow.
  Future<CameraProbe> testCamera({int? cameraId, String? url}) async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/capture/cameras/test',
        data: {
          if (cameraId != null) 'camera_id': cameraId,
          if (url != null && url.isNotEmpty) 'url': url,
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return CameraProbe.fromJson(data);
    }
    throw Exception(_messageOf(data, 'Could not test that feed'));
  }

  // ── capture ─────────────────────────────────────────────────────────────

  /// Trigger every enabled camera once. All feeds are pulled in parallel
  /// server-side so the bands of one shot describe the same patch of ground.
  Future<CaptureShot> shoot({
    String? sessionId,
    String? fieldName,
    List<int>? cameraIds,
  }) async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/capture/shoot',
        data: {
          if (sessionId != null) 'session_id': sessionId,
          if (fieldName != null && fieldName.isNotEmpty) 'field_name': fieldName,
          if (cameraIds != null && cameraIds.isNotEmpty) 'camera_ids': cameraIds,
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return CaptureShot.fromJson(data);
    }
    throw Exception(_messageOf(data, 'Could not capture from the cameras'));
  }

  /// Store frames the phone already holds as if they had been captured.
  ///
  /// The path for a rig that records to a card instead of streaming, and for
  /// trying the whole prescription chain with no cameras attached. [bands]
  /// maps a band name (or `rgb`) to the file.
  Future<CaptureShot> uploadFrames({
    required Map<String, MediaFile> bands,
    String? sessionId,
    String? fieldName,
    double? lat,
    double? lon,
    double? altM,
    double? headingDeg,
  }) async {
    final form = FormData();
    if (sessionId != null && sessionId.isNotEmpty) {
      form.fields.add(MapEntry('session_id', sessionId));
    }
    if (fieldName != null && fieldName.isNotEmpty) {
      form.fields.add(MapEntry('field_name', fieldName));
    }
    if (lat != null) form.fields.add(MapEntry('lat', '$lat'));
    if (lon != null) form.fields.add(MapEntry('lon', '$lon'));
    if (altM != null) form.fields.add(MapEntry('alt_m', '$altM'));
    if (headingDeg != null) {
      form.fields.add(MapEntry('heading_deg', '$headingDeg'));
    }

    bands.forEach((band, file) {
      form.files.add(
        MapEntry(
          // The *field name* is the band — that is how the backend knows
          // which image is the NIR one.
          band,
          MultipartFile.fromBytes(
            file.bytes,
            filename: file.name,
            contentType: file.mimeType != null
                ? DioMediaType.parse(file.mimeType!)
                : null,
          ),
        ),
      );
    });

    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/capture/upload',
        data: form,
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return CaptureShot.fromJson(data);
    }
    throw Exception(_messageOf(data, 'Could not store those frames'));
  }

  // ── history ─────────────────────────────────────────────────────────────

  Future<List<CaptureSession>> fetchSessions() async {
    final response = await _guard(
      () async => _dio.get(
        '${ApiConfig.baseUrl()}/api/capture/sessions',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return ((data['sessions'] as List?) ?? const [])
          .map((e) => CaptureSession.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    throw Exception(_messageOf(data, 'Could not load capture history'));
  }

  Future<List<CaptureShot>> fetchShots({String? sessionId}) async {
    final response = await _guard(
      () async => _dio.get(
        '${ApiConfig.baseUrl()}/api/capture/frames',
        queryParameters: {
          if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return ((data['shots'] as List?) ?? const [])
          .map((e) => CaptureShot.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    throw Exception(_messageOf(data, 'Could not load captured frames'));
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
