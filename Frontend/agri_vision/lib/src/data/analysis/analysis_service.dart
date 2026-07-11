import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../domain/entity/analysis_result.dart';
import '../../domain/entity/media_file.dart';

/// Talks to the Flask multispectral analysis endpoints.
///
/// Since there is no drone yet, the flow is: the user picks band images from
/// their system, we POST them as multipart to `/api/preprocessing/analyze-images`,
/// and the backend returns the field report, risk zones and action plan.
class AnalysisService {
  AnalysisService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              // Multispectral processing can take a few seconds server-side.
              receiveTimeout: const Duration(seconds: 120),
              sendTimeout: const Duration(seconds: 120),
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  final Dio _dio;

  /// Same override strategy as [AuthService] so a physical device can reach a
  /// LAN backend: `--dart-define=API_BASE_URL=http://192.168.x.x:5000`.
  static const String _baseUrlOverride = String.fromEnvironment('API_BASE_URL');

  String _baseUrl() {
    if (_baseUrlOverride.isNotEmpty) return _baseUrlOverride;
    if (kIsWeb) return 'http://127.0.0.1:5000';
    if (Platform.isAndroid) return 'http://10.0.2.2:5000';
    return 'http://127.0.0.1:5000';
  }

  /// Upload band images and run the full analysis.
  ///
  /// [images]      one file per band (named so the backend can auto-detect, e.g.
  ///               `*_nir.tif`) — or pass [bandMap] to map bands explicitly.
  /// [calibrate]   when true, [panelImages] are used for reflectance calibration.
  Future<AnalysisResult> analyzeImages({
    required List<MediaFile> images,
    bool calibrate = false,
    List<MediaFile> panelImages = const [],
    List<String>? indices,
    String? primaryIndex,
    Map<String, String>? bandMap,
  }) async {
    if (images.isEmpty) {
      throw Exception('Select at least one image to analyze.');
    }

    final form = FormData();

    // Attach each band image. The backend treats any non-"panel" part as a
    // scene band, so the field name just needs to be stable and unique.
    for (final img in images) {
      form.files.add(
        MapEntry(
          'images[]',
          MultipartFile.fromBytes(
            img.bytes,
            filename: img.name,
            contentType: img.mimeType != null
                ? DioMediaType.parse(img.mimeType!)
                : null,
          ),
        ),
      );
    }

    if (calibrate) {
      form.fields.add(const MapEntry('calibrate', 'true'));
      for (final p in panelImages) {
        form.files.add(
          MapEntry(
            'panel[]',
            MultipartFile.fromBytes(
              p.bytes,
              filename: 'panel_${p.name}',
              contentType: p.mimeType != null
                  ? DioMediaType.parse(p.mimeType!)
                  : null,
            ),
          ),
        );
      }
    }

    if (indices != null && indices.isNotEmpty) {
      form.fields.add(MapEntry('indices', _jsonList(indices)));
    }
    if (primaryIndex != null) {
      form.fields.add(MapEntry('primary_index', primaryIndex));
    }
    if (bandMap != null && bandMap.isNotEmpty) {
      form.fields.add(MapEntry('band_map', _jsonMap(bandMap)));
    }

    final response = await _dio.post(
      '${_baseUrl()}/api/preprocessing/analyze-images',
      data: form,
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return AnalysisResult.fromJson(data);
    }

    throw Exception(
      (data is Map && data['message'] != null)
          ? data['message'].toString()
          : 'Analysis failed (HTTP ${response.statusCode}).',
    );
  }

  String _jsonList(List<String> items) =>
      '[${items.map((e) => '"$e"').join(',')}]';

  String _jsonMap(Map<String, String> map) =>
      '{${map.entries.map((e) => '"${e.key}":"${e.value}"').join(',')}}';
}
