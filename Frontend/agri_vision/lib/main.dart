import 'package:agri_vision/bootstrap.dart';
import 'package:agri_vision/src/ui/handler/exception_handler.dart';
import 'package:flutter/material.dart';
import 'dart:async';

Future<void> main() async {
  // Installed before bootstrap so a framework error raised during startup is
  // reported through the same path as everything after it.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    ExceptionHandler.handle(details.exception, stackTrace: details.stack);
  };

  runZonedGuarded(
    () async {
      await bootstrap();
    },
    (error, stackTrace) {
      ExceptionHandler.handle(error, stackTrace: stackTrace);
    },
  );
}
