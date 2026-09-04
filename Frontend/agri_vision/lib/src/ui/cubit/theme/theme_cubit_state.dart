part of 'theme_cubit.dart';

class ThemeState extends Equatable {
  const ThemeState({this.mode = AppThemeMode.light, this.loaded = false});

  /// Light unless the farmer has chosen otherwise.
  final AppThemeMode mode;

  /// Whether the stored choice has been read yet.
  ///
  /// The first frame waits on this, so the app never paints light and then
  /// flips to dark in front of the farmer.
  final bool loaded;

  bool get isDark => mode.isDark;

  @override
  List<Object?> get props => [mode, loaded];
}
