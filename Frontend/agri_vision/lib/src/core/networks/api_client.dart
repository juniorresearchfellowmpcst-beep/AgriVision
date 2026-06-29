import 'package:agri_vision/src/core/constants/strorage_constants.dart';
import 'package:agri_vision/src/core/core.dart';
import 'package:agri_vision/src/data/data.dart';
import 'package:agri_vision/src/domain/entity/media_file.dart';
import 'package:agri_vision/src/ui/handler/exception_handler.dart';
import 'package:dio/dio.dart';

class ApiClient {
  final Dio _dio;
  final Storage _storage;
  final void Function()? onUnauthorized;

  ApiClient({
    required String baseUrl,
    required Storage storage,
    this.onUnauthorized,
  }) : _dio = Dio(
         BaseOptions(
           baseUrl: baseUrl,
           validateStatus: (status) {
             return status != 401;
           },
         ),
       ),
       _storage = storage {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: StorageConstants.bearerToken);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          // Logger.i(
          //   '[REQUEST][${options.method}] ${options.uri} | Headers: ${options.headers} ${options.queryParameters.isNotEmpty ? '| Query: ${options.queryParameters}' : ''} | ${options.data != null ? '| Payload: ${options.data}' : ''}',
          // );
          Logger.i('[REQUEST][${options.method}] ${options.uri}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          // Logger.i(
          //   '[RESPONSE][${response.requestOptions.method}] ${response.requestOptions.uri} '
          //   '| Status: ${response.statusCode} | Response: ${response.data is List<int> ? '<binary data>' : response.data}',
          // );
          Logger.i(
            '[RESPONSE][${response.requestOptions.method}] ${response.requestOptions.uri} | Status: ${response.statusCode}',
          );
          return handler.next(response);
        },
        onError: (DioException e, handler) {
          final res = e.response;

          // ------------- HANDLE 401 HERE -------------
          if (res != null && res.statusCode == 401) {
            ExceptionHandler.handle(e);
            return handler.next(e);
          }

          // ------------- HANDLE ALL OTHER SERVER ERRORS AS SUCCESS -------------
          if (res != null) {
            return handler.resolve(res);
          }

          // Network or timeout errors (no response)
          ExceptionHandler.handle(e);
          return handler.next(e);
        },
      ),
    );
  }

  /// GET request
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
  }) async {
    return await _dio.get(
      path,
      queryParameters: queryParameters,
      options: Options(headers: headers),
    );
  }

  /// GET request for downloading binary files (images, videos, etc.)
  Future<Response> downloadFile(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    void Function(int, int)? onReceiveProgress,
  }) async {
    return await _dio.get(
      path,
      queryParameters: queryParameters,
      options: Options(
        headers: headers,
        responseType: ResponseType.bytes,
        followRedirects: true,
        validateStatus: (status) => status! < 500,
      ),
      onReceiveProgress: onReceiveProgress,
    );
  }

  /// POST request (supports multipart if files are provided)
  Future<Response> post(
    String path, {
    Map<String, dynamic>? data,
    List<MediaFile>? files,
    String fileFieldName = 'file',
    Map<String, dynamic>? headers,
  }) async {
    dynamic payload;
    if (files != null && files.isNotEmpty) {
      payload = _buildFormDataWithFiles(data, files, fileFieldName);
    } else {
      payload = data;
    }
    return await _dio.post(
      path,
      data: payload,
      options: Options(headers: headers),
    );
  }

  /// PUT request (supports multipart if files are provided)
  Future<Response> put(
    String path, {
    Map<String, dynamic>? data,
    List<MediaFile>? files,
    String fileFieldName = 'file',
    Map<String, dynamic>? headers,
  }) async {
    dynamic payload;
    if (files != null && files.isNotEmpty) {
      payload = _buildFormDataWithFiles(data, files, fileFieldName);
    } else {
      payload = data;
    }
    return await _dio.put(
      path,
      data: payload,
      options: Options(headers: headers),
    );
  }

  /// DELETE request
  Future<Response> delete(
    String path, {
    Object? data,
    Map<String, dynamic>? headers,
  }) async {
    return await _dio.delete(
      path,
      data: data,
      options: Options(headers: headers),
    );
  }

  /// Helper to build FormData (always returns FormData, with or without files)
  FormData _buildFormDataWithFiles(
    Map<String, dynamic>? data,
    List<MediaFile>? files,
    String fileFieldName,
  ) {
    final formMap = Map<String, dynamic>.from(data ?? {});

    // If files exist, attach them
    if (files != null && files.isNotEmpty) {
      if (files.length == 1) {
        final file = files.first;
        formMap[fileFieldName] = MultipartFile.fromBytes(
          file.bytes,
          filename: file.name,
          contentType: file.mimeType != null
              ? DioMediaType.parse(file.mimeType!)
              : null,
        );
      } else {
        formMap['$fileFieldName[]'] = files
            .map(
              (f) => MultipartFile.fromBytes(
                f.bytes,
                filename: f.name,
                contentType: f.mimeType != null
                    ? DioMediaType.parse(f.mimeType!)
                    : null,
              ),
            )
            .toList();
      }
    }

    // Always return FormData — even if no files
    return FormData.fromMap(formMap);
  }
}
