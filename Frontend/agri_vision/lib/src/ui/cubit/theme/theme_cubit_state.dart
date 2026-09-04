part of 'theme_cubit.dart';

class ThemeState extends Equatable {
  const ThemeState({this.mode = AppThemeMode.system, this.loaded = false});

  final AppThemeMode mode;

  /// Whether the stored choice has been read yet.
  ///
  /// The first frame waits on this, so the app never paints light and then
  /// flips to dark in front of the farmer.
  final bool loaded;

  @override
  List<Object?> get props => [mode, loaded];
}
