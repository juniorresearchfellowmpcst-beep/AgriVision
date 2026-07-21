part of 'reports_cubit.dart';

enum ReportsStatus { initial, loading, success, failure }

class ReportsState extends Equatable {
  const ReportsState({
    this.status = ReportsStatus.initial,
    this.reports = const [],
    this.selectedIndex = 0,
    this.errorMessage = '',
  });

  final ReportsStatus status;
  final List<FieldReportEntity> reports;
  final int selectedIndex;
  final String errorMessage;

  bool get isLoading => status == ReportsStatus.loading;

  FieldReportEntity? get selected =>
      selectedIndex >= 0 && selectedIndex < reports.length
      ? reports[selectedIndex]
      : null;

  ReportsState copyWith({
    ReportsStatus? status,
    List<FieldReportEntity>? reports,
    int? selectedIndex,
    String? errorMessage,
  }) {
    return ReportsState(
      status: status ?? this.status,
      reports: reports ?? this.reports,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, reports, selectedIndex, errorMessage];
}
