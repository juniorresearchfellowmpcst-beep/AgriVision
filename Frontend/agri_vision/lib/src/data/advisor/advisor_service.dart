import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/networks/api_config.dart';
import '../../domain/entity/advisor_entity.dart';
import '../../domain/entity/media_file.dart';

/// The crop advisor behind "More information" (`/api/advisor`).
///
/// Two ways to point at the picture, and the choice matters on a field
/// connection:
///
///   * [ask] with a [MediaFile] uploads the photo — right for something the
///     farmer just took on the phone;
///   * [ask] with a `frameId` / `scanId` / `runId` names something the server
///     already holds, so nothing is re-uploaded over the slowest link in the
///     chain to send back what is already at the other end of it.
class AdvisorService {
  AdvisorService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            ApiConfig.options(
              // This is the one call that leaves the ground station for the
              // internet, and a model answering a question about a photograph
              // is not instant.
              receiveTimeout: const Duration(seconds: 90),
              sendTimeout: const Duration(seconds: 90),
            ),
          );

  final Dio _dio;

  String get _base => '${ApiConfig.baseUrl()}/api/advisor';

  Future<Response> _guard(Future<Response> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw Exception(ApiConfig.friendlyDioError(e));
    }
  }

  /// Whether the advisor is configured. Checked before the button is shown.
  Future<AdvisorAvailability> availability() async {
    try {
      final response = await _dio.get('$_base/health');
      final data = response.data;
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        return AdvisorAvailability.fromJson(data);
      }
    } catch (_) {
      // An unreachable backend is not the same as an unconfigured advisor, but
      // from the button's point of view the answer is the same: do not offer
      // it. The rest of the screen still works offline.
    }
    return AdvisorAvailability.unknown;
  }

  /// Opening questions, tailored to what the scan found.
  Future<List<String>> suggestions(Map<String, dynamic>? context) async {
    try {
      final response = await _dio.post(
        '$_base/suggest',
        data: {'context': context ?? const {}},
      );
      final data = response.data;
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        return ((data['questions'] as List?) ?? const [])
            .map((e) => '$e')
            .toList();
      }
    } catch (_) {
      // Starter questions are a convenience; the box still works empty.
    }
    return const [];
  }

  /// Ask one question, optionally about one photo.
  Future<String> ask({
    required String question,
    MediaFile? image,
    Map<String, dynamic>? context,
    List<AdvisorMessage> history = const [],
    int? frameId,
    int? scanId,
    int? diseaseScanId,
    int? runId,
  }) async {
    // The whole conversation is re-sent each turn so the model can answer a
    // follow-up ("and if it rains tomorrow?"); the backend caps how far back
    // it looks, so this does not grow without bound.
    final historyJson = history
        .where((message) => !message.pending && !message.failed)
        .map((message) => message.toHistoryJson())
        .toList();

    late final Response response;

    if (image != null) {
      final form = FormData();
      form.fields.add(MapEntry('question', question));
      if (context != null && context.isNotEmpty) {
        // Multipart cannot nest, so the diagnosis and the history travel as
        // JSON strings.
        form.fields.add(MapEntry('context', jsonEncode(context)));
      }
      if (historyJson.isNotEmpty) {
        form.fields.add(MapEntry('history', jsonEncode(historyJson)));
      }
      if (frameId != null) form.fields.add(MapEntry('frame_id', '$frameId'));
      if (scanId != null) form.fields.add(MapEntry('scan_id', '$scanId'));
      if (diseaseScanId != null) {
        form.fields.add(MapEntry('disease_scan_id', '$diseaseScanId'));
      }
      if (runId != null) form.fields.add(MapEntry('run_id', '$runId'));

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

      response = await _guard(
        () async => _dio.post(
          '$_base/ask',
          data: form,
          options: Options(headers: await ApiConfig.authHeaders()),
        ),
      );
    } else {
      response = await _guard(
        () async => _dio.post(
          '$_base/ask',
          data: {
            'question': question,
            if (context != null && context.isNotEmpty) 'context': context,
            if (historyJson.isNotEmpty) 'history': historyJson,
            if (frameId != null) 'frame_id': frameId,
            if (scanId != null) 'scan_id': scanId,
            if (diseaseScanId != null) 'disease_scan_id': diseaseScanId,
            if (runId != null) 'run_id': runId,
          },
          options: Options(headers: await ApiConfig.authHeaders()),
        ),
      );
    }

    final data = response.data;
    if (response.statusCode == 200 && data is Map<String, dynamic>) {
      final answer = data['answer']?.toString() ?? '';
      if (answer.isEmpty) {
        throw Exception('The advisor sent back an empty answer.');
      }
      return answer;
    }
    // The server's own message is what an operator can act on — "the ground
    // station has no internet" beats "request failed".
    if (data is Map && data['message'] != null) {
      throw Exception('${data['message']}');
    }
    throw Exception('The advisor could not answer that.');
  }
}
