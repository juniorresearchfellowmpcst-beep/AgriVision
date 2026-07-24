import 'package:dio/dio.dart';

import '../../core/networks/api_config.dart';
import '../../domain/entity/disease_result.dart';
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
  Future<DiseaseResult> identify(MediaFile image) async {
    final headers = await ApiConfig.authHeaders();

    final form = FormData();
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
}
