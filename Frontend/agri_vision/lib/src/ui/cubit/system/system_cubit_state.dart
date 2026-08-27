part of 'system_cubit.dart';

enum SystemStatus { initial, loading, success, failure }

class SystemState extends Equatable {
  const SystemState({
    this.status = SystemStatus.initial,
    this.links = SystemLinksEntity.empty,
    this.health = SystemHealth.empty,
    this.healthLoaded = false,
    this.errorMessage = '',
  });

  final SystemStatus status;
  final SystemLinksEntity links;
  final SystemHealth health;

  /// Whether the health report has been fetched at least once, so the screen
  /// can show a spinner instead of claiming everything is down on first paint.
  final bool healthLoaded;

  final String errorMessage;

  bool get isLoading => status == SystemStatus.loading;

  /// True when there is something concrete to show a ground-station operator.
  bool get hasGcsTarget => links.mavlink.gcsTargets.isNotEmpty;

  SystemState copyWith({
    SystemStatus? status,
    SystemLinksEntity? links,
    SystemHealth? health,
    bool? healthLoaded,
    String? errorMessage,
  }) {
    return SystemState(
      status: status ?? this.status,
      links: links ?? this.links,
      health: health ?? this.health,
      healthLoaded: healthLoaded ?? this.healthLoaded,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status,
    links,
    healthLoaded,
    errorMessage,
    health.ok,
    health.degraded,
  ];
}
