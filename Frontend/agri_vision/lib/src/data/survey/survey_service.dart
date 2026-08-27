import 'package:dio/dio.dart';

import '../../core/networks/api_config.dart';
import '../../domain/entity/survey_entity.dart';

/// Talks to the survey-flight endpoints (`/api/survey`).
///
/// One run is the whole flight: which cameras, which crop, what to look for,
/// what was found, and — only after two separate human confirmations — the
/// spray that follows from it. Every method here maps to one step of that,
/// and the ordering is enforced server-side rather than by the UI, so a stale
/// screen cannot skip the confirmations.
class SurveyService {
  SurveyService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            ApiConfig.options(
              // Finishing a run scans the whole pass, clusters it and renders
              // a map. On a long flight that is not a two-second request.
              receiveTimeout: const Duration(seconds: 120),
              sendTimeout: const Duration(seconds: 120),
            ),
          );

  final Dio _dio;

  String get _base => '${ApiConfig.baseUrl()}/api/survey';

  Future<Response> _guard(Future<Response> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw Exception(ApiConfig.friendlyDioError(e));
    }
  }

  /// Which camera modes this rig can actually fly, and why not otherwise.
  Future<SurveyCapabilities> fetchCapabilities() async {
    final response = await _guard(
      () async => _dio.get(
        '$_base/capabilities',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return SurveyCapabilities.fromJson(data);
    }
    throw Exception(_messageOf(data, 'Could not read the drone camera setup'));
  }

  /// Past runs, newest first.
  Future<({List<SurveyRun> runs, SurveyRun? active})> fetchRuns() async {
    final response = await _guard(
      () async => _dio.get(
        '$_base/runs',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      final runs = ((data['runs'] as List?) ?? const [])
          .map((e) => SurveyRun.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final active = (data['active'] as Map?)?.cast<String, dynamic>();
      return (
        runs: runs,
        active: active == null ? null : SurveyRun.fromJson(active),
      );
    }
    throw Exception(_messageOf(data, 'Could not load past surveys'));
  }

  /// Start a run. For the RGB modes this also starts the CNN on the live feed.
  Future<({SurveyRun run, List<String> warnings})> start({
    required CameraMode cameraMode,
    required DetectionTarget target,
    String? crop,
    String? fieldName,
    int? rgbCameraId,
  }) async {
    final response = await _guard(
      () async => _dio.post(
        '$_base/runs',
        data: {
          'camera_mode': cameraMode.id,
          'detection_target': target.id,
          if (crop != null && crop.isNotEmpty) 'crop': crop,
          if (fieldName != null && fieldName.isNotEmpty) 'field_name': fieldName,
          if (rgbCameraId != null) 'rgb_camera_id': rgbCameraId,
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return (
        run: SurveyRun.fromJson(
          (data['run'] as Map).cast<String, dynamic>(),
        ),
        warnings:
            (data['warnings'] as List?)?.map((e) => '$e').toList() ?? const [],
      );
    }
    throw Exception(_messageOf(data, 'Could not start the survey'));
  }

  /// The rolling readout while the aircraft is over the field.
  Future<({SurveyRun run, SurveyProgress progress})> status(int runId) async {
    final response = await _guard(
      () async => _dio.get(
        '$_base/runs/$runId',
        // Polled every couple of seconds; a long timeout here would stack
        // requests on a bad link instead of failing one and retrying.
        options: Options(
          headers: await ApiConfig.authHeaders(),
          receiveTimeout: const Duration(seconds: 12),
        ),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return (
        run: SurveyRun.fromJson((data['run'] as Map).cast<String, dynamic>()),
        progress: SurveyProgress.fromJson(
          (data['analysis'] as Map?)?.cast<String, dynamic>(),
          shots: int.tryParse('${data['shots']}') ?? 0,
        ),
      );
    }
    throw Exception(_messageOf(data, 'Could not read the survey'));
  }

  /// Trigger every enabled camera once, filed under this run.
  Future<String> shoot(int runId) async {
    final response = await _guard(
      () async => _dio.post(
        '$_base/runs/$runId/shoot',
        data: const {},
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return data['message']?.toString() ?? 'Captured.';
    }
    throw Exception(_messageOf(data, 'The cameras did not fire'));
  }

  /// End the pass: crop health, action plan, tank plan and treatment map.
  Future<({SurveyRun run, SurveySummary summary})> finish(int runId) async {
    final response = await _guard(
      () async => _dio.post(
        '$_base/runs/$runId/finish',
        data: const {},
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return (
        run: SurveyRun.fromJson((data['run'] as Map).cast<String, dynamic>()),
        summary: SurveySummary.fromJson(
          (data['summary'] as Map).cast<String, dynamic>(),
        ),
      );
    }
    throw Exception(_messageOf(data, 'Could not summarise the survey'));
  }

  /// Re-open a finished run without re-scanning anything.
  Future<({SurveyRun run, SurveySummary summary})> summary(int runId) async {
    final response = await _guard(
      () async => _dio.get(
        '$_base/runs/$runId/summary',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return (
        run: SurveyRun.fromJson((data['run'] as Map).cast<String, dynamic>()),
        summary: SurveySummary.fromJson(
          (data['summary'] as Map).cast<String, dynamic>(),
        ),
      );
    }
    throw Exception(_messageOf(data, 'Could not open that survey'));
  }

  /// Record the tank and the permission, then send the spray mission.
  ///
  /// The three flags are separate on purpose. `tankFilled` is a statement
  /// about the aircraft, `authorised` is a statement by the farmer, and
  /// `start` is what actually opens a valve over a field — an operator can
  /// load the plan on the ground and launch it once the field is clear.
  Future<({String message, SurveyRun run, Map<String, dynamic> detail})> authorise({
    required int runId,
    required bool tankFilled,
    required bool authorised,
    required String option,
    double? tankLitres,
    String? tankProduct,
    String? authorisedBy,
    bool start = false,
  }) async {
    final response = await _guard(
      () async => _dio.post(
        '$_base/runs/$runId/authorise',
        data: {
          'tank_filled': tankFilled,
          'spray_authorised': authorised,
          'option': option,
          'start': start,
          if (tankLitres != null) 'tank_litres': tankLitres,
          if (tankProduct != null && tankProduct.isNotEmpty)
            'tank_product': tankProduct,
          if (authorisedBy != null && authorisedBy.isNotEmpty)
            'authorised_by': authorisedBy,
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return (
        message: data['message']?.toString() ?? 'Spray mission sent.',
        run: SurveyRun.fromJson(
          ((data['run'] as Map?) ?? const {}).cast<String, dynamic>(),
        ),
        detail: data,
      );
    }
    throw Exception(_messageOf(data, 'The spray could not be authorised'));
  }

  Future<void> cancel(int runId) async {
    await _guard(
      () async => _dio.post(
        '$_base/runs/$runId/cancel',
        data: const {},
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );
  }

  /// The server's own explanation, not a generic one.
  ///
  /// These messages are the whole point of the endpoint design — "No RGB
  /// camera is registered" tells an operator what to do, and "Request failed"
  /// tells them nothing.
  String _messageOf(dynamic data, String fallback) {
    if (data is Map && data['message'] != null) return '${data['message']}';
    return fallback;
  }
}
