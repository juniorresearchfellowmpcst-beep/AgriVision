import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/data/report/report_service.dart';
import 'package:agri_vision/src/domain/entity/alert_entity.dart';

part 'alerts_cubit_state.dart';

/// Active AI alerts raised by analysis runs, shown on the Alerts tab.
class AlertsCubit extends Cubit<AlertsState> {
  AlertsCubit({ReportService? service})
    : _service = service ?? ReportService(),
      super(const AlertsState());

  final ReportService _service;

  Future<void> load({bool refresh = false}) async {
    if (state.status == AlertsStatus.loading) return;
    if (state.status == AlertsStatus.success && !refresh) return;

    emit(state.copyWith(status: AlertsStatus.loading, errorMessage: ''));
    try {
      final (activeCount, alerts) = await _service.fetchAlerts();
      emit(
        state.copyWith(
          status: AlertsStatus.success,
          alerts: alerts,
          activeCount: activeCount,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: AlertsStatus.failure,
          errorMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  /// Optimistically remove the alert, then confirm with the backend.
  Future<void> resolve(AlertEntity alert) async {
    final previous = state;
    emit(
      state.copyWith(
        alerts: state.alerts.where((a) => a.id != alert.id).toList(),
        activeCount: (state.activeCount - 1).clamp(0, 1 << 31),
      ),
    );
    try {
      await _service.resolveAlert(alert.id);
    } catch (_) {
      emit(previous); // roll back; the alert is still active server-side
    }
  }
}
