import 'package:dio/dio.dart';

import '../../core/networks/api_config.dart';
import '../../domain/entity/crop_catalog.dart';
import '../../domain/entity/media_file.dart';

/// The crop catalogue and the phone-camera scan (`/api/crops`).
///
/// This is the drone-free half of the app: no aircraft, no session, no
/// prescription. A farmer picks their crop, points their phone at a plant, and
/// gets a diagnosis with an actual product behind it.
class CropCatalogService {
  CropCatalogService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            ApiConfig.options(
              // A phone photo goes through the same detectors as a drone frame.
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 60),
            ),
          );

  final Dio _dio;

  String get _base => '${ApiConfig.baseUrl()}/api/crops';

  Future<Response> _guard(Future<Response> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw Exception(ApiConfig.friendlyDioError(e));
    }
  }

  /// The picker grid: every crop, plus the Weeds tile.
  ///
  /// [month] marks and sorts by what is in the ground now. Passing the current
  /// month is not a nicety — in August a farmer in MP is looking at soybean and
  /// paddy, and making them scroll past wheat every time is a small daily tax.
  Future<({List<CropCatalogItem> crops, CropCatalogItem weeds})> fetchCatalog({
    int? month,
  }) async {
    final response = await _guard(
      () async => _dio.get(
        _base,
        queryParameters: {if (month != null) 'month': month},
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      final crops = ((data['crops'] as List?) ?? const [])
          .map((e) => CropCatalogItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final weeds = CropCatalogItem.fromJson(
        ((data['weeds_option'] as Map?) ?? const {}).cast<String, dynamic>(),
      );
      return (crops: crops, weeds: weeds);
    }
    throw Exception(_messageOf(data, 'Could not load the crop list'));
  }

  /// One crop: every disease it gets here, each with its treatment.
  Future<CropDetail> fetchCrop(String cropId) async {
    final response = await _guard(() async => _dio.get('$_base/$cropId'));

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return CropDetail.fromJson(data);
    }
    throw Exception(_messageOf(data, 'Could not open that crop'));
  }

  /// The weeds, narrowed to one crop's usual suspects when given.
  Future<CropDetail> fetchWeeds({String? cropId}) async {
    final response = await _guard(
      () async => _dio.get(
        '$_base/weeds',
        queryParameters: {if (cropId != null && cropId.isNotEmpty) 'crop': cropId},
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return CropDetail.fromJson(data);
    }
    throw Exception(_messageOf(data, 'Could not load the weed list'));
  }

  /// Scan a photo taken with the phone.
  ///
  /// [crop] is asked for first and passed here rather than inferred, because
  /// the crop is part of the diagnosis: the same yellowing is yellow rust in
  /// wheat and yellow mosaic in soybean.
  Future<CropScanResult> scan(
    MediaFile image, {
    String? crop,
    ScanMode mode = ScanMode.both,
    String? fieldName,
    double? lat,
    double? lon,
  }) async {
    final form = FormData();
    if (crop != null && crop.isNotEmpty) {
      form.fields.add(MapEntry('crop', crop));
    }
    form.fields.add(MapEntry('mode', mode.id));
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
        '$_base/scan',
        data: form,
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return CropScanResult.fromJson(data);
    }
    throw Exception(_messageOf(data, 'Could not scan that photo'));
  }

  String _messageOf(dynamic data, String fallback) {
    if (data is Map && data['message'] != null) return '${data['message']}';
    return fallback;
  }
}
