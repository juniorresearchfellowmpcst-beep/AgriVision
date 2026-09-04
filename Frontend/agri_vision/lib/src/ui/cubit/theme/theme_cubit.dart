import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agri_vision/src/core/theme/app_palette.dart';

part 'theme_cubit_state.dart';

/// Light by default; dark is something the farmer turns on.
///
/// Not "follow the phone". This app is used outdoors in daylight far more than
/// it is used in the dark, and the light theme is the one every screen was
/// designed and reviewed against — so it is what a fresh install gets,
/// regardless of what the handset happens to be set to. Dark is an option,
/// which is a different thing from a default.
///
/// Stored on the device rather than server-side, for the same reason the
/// language is: a shared ground-station handset passed between an operator and
/// a farmer should not have its appearance follow whoever last signed in, and
/// the setting has to work before anyone signs in at all.
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
      // A preferences failure must not stop the app starting, and light is the
      // safe fallback: it is what a fresh install uses anyway.
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
      // Already applied in memory; losing only the persistence means it resets
      // next launch, which beats refusing to switch at all.
    }
  }

  Future<void> setDark(bool on) =>
      select(on ? AppThemeMode.dark : AppThemeMode.light);
}

/// The two themes. Light is the default and dark is the option.
enum AppThemeMode {
  light,
  dark;

  /// Falls back to light for anything unrecognised — including a value written
  /// by an older build that also offered "follow the phone".
  static AppThemeMode fromName(String? name) => AppThemeMode.values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => AppThemeMode.light,
  );

  bool get isDark => this == AppThemeMode.dark;

  ThemeMode get material =>
      this == AppThemeMode.dark ? ThemeMode.dark : ThemeMode.light;

  AppPalette get palette =>
      this == AppThemeMode.dark ? AppPalette.dark : AppPalette.light;
}

/// Repaint everything after a palette swap, without throwing away any state.
///
/// `AppColors.x` reads a global, so — unlike `Theme.of(context)` — it registers
/// no dependency and nothing tells an already-built widget that its colours
/// changed. A `const` subtree is worse: its widget instance is identical
/// between builds, so the element short-circuits and `build` is never called
/// again. Toggling the theme left whole sections of the screen in the old
/// palette until something else happened to rebuild them.
///
/// Marking every element dirty fixes that at the level the problem lives on —
/// the elements, not the widgets. Re-keying the tree would also work and would
/// destroy the navigation stack and every scroll position with it, which is a
/// large price for a setting somebody flips in Settings.
///
/// Called after the frame: `markNeedsBuild` during a build is illegal.
void repaintAfterThemeChange() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    void mark(Element element) {
      element.markNeedsBuild();
      element.visitChildren(mark);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) mark(root);
  });
}
