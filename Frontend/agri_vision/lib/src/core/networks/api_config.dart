import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/strorage_constants.dart';

/// Single source of truth for reaching the Flask backend.
///
/// The backend address lives in exactly one place — `BASE_URL` in
/// `assets/.env` (loaded at startup in [bootstrap]). Every data service, plus
/// the auth and analysis services, resolves its base URL from here, so there is
/// only ever one value to change when the server moves.
///
/// For a one-off run you can still override it without editing the file:
///   flutter run --dart-define=API_BASE_URL=http://192.168.x.x:5000
class ApiConfig {
  ApiConfig._();

  /// Optional per-run override; when empty the value comes from `assets/.env`.
  static const String _baseUrlOverride = String.fromEnvironment('API_BASE_URL');

  /// The Flask backend base URL, e.g. `http://192.168.31.90:5000`.
  static String baseUrl() {
    if (_baseUrlOverride.isNotEmpty) return _baseUrlOverride;
    return dotenv.get('BASE_URL', fallback: 'http://127.0.0.1:5000');
  }

  /// Authorization header for the signed-in user; empty when anonymous so
  /// requests still work against the jwt-optional endpoints.
  static Future<Map<String, dynamic>> authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(StorageConstants.bearerToken);
    if (token == null || token.isEmpty) return {};
    return {'Authorization': 'Bearer $token'};
  }

  /// Shared timeouts so an offline device fails fast (and the error/empty
  /// states — including the Drone Runner button — actually appear) instead of
  /// hanging on a connection attempt for minutes.
  static BaseOptions options({
    Duration receiveTimeout = const Duration(seconds: 20),
    Duration sendTimeout = const Duration(seconds: 20),
  }) {
    return BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      // Accept every status code and let each service read the body.
      //
      // Rejecting 5xx here turned them into transport exceptions, so the
      // server's explanation was thrown away and replaced with a generic
      // "Network error — please try again". That hid exactly the messages
      // worth reading: a MAVLink connect failure answers 502 with "Nothing is
      // listening at tcp:127.0.0.1:5762 …", which tells the operator what to
      // do; "Network error" tells them nothing.
      validateStatus: (status) => status != null,
    );
  }

  /// A short, human-readable message for a transport-level failure.
  static String friendlyDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return 'No connection to the server.\nCheck Wi-Fi and that the backend is running.';
      case DioExceptionType.badCertificate:
        return 'Secure connection failed.';
      case DioExceptionType.cancel:
        return 'Request cancelled.';
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return 'Network error — please try again.';
    }
  }
}
