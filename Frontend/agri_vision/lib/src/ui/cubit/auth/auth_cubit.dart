import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:agri_vision/src/data/auth/auth_service.dart';

part 'auth_cubit_state.dart';

class AuthCubit extends Cubit<AuthCubitState> {
  AuthCubit({AuthService? authService})
    : _authService = authService ?? AuthService(),
      super(const AuthCubitState());

  final AuthService _authService;

  Future<void> checkStatus() async {
    final token = await _authService.getStoredToken();
    emit(
      state.copyWith(
        status: (token != null && token.isNotEmpty)
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated,
      ),
    );
  }

  Future<void> signOut() async {
    await _authService.signOut();
    emit(const AuthCubitState(status: AuthStatus.unauthenticated));
  }
}
