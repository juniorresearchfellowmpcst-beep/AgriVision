// ignore_for_file: public_member_api_docs

import 'package:dio/dio.dart';

abstract class AppException implements Exception {
  AppException({this.code = '', this.message = '', this.data});

  final String code;
  final String message;
  final dynamic data;

  @override
  String toString() => message;
}

extension AppErrorExtension on Object {
  AppException toAppException() {
    if (this is AppException) {
      return this as AppException;
    }
    return UnexpectedException(message: toString());
  }
}

extension ResponseExceptionParser on Response {
  AppException toAppException() {
    try {
      final data = this.data;

      if (data is Map<String, dynamic>) {
        final message = data['message']?.toString();
        final errors = data['errors'];

        if (message != null && message.isNotEmpty) {
          return UnProcessableContentException(
            code: statusCode?.toString() ?? '',
            message: message,
            data: errors ?? data,
          );
        }
      }

      // If message not found → fallback
      return UnexpectedException(
        code: statusCode?.toString() ?? '',
        message: " somethingWentWrong",
        data: data,
      );
    } catch (_) {
      return UnexpectedException(
        code: statusCode?.toString() ?? '',
        message: " somethingWentWrong",
        data: data,
      );
    }
  }
}

class TokenNotFoundException extends AppException {
  TokenNotFoundException({
    super.code,
    super.message = "Token not found",
    super.data,
  });
}

class UnexpectedException extends AppException {
  UnexpectedException({
    super.code,
    super.message = " somethingWentWrong",
    super.data,
  });
}

class MissingDataException extends AppException {
  MissingDataException({super.code, super.message, super.data});
}

class FileSizeExceededException extends AppException {
  FileSizeExceededException({
    super.code,
    super.message = "File size exceeded",
    super.data,
  });
}

class UnProcessableContentException extends AppException {
  UnProcessableContentException({
    super.code,
    super.message = "Unprocessable content",
    super.data,
  });
}

class MethodChannelException extends AppException {
  MethodChannelException({
    super.code,
    super.message = "Method channel error",
    super.data,
  });
}
