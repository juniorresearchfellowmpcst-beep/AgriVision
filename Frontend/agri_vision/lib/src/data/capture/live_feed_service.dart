import 'package:dio/dio.dart';

import '../../core/networks/api_config.dart';
import '../../domain/entity/live_feed_entity.dart';

/// The live half of `/api/capture`: watching a drone camera, and scanning what
/// it sees while the aircraft is still flying.
///
/// Two very different transports live behind this one class, and the split is
/// deliberate:
///
///   * the **video** is a URL, not a method — [streamUrl] hands a string to
///     [MjpegView], which owns the socket for as long as it is on screen.
///     Pulling video through a Future would mean buffering a stream that never
///     ends.
///   * the **analysis** is ordinary request/response. The backend samples the
///     feed on its own timer, so the app polls a readout rather than driving
///     the scanning itself — which means the analysis keeps running when the
///     operator switches away from the video to look at the map.
class LiveFeedService {
  LiveFeedService({Dio? dio})
    : _dio = dio ?? Dio(ApiConfig.options());

  final Dio _dio;

  // ── video ──────────────────────────────────────────────────────────────

  /// The MJPEG relay URL for a camera.
  ///
  /// [fps] and [width] are what the phone asks the *server* to send, so a
  /// handset on a weak link can ask for less rather than falling behind. They
  /// cost the camera nothing — it runs at its own rate regardless.
  static String streamUrl(
    int cameraId, {
    int fps = 12,
    int width = 960,
    int quality = 75,
  }) =>
      '${ApiConfig.baseUrl()}/api/capture/cameras/$cameraId/stream'
      '?fps=$fps&width=$width&quality=$quality';

  /// Single newest frame — a thumbnail, or the browser fallback.
  static String frameUrl(int cameraId, {int width = 640, int quality = 70}) =>
      '${ApiConfig.baseUrl()}/api/capture/cameras/$cameraId/frame'
      '?width=$width&quality=$quality';

  /// State of every feed the server currently holds open.
  Future<List<LiveStreamStatus>> fetchStreams() async {
    final response = await _guard(
      () async => _dio.get(
        '${ApiConfig.baseUrl()}/api/capture/live',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return ((data['streams'] as List?) ?? const [])
          .map(
            (e) => LiveStreamStatus.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    }
    throw Exception(_messageOf(data, 'Could not read the feed status'));
  }

  /// Drop the server's session with a camera immediately.
  ///
  /// Not usually needed — a feed nobody is watching releases itself — but it
  /// is the way to force a reconnect after the camera has been power-cycled.
  Future<void> closeStream(int cameraId) async {
    await _guard(
      () async => _dio.delete(
        '${ApiConfig.baseUrl()}/api/capture/cameras/$cameraId/stream',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );
  }

  // ── analysis ───────────────────────────────────────────────────────────

  /// Start scanning the live feed for weeds and disease.
  ///
  /// [intervalS] is how often a frame is taken *for scanning* — nothing to do
  /// with the video's frame rate. Slower is usually better: at survey speed
  /// the aircraft needs a few seconds to cover new ground, so a faster
  /// interval mostly re-scans the same patch.
  Future<LiveAnalysis> startAnalysis(
    int cameraId, {
    String? crop,
    String? fieldName,
    double intervalS = 3,
    int window = 40,
  }) async {
    final response = await _guard(
      () async => _dio.post(
        '${ApiConfig.baseUrl()}/api/capture/cameras/$cameraId/analyze',
        data: {
          if (crop != null && crop.isNotEmpty) 'crop': crop,
          if (fieldName != null && fieldName.isNotEmpty) 'field_name': fieldName,
          'interval_s': intervalS,
          'window': window,
        },
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return LiveAnalysis.fromJson(
        Map<String, dynamic>.from(data['analysis'] as Map),
      );
    }
    throw Exception(_messageOf(data, 'Could not start the live scan'));
  }

  /// The current readout, or null when nothing is scanning this camera.
  ///
  /// "Nothing is running" is a normal answer, not a failure — the page asks
  /// on open, before the operator has started anything.
  Future<LiveAnalysis?> fetchAnalysis(int cameraId) async {
    final response = await _guard(
      () async => _dio.get(
        '${ApiConfig.baseUrl()}/api/capture/cameras/$cameraId/analyze',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      final analysis = data['analysis'];
      if (analysis is Map) {
        return LiveAnalysis.fromJson(Map<String, dynamic>.from(analysis));
      }
      return null;
    }
    throw Exception(_messageOf(data, 'Could not read the live scan'));
  }

  Future<void> stopAnalysis(int cameraId) async {
    final response = await _guard(
      () async => _dio.delete(
        '${ApiConfig.baseUrl()}/api/capture/cameras/$cameraId/analyze',
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );
    // 404 means it had already stopped, which is the state being asked for.
    if (response.statusCode != 200 && response.statusCode != 404) {
      throw Exception(_messageOf(response.data, 'Could not stop the live scan'));
    }
  }

  /// The trail of recent samples behind the current reading.
  Future<List<LiveScan>> fetchRecentScans(int cameraId, {int limit = 20}) async {
    final response = await _guard(
      () async => _dio.get(
        '${ApiConfig.baseUrl()}/api/capture/cameras/$cameraId/analyze/frames',
        queryParameters: {'limit': limit},
        options: Options(headers: await ApiConfig.authHeaders()),
      ),
    );

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      return ((data['frames'] as List?) ?? const [])
          .map((e) => LiveScan.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    throw Exception(_messageOf(data, 'Could not read recent scans'));
  }

  /// Does this backend support the live relay at all?
  ///
  /// An older server has the camera registry but no video, and a build that
  /// assumed otherwise would show a pane that can never fill.
  Future<bool> supportsLiveVideo() async {
    try {
      final response = await _dio.get(
        '${ApiConfig.baseUrl()}/api/capture/health',
        options: Options(headers: await ApiConfig.authHeaders()),
      );
      final data = response.data;
      if (data is Map && data['live'] is Map) {
        return (data['live'] as Map)['supported'] == true;
      }
    } catch (_) {
      // Unreachable server: the page's own error state covers it.
    }
    return false;
  }

  Future<Response> _guard(Future<Response> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw Exception(ApiConfig.friendlyDioError(e));
    }
  }

  String _messageOf(dynamic data, String fallback) {
    if (data is Map) {
      final message = data['message'] ?? data['msg'];
      if (message != null) return message.toString();
    }
    return fallback;
  }
}
