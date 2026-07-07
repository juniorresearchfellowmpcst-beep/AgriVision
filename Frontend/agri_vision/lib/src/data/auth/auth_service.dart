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
              validateStatus: (status) => status != null && status! < 500,
            ),
          );

  final Dio _dio;

  String _baseUrl() {
    if (kIsWeb) {
      return 'http://127.0.0.1:5000';
    }

    if (Platform.isAndroid) {
      return 'http://10.0.2.2:5000';
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

  Future<String?> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(StorageConstants.bearerToken);
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageConstants.bearerToken);
    await prefs.remove(StorageConstants.userData);
  }
}
