import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/strorage_constants.dart';

class AuthService {
  AuthService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  final Dio _dio;

  /// Override at build/run time for a physical device, e.g.:
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.31.90:5000
  /// Without an override, defaults only work for local emulators/web:
  ///   - Android emulator loopback alias: 10.0.2.2
  ///   - iOS simulator / web: 127.0.0.1
  /// Neither default is reachable from a real phone.
  static const String _baseUrlOverride = String.fromEnvironment('API_BASE_URL');

  String _baseUrl() {
    if (_baseUrlOverride.isNotEmpty) {
      return _baseUrlOverride;
    }

    if (kIsWeb) {
      return 'http://127.0.0.1:5000';
    }

    if (Platform.isAndroid) {
      return 'http://192.168.31.90:5000';
    }

    return 'http://127.0.0.1:5000';
  }

  Future<Map<String, dynamic>> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post(
      '${_baseUrl()}/api/auth/signin',
      data: {'email': email.trim(), 'password': password},
    );

    if (response.statusCode == 200) {
      final data = response.data as Map<String, dynamic>;
      final token = data['access_token']?.toString();

      if (token != null && token.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(StorageConstants.bearerToken, token);

        if (data['user'] != null) {
          await prefs.setString(
            StorageConstants.userData,
            jsonEncode(data['user']),
          );
        }
      }

      return data;
    }

    throw Exception(
      (response.data is Map ? response.data['message'] : null) ??
          'Sign in failed',
    );
  }

  Future<Map<String, dynamic>> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _dio.post(
      '${_baseUrl()}/api/auth/signup',
      data: {'name': name.trim(), 'email': email.trim(), 'password': password},
    );

    if (response.statusCode == 201) {
      return response.data as Map<String, dynamic>;
    }

    throw Exception(
      (response.data is Map ? response.data['message'] : null) ??
          'Sign up failed',
    );
  }

  /// Requests a password-reset OTP for [email].
  /// Returns the response body; when the backend has no mail server
  /// configured it includes a `debug_otp` field for development builds.
  Future<Map<String, dynamic>> forgotPassword({required String email}) async {
    final response = await _dio.post(
      '${_baseUrl()}/api/auth/forgot-password',
      data: {'email': email.trim()},
    );

    if (response.statusCode == 200) {
      return response.data as Map<String, dynamic>;
    }

    throw Exception(
      (response.data is Map ? response.data['message'] : null) ??
          'Could not send OTP',
    );
  }

  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final response = await _dio.post(
      '${_baseUrl()}/api/auth/reset-password',
      data: {
        'email': email.trim(),
        'otp': otp.trim(),
        'new_password': newPassword,
      },
    );

    if (response.statusCode == 200) {
      return response.data as Map<String, dynamic>;
    }

    throw Exception(
      (response.data is Map ? response.data['message'] : null) ??
          'Password reset failed',
    );
  }

  Future<String?> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(StorageConstants.bearerToken);
  }

  /// User object saved at sign-in (`{id, username, email}`), or null.
  Future<Map<String, dynamic>?> getStoredUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageConstants.userData);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageConstants.bearerToken);
    await prefs.remove(StorageConstants.userData);
  }
}
