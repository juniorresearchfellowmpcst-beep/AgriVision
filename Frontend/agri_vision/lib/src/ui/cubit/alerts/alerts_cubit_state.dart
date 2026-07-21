part of 'alerts_cubit.dart';

enum AlertsStatus { initial, loading, success, failure }

class AlertsState extends Equatable {
  const AlertsState({
    this.status = AlertsStatus.initial,
    this.alerts = const [],
    this.activeCount = 0,
    this.errorMessage = '',
  });

  final AlertsStatus status;
  final List<AlertEntity> alerts;
  final int activeCount;
  final String errorMessage;

  bool get isLoading => status == AlertsStatus.loading;

  AlertsState copyWith({
    AlertsStatus? status,
    List<AlertEntity>? alerts,
    int? activeCount,
    String? errorMessage,
  }) {
    return AlertsState(
      status: status ?? this.status,
      alerts: alerts ?? this.alerts,
      activeCount: activeCount ?? this.activeCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, alerts, activeCount, errorMessage];
}
