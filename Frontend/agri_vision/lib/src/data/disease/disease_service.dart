import 'package:dio/dio.dart';

import '../../core/networks/api_config.dart';
import '../../domain/entity/disease_result.dart';
import '../../domain/entity/disease_scan_entity.dart';
import '../../domain/entity/media_file.dart';

/// Talks to the Flask plant-disease identification endpoint.
///
/// The flow is: the user takes or picks one photo of a plant leaf, we POST it
/// as multipart to `/api/disease/identify`, and the backend returns the
/// identified condition plus its treatment/solution plan.
///
/// Base URL + auth header come from [ApiConfig] so the override story stays
/// consistent with the rest of the app:
///   flutter run --dart-define=API_BASE_URL=http://192.168.x.x:5000
class DiseaseService {
  DiseaseService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            ApiConfig.options(
              // Give the on-device image analysis some head-room server-side.
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 60),
            ),
          );

  final Dio _dio;

  /// Upload a single leaf photo and identify the disease.
  ///
  /// The backend records every scan, so [fieldName] — when the operator knows
  /// which block they are standing in — is what makes the history searchable
  /// later rather than a pile of undated photos.
  Future<DiseaseResult> identify(MediaFile image, {String? fieldName}) async {
    final headers = await ApiConfig.authHeaders();

    final form = FormData();
    if (fieldName != null && fieldName.trim().isNotEmpty) {
      form.fields.add(MapEntry('field_name', fieldName.trim()));
    }
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

    final response = await _dio.post(
      '${ApiConfig.baseUrl()}/api/disease/identify',
      data: form,
      options: Options(headers: headers),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return DiseaseResult.fromJson(data);
    }

    throw Exception(
      (data is Map && data['message'] != null)
          ? data['message'].toString()
          : 'Identification failed (HTTP ${response.statusCode}).',
    );
  }

  /// Past scans, newest first — the Disease tab's history list.
  Future<List<DiseaseScanEntity>> fetchScans() async {
    final response = await _dio.get(
      '${ApiConfig.baseUrl()}/api/disease/scans',
      options: Options(headers: await ApiConfig.authHeaders()),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return DiseaseScanEntity.fromJsonList((data['scans'] as List?) ?? const []);
    }
    throw Exception(_messageOf(data, 'Could not load scan history'));
  }

  /// Re-open a past scan with the full diagnosis it produced.
  Future<DiseaseResult> fetchScan(int scanId) async {
    final response = await _dio.get(
      '${ApiConfig.baseUrl()}/api/disease/scans/$scanId',
      options: Options(headers: await ApiConfig.authHeaders()),
    );

    final data = response.data;
    if (response.statusCode == 200 &&
        data is Map<String, dynamic> &&
        data['scan'] is Map &&
        (data['scan'] as Map)['detail'] is Map) {
      return DiseaseResult.fromJson(
        Map<String, dynamic>.from((data['scan'] as Map)['detail'] as Map),
      );
    }
    throw Exception(_messageOf(data, 'Could not open that scan'));
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
