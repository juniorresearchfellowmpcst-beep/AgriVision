import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/strorage_constants.dart';

/// Single source of truth for reaching the Flask backend.
///
/// Every data service resolves its base URL and auth header from here so the
/// override story stays consistent across the app:
///   flutter run --dart-define=API_BASE_URL=http://192.168.x.x:5000
class ApiConfig {
  ApiConfig._();

  static const String _baseUrlOverride = String.fromEnvironment('API_BASE_URL');

  /// Same defaults as [AuthService]/[AnalysisService]: web + desktop hit
  /// localhost, a physical Android device needs the LAN IP override.
  static String baseUrl() {
    if (_baseUrlOverride.isNotEmpty) return _baseUrlOverride;
    if (kIsWeb) return 'http://127.0.0.1:5000';
    if (Platform.isAndroid) return 'http://192.168.1.5:5000';
    return 'http://127.0.0.1:5000';
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
      validateStatus: (status) => status != null && status < 500,
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
