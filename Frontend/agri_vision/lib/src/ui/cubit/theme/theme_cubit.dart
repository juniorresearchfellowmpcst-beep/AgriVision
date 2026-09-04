import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agri_vision/src/core/theme/app_palette.dart';

part 'theme_cubit_state.dart';

/// Light, dark, or whatever the phone is set to.
///
/// Stored on the device rather than server-side, for the same reason the
/// language is: a shared ground-station handset passed between an operator and
/// a farmer should not have its appearance follow whoever last signed in, and
/// the setting has to work before anyone signs in at all.
///
/// "Follow the phone" is the default. Somebody who has already set their phone
/// to dark has said what they want, and asking again is a worse default than
/// listening — but a fixed choice still wins over the system when one is made,
/// because a screen used outdoors in sun is a real reason to override a
/// scheduled dark mode.
class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit() : super(const ThemeState());

  static const String _storageKey = 'app_theme_mode';

  /// Read the stored choice. Called once at startup, before the first frame,
  /// so the app never paints light and then flips to dark.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (isClosed) return;
      emit(ThemeState(mode: AppThemeMode.fromName(stored), loaded: true));
    } catch (_) {
      // A preferences failure must not stop the app starting. Following the
      // system is the safe fallback: it is what a fresh install does.
      if (isClosed) return;
      emit(const ThemeState(loaded: true));
    }
  }

  Future<void> select(AppThemeMode mode) async {
    if (mode == state.mode) return;
    emit(ThemeState(mode: mode, loaded: true));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, mode.name);
    } catch (_) {
      // Already applied in memory; losing only the persistence means it
      // resets next launch, which beats refusing to switch at all.
    }
  }

  /// Flip between light and dark.
  ///
  /// From "follow the phone" this commits to the opposite of what is on screen
  /// right now, which is what someone pressing a switch means by it — landing
  /// on the mode they can already see would read as the control being broken.
  Future<void> toggle({required bool currentlyDark}) =>
      select(currentlyDark ? AppThemeMode.light : AppThemeMode.dark);
}

/// What the farmer chose, which is not the same as what is on screen: `system`
/// resolves against the phone.
enum AppThemeMode {
  system,
  light,
  dark;

  static AppThemeMode fromName(String? name) => AppThemeMode.values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => AppThemeMode.system,
  );

  ThemeMode get material => switch (this) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };

  /// Which palette this resolves to, given what the phone is currently set to.
  AppPalette paletteFor(Brightness platformBrightness) => switch (this) {
    AppThemeMode.light => AppPalette.light,
    AppThemeMode.dark => AppPalette.dark,
    AppThemeMode.system => platformBrightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light,
  };
}
