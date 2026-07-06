import 'dart:async';
import 'package:flutter/material.dart';

import 'src/src.dart';
import 'src/utils/phone_number_support.dart';
import 'package:flutter_libphonenumber/flutter_libphonenumber.dart'
    as libphonenumber;

import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  // await dotenv.load();

  // Initialize date formatting
  await initializeDateFormatting();

  // Initialize libphonenumber only on supported platforms.
  // if (isPhoneNumberPluginSupported(defaultTargetPlatform)) {
  //   await libphonenumber.init();
  // }

  /// Initialize Shared Preferences and Secure Storage
  // final sharedPref = await SharedPreferences.getInstance();
  // final secureStorage = const FlutterSecureStorage();

  /// Initialize Local Storage and Secure Local Storage
  // final localStorage = LocalStorage(sharedPreferences: sharedPref);
  // final secureLocalStorage = SecureLocalStorage(secureStorage: secureStorage);

  /// Initialize API Client
  // final apiClient = ApiClient(
  //   storage: secureLocalStorage,
  //   baseUrl: dotenv.get('BASE_URL'),
  // );

  /// Initialize Repositories
  final appRepository = AppRepositoryImpl(
    remoteDataSource: null,
    localDataSource: null,
    networkInfo: null,
  );

  runApp(App(appRepository: appRepository as AppRepository));
}
