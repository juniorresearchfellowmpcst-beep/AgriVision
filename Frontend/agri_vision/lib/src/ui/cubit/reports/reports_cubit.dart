import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/data/report/report_service.dart';
import 'package:agri_vision/src/domain/entity/field_report_entity.dart';

part 'reports_cubit_state.dart';

/// Persisted field-analysis reports (multispectral history), shown on the
/// Reports tab. One report can be selected via the block dropdown.
class ReportsCubit extends Cubit<ReportsState> {
  ReportsCubit({ReportService? service})
    : _service = service ?? ReportService(),
      super(const ReportsState());

  final ReportService _service;

  Future<void> load({bool refresh = false}) async {
    if (state.status == ReportsStatus.loading) return;
    if (state.status == ReportsStatus.success && !refresh) return;

    emit(state.copyWith(status: ReportsStatus.loading, errorMessage: ''));
    try {
      final reports = await _service.fetchReports();
      emit(
        state.copyWith(
          status: ReportsStatus.success,
          reports: reports,
          selectedIndex: 0,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: ReportsStatus.failure,
          errorMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  void select(int index) {
    if (index < 0 || index >= state.reports.length) return;
    emit(state.copyWith(selectedIndex: index));
  }
}
