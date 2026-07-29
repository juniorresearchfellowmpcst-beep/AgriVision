import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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

  // Warm the SharedPreferences singleton so the first token read on the
  // sign-in path doesn't pay for plugin initialisation.
  await SharedPreferences.getInstance();

  // NOTE: no ApiClient is constructed here. Every data service builds its own
  // Dio through ApiConfig (base URL from assets/.env, bearer token per call),
  // so a client wired up at startup would just be a second, unused transport.
  // If the app ever centralises on ApiClient, this is where it goes.

  /// Initialize Repositories
  final appRepository = AppRepositoryImpl(
    remoteDataSource: null,
    localDataSource: null,
    networkInfo: null,
  );

  runApp(App(appRepository: appRepository as AppRepository));
}
