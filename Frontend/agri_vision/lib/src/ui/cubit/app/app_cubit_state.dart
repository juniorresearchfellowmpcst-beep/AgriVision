part of 'app_cubit.dart';

/// Simple status enumeration for the app cubit
enum AppStatus { initial, loading, success, failure }

class AppCubitState extends Equatable {
  final AppStatus status;
  final String? message;
  final Map<String, dynamic>? payload;

  const AppCubitState({
    this.status = AppStatus.initial,
    this.message,
    this.payload,
  });

  AppCubitState copyWith({
    AppStatus? status,
    String? message,
    Map<String, dynamic>? payload,
  }) {
    return AppCubitState(
      status: status ?? this.status,
      message: message ?? this.message,
      payload: payload ?? this.payload,
    );
  }

  @override
  List<Object?> get props => [status, message, payload];
}
