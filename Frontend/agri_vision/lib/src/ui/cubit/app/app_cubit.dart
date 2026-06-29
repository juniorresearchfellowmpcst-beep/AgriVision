import 'package:agri_vision/src/domain/repository/app_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'app_cubit_state.dart';

class AppCubit extends Cubit<AppCubitState> {
  AppCubit({required AppRepository repository}) : super(const AppCubitState());
}
