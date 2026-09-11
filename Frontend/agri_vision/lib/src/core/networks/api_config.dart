import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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

  /// The deployed backend: what a released app talks to unless told otherwise.
  static const String productionBaseUrl =
      'https://agrivision-production-ae8e.up.railway.app';

  /// The Flask backend base URL, e.g. `http://192.168.31.90:5000`.
  ///
  /// A release build refuses a device-local address and uses
  /// [productionBaseUrl] instead. `assets/.env` is bundled into the app, so
  /// whatever a developer last pointed it at ships with it -- and on a phone
  /// `127.0.0.1` is the phone itself, while `10.0.2.2` exists only inside the
  /// emulator. Either would make every screen of a store build fail with a
  /// connection error. A LAN address such as `192.168.x.x` is still allowed:
  /// a ground station on the field's own network is a real release setup.
  static String baseUrl() {
    if (_baseUrlOverride.isNotEmpty) return _baseUrlOverride;
    final configured = dotenv.get(
      'BASE_URL',
      fallback: 'http://127.0.0.1:5000',
    );
    if (kReleaseMode && isDeviceLocal(configured)) return productionBaseUrl;
    return configured;
  }

  /// Whether [url] points at this device, or at an emulator's alias for its
  /// host, rather than at a machine a real phone can reach.
  @visibleForTesting
  static bool isDeviceLocal(String url) {
    final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
    return host.isEmpty ||
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '0.0.0.0' ||
        host == '::1' ||
        host == '10.0.2.2';
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
