import 'package:agri_vision/bootstrap.dart';
import 'package:agri_vision/src/ui/handler/exception_handler.dart';
import 'package:flutter/material.dart';
import 'dart:async';

Future<void> main() async {
  runZonedGuarded(
    () {
      bootstrap();
    },
    (error, stackTrace) {
      ExceptionHandler.handle(error, stackTrace: stackTrace);
    },
  );

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    ExceptionHandler.handle(details.exception, stackTrace: details.stack);
  };
}
