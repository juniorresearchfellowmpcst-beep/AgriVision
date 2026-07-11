import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'src/src.dart';
import 'package:flutter_libphonenumber/flutter_libphonenumber.dart'
    as libphonenumber;

import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from the bundled asset. The asset is declared
  // in pubspec as `assets/.env`, so it must be loaded by that key (the default
  // '.env' key does not match and would silently load nothing).
  await dotenv.load(fileName: 'assets/.env');

  // Initialize date formatting
  await initializeDateFormatting();

  // Initialize libphonenumber
  await libphonenumber.init();

  /// Initialize Shared Preferences and Secure Storage
  final sharedPref = await SharedPreferences.getInstance();
  final secureStorage = const FlutterSecureStorage();

  /// Initialize Local Storage and Secure Local Storage
  final localStorage = LocalStorage(sharedPreferences: sharedPref);
  final secureLocalStorage = SecureLocalStorage(secureStorage: secureStorage);

  /// Initialize API Client
  final apiClient = ApiClient(
    storage: secureLocalStorage,
    // Fallback keeps startup from hard-crashing if BASE_URL is absent; the
    // auth/analysis services also honour --dart-define=API_BASE_URL at runtime.
    baseUrl: dotenv.get('BASE_URL', fallback: 'http://127.0.0.1:5000'),
  );

  /// Initialize Repositories
  final appRepository = AppRepositoryImpl(
    remoteDataSource: null,
    localDataSource: null,
    networkInfo: null,
  );

  runApp(App(appRepository: appRepository as AppRepository));
}
