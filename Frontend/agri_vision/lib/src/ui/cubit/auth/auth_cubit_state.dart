part of 'auth_cubit.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthCubitState extends Equatable {
  final AuthStatus status;

  const AuthCubitState({this.status = AuthStatus.unknown});

  AuthCubitState copyWith({AuthStatus? status}) {
    return AuthCubitState(status: status ?? this.status);
  }

  @override
  List<Object?> get props => [status];
}
