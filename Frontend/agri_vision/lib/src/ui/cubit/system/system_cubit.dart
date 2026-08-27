import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:agri_vision/src/data/system/system_service.dart';
import 'package:agri_vision/src/domain/entity/system_links_entity.dart';

part 'system_cubit_state.dart';

/// The backend's own connection details, for the Settings screen.
///
/// Kept apart from [SettingsCubit] on purpose: preferences are per-account and
/// change when the user taps a switch, whereas this is per-machine and changes
/// when the network does. Refreshing one should not refetch the other, and a
/// failure to reach the server here must not blank out the preferences that
/// already loaded.
class SystemCubit extends Cubit<SystemState> {
  SystemCubit({SystemService? service})
    : _service = service ?? SystemService(),
      super(const SystemState());

  final SystemService _service;

  /// Load the connection links and the module health report.
  ///
  /// The two are fetched independently: a machine with no LAN address still
  /// has a working health report, and a degraded module should not stop the
  /// operator reading the API address they came here for.
  Future<void> load({bool refresh = false}) async {
    if (state.status == SystemStatus.loading) return;
    if (state.status == SystemStatus.success && !refresh) return;

    emit(state.copyWith(status: SystemStatus.loading, errorMessage: ''));

    try {
      final links = await _service.fetchLinks();
      emit(state.copyWith(status: SystemStatus.success, links: links));
    } catch (e) {
      emit(
        state.copyWith(status: SystemStatus.failure, errorMessage: _clean(e)),
      );
    }

    await loadHealth();
  }

  Future<void> loadHealth() async {
    try {
      final health = await _service.fetchHealth();
      emit(state.copyWith(health: health, healthLoaded: true));
    } catch (_) {
      // A health failure is not worth an error banner — the links above it are
      // the reason the operator opened this screen.
      emit(state.copyWith(healthLoaded: true));
    }
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');
}
