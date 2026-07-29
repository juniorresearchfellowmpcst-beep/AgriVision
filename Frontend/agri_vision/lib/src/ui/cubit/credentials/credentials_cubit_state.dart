part of 'credentials_cubit.dart';

enum CredentialsStatus { initial, loading, success, failure }

class CredentialsState extends Equatable {
  const CredentialsState({
    this.status = CredentialsStatus.initial,
    this.credentials = const [],
    this.expiringCount = 0,
    this.expiredCount = 0,
    this.errorMessage = '',
  });

  final CredentialsStatus status;
  final List<PilotCredentialEntity> credentials;
  final int expiringCount;
  final int expiredCount;
  final String errorMessage;

  bool get isLoading => status == CredentialsStatus.loading;

  /// Anything the operator needs to act on before the next flight.
  bool get needsAttention => expiringCount > 0 || expiredCount > 0;

  /// Rows that exist but haven't been filled in yet.
  int get blankCount => credentials.where((c) => c.isBlank).length;

  CredentialsState copyWith({
    CredentialsStatus? status,
    List<PilotCredentialEntity>? credentials,
    int? expiringCount,
    int? expiredCount,
    String? errorMessage,
  }) {
    return CredentialsState(
      status: status ?? this.status,
      credentials: credentials ?? this.credentials,
      expiringCount: expiringCount ?? this.expiringCount,
      expiredCount: expiredCount ?? this.expiredCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status,
    credentials,
    expiringCount,
    expiredCount,
    errorMessage,
  ];
}
