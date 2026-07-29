part of 'settings_cubit.dart';

enum SettingsStatus { initial, loading, success, failure }

class SettingsState extends Equatable {
  const SettingsState({
    this.status = SettingsStatus.initial,
    this.preferences = const UserPreferencesEntity(),
    this.syncItems = const [],
    this.syncLoaded = false,
    this.errorMessage = '',
  });

  final SettingsStatus status;
  final UserPreferencesEntity preferences;
  final List<SyncItemEntity> syncItems;

  /// Whether the sync summary has been fetched at least once — lets the
  /// Settings screen show a spinner rather than an empty queue on first paint.
  final bool syncLoaded;

  final String errorMessage;

  bool get isLoading => status == SettingsStatus.loading;

  /// Total records the server is still holding open across all categories.
  int get pendingCount =>
      syncItems.fold(0, (sum, item) => sum + item.pending);

  SettingsState copyWith({
    SettingsStatus? status,
    UserPreferencesEntity? preferences,
    List<SyncItemEntity>? syncItems,
    bool? syncLoaded,
    String? errorMessage,
  }) {
    return SettingsState(
      status: status ?? this.status,
      preferences: preferences ?? this.preferences,
      syncItems: syncItems ?? this.syncItems,
      syncLoaded: syncLoaded ?? this.syncLoaded,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status,
    preferences,
    syncItems,
    syncLoaded,
    errorMessage,
  ];
}
