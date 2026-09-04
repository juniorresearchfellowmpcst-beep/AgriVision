import 'package:flutter/material.dart';

import 'package:agri_vision/src/core/theme/app_palette.dart';

/// The app's colours, resolved against whichever palette is active.
///
/// These were `static const` and are now getters, which is the whole mechanism
/// behind the dark theme. Around 1250 call sites across 81 files name these
/// colours directly; rewriting them all to read from a `ThemeExtension` would
/// be the textbook approach and a far larger and riskier change than swapping
/// what they resolve to.
///
/// The cost of the getters is that `const SomeWidget(color: AppColors.x)` no
/// longer compiles. That cost is paid once, it is caught by the analyser
/// rather than at runtime, and dropping a `const` is never a behavioural
/// change — only a missed canonicalisation.
///
/// Written by [setPalette] before the first frame and on every theme change.
/// Reading a global rather than the `BuildContext` means a widget that does
/// not rebuild would keep the old colour, so the theme switch rebuilds the
/// whole tree from the root — see `ThemeCubit` and `app.dart`.
class AppColors {
  const AppColors._();

  static AppPalette _palette = AppPalette.light;

  /// The palette in force. Set from the root widget when the theme changes.
  static AppPalette get palette => _palette;

  static void setPalette(AppPalette palette) => _palette = palette;

  static bool get isDark => _palette.isDark;

  static Color get primary => _palette.primary;
  static Color get primary2 => _palette.primary2;
  static Color get primary3 => _palette.primary3;
  static Color get primary4 => _palette.primary4;
  static Color get primary5 => _palette.primary5;
  static Color get primary6 => _palette.primary6;
  static Color get primaryFade => _palette.primaryFade;
  static Color get themeSecondary => _palette.themeSecondary;
  static Color get themeSuccess => _palette.themeSuccess;
  static Color get themeError => _palette.themeError;
  static Color get themeWarning => _palette.themeWarning;
  static Color get themeToolTipIcon => _palette.themeToolTipIcon;

  static Color get secondary => _palette.secondary;
  static Color get tertiary => _palette.tertiary;
  static Color get googleColor => _palette.googleColor;
  static Color get darkGreen => _palette.darkGreen;
  static Color get background => _palette.background;
  static Color get surface => _palette.surface;
  static Color get surfaceRaised => _palette.surfaceRaised;
  static Color get contrastSurface => _palette.contrastSurface;

  static Color get light100 => _palette.light100;
  static Color get light300 => _palette.light300;
  static Color get light500 => _palette.light500;
  static Color get light700 => _palette.light700;
  static Color get light900 => _palette.light900;
  static Color get light2 => _palette.light2;

  static Color get dark100 => _palette.dark100;
  static Color get dark300 => _palette.dark300;
  static Color get dark500 => _palette.dark500;
  static Color get dark700 => _palette.dark700;
  static Color get dark900 => _palette.dark900;

  /// A shadow that reads on either ground.
  ///
  /// Tinting a shadow with the ink colour is right on white and wrong on
  /// charcoal: in dark mode `dark900` is nearly white, so the same code would
  /// paint a glow around every card. Dark surfaces are separated by their own
  /// tone rather than by a shadow, so the shadow goes black and gets deeper.
  static BoxShadow get boxShadow => BoxShadow(
    color: _palette.isDark
        ? const Color(0xFF000000).withAlpha(90)
        : _palette.dark900.withAlpha(50),
    offset: const Offset(0, 1),
    blurRadius: 5,
    spreadRadius: 1,
  );
}
