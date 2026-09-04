import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agri_vision/src/core/theme/app_colors.dart';
import 'package:agri_vision/src/core/theme/app_palette.dart';
import 'package:agri_vision/src/ui/cubit/theme/theme_cubit.dart';

/// The dark theme, and the switch that reaches it.
///
/// Two things are worth pinning. The first is that "follow the phone" is a
/// third state rather than a second one, and a switch showing what the phone
/// resolved to has to commit to the *opposite* when pressed — landing on the
/// theme already on screen is the failure that reads as a broken control.
///
/// The second is contrast. A dark palette that is merely an arithmetic
/// inversion of a light one produces text you cannot read, and the way that
/// reaches a farmer is a screen of invisible headings rather than a crash.

/// Relative luminance, per WCAG. Enough to catch "these two are the same
/// colour" and "this text is a shade darker than its own background", which
/// is what an inverted palette actually gets wrong.
double _luminance(Color c) {
  double channel(double v) {
    v /= 255.0;
    // The exponent is 2.4, not 2. Squaring instead understates every ratio,
    // which would let a genuinely unreadable palette pass this file.
    return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(c.r * 255) +
      0.7152 * channel(c.g * 255) +
      0.0722 * channel(c.b * 255);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('choosing a theme', () {
    test('a fresh install follows the phone', () async {
      final cubit = ThemeCubit();
      await cubit.load();
      expect(cubit.state.mode, AppThemeMode.system);
      expect(cubit.state.loaded, isTrue);
    });

    test('the choice survives a restart', () async {
      await (ThemeCubit()..load()).select(AppThemeMode.dark);

      final next = ThemeCubit();
      await next.load();
      expect(next.state.mode, AppThemeMode.dark);
    });

    test('a toggle from "follow the phone" commits to the opposite', () async {
      // The switch shows what the phone resolved to. Pressing it must change
      // what is on screen, not agree with it.
      final cubit = ThemeCubit();
      await cubit.load();

      await cubit.toggle(currentlyDark: false);
      expect(cubit.state.mode, AppThemeMode.dark);

      await cubit.toggle(currentlyDark: true);
      expect(cubit.state.mode, AppThemeMode.light);
    });

    test('following the phone resolves against the device', () {
      expect(
        AppThemeMode.system.paletteFor(Brightness.dark).isDark,
        isTrue,
      );
      expect(
        AppThemeMode.system.paletteFor(Brightness.light).isDark,
        isFalse,
      );
      // A fixed choice outranks the phone: a screen used outdoors in sun is a
      // real reason to override a scheduled dark mode.
      expect(AppThemeMode.light.paletteFor(Brightness.dark).isDark, isFalse);
      expect(AppThemeMode.dark.paletteFor(Brightness.light).isDark, isTrue);
    });

    test('a broken preferences store still starts the app', () async {
      SharedPreferences.setMockInitialValues({'app_theme_mode': 'nonsense'});
      final cubit = ThemeCubit();
      await cubit.load();
      expect(cubit.state.mode, AppThemeMode.system);
    });
  });

  group('the dark palette is readable', () {
    test('body text clears WCAG AA on its own surface', () {
      const c = AppPalette.dark;
      // 4.5:1 is the AA bar for body text.
      expect(_contrast(c.dark900, c.surface), greaterThanOrEqualTo(4.5));
      expect(_contrast(c.dark700, c.surface), greaterThanOrEqualTo(4.5));
      expect(_contrast(c.dark500, c.surface), greaterThanOrEqualTo(4.5));
      expect(_contrast(c.dark900, c.background), greaterThanOrEqualTo(4.5));
    });

    test('secondary text clears the large-text bar', () {
      const c = AppPalette.dark;
      // dark300/dark100 are hints and captions, held to 3:1.
      expect(_contrast(c.dark300, c.surface), greaterThanOrEqualTo(3.0));
      expect(_contrast(c.dark100, c.surface), greaterThanOrEqualTo(3.0));
    });

    test('white ink still reads on the brand colours', () {
      const c = AppPalette.dark;
      // `light100` is white *ink* far more often than it is a surface, and it
      // sits on these two. Inverting it is what made the home banner's
      // greeting dark-on-dark.
      expect(c.light100, const Color(0xFFFFFFFF));
      expect(_contrast(c.light100, c.darkGreen), greaterThanOrEqualTo(4.5));
      expect(_contrast(c.light100, c.contrastSurface), greaterThanOrEqualTo(4.5));
    });

    test('the primary green carries white button labels', () {
      // The two jobs `primary` does pull in opposite directions -- white text
      // on it wants a dark green, accent ink on the near-black ground wants a
      // light one -- and no single colour clears AA 4.5 for both. 4.0 is the
      // balance point actually reachable, and both sides are held to it so a
      // future retune cannot quietly sacrifice one for the other.
      const c = AppPalette.dark;
      expect(_contrast(c.light100, c.primary), greaterThanOrEqualTo(4.0),
          reason: 'white button labels sit on this');
      expect(_contrast(c.primary, c.background), greaterThanOrEqualTo(4.0),
          reason: 'it is also used as accent ink on the background');
    });

    test('surfaces are distinguishable from the ground they sit on', () {
      const c = AppPalette.dark;
      for (final pair in <(Color, Color, String)>[
        (c.surface, c.background, 'card vs background'),
        (c.surfaceRaised, c.surface, 'raised vs card'),
        (c.light500, c.surface, 'border vs card'),
      ]) {
        expect(
          pair.$1,
          isNot(pair.$2),
          reason: '${pair.$3} must not be the same colour',
        );
      }
    });

    test('status colours stay legible on a dark card', () {
      const c = AppPalette.dark;
      // Error text is the last thing that should be hard to read.
      expect(_contrast(c.themeError, c.surface), greaterThanOrEqualTo(4.5));
      expect(_contrast(c.themeWarning, c.surface), greaterThanOrEqualTo(4.5));
      expect(_contrast(c.themeSuccess, c.surface), greaterThanOrEqualTo(4.5));
    });
  });

  group('the light theme is unchanged', () {
    test('its colours are the ones the app already shipped', () {
      // Adding a dark theme is not a licence to restyle the light one, which
      // is what every screen was designed and reviewed against.
      const c = AppPalette.light;
      expect(c.primary, const Color(0xFF569150));
      expect(c.background, const Color(0xFFF4F6F4));
      expect(c.light100, const Color(0xFFFFFFFF));
      expect(c.surface, const Color(0xFFFFFFFF));
      expect(c.darkGreen, const Color(0xFF1F4D38));
      expect(c.dark900, const Color(0xFF1F2024));
      expect(c.contrastSurface, const Color(0xFF2F3036));
    });

    test('AppColors resolves to whichever palette is active', () {
      addTearDown(() => AppColors.setPalette(AppPalette.light));

      AppColors.setPalette(AppPalette.light);
      expect(AppColors.surface, const Color(0xFFFFFFFF));
      expect(AppColors.isDark, isFalse);

      AppColors.setPalette(AppPalette.dark);
      expect(AppColors.surface, isNot(const Color(0xFFFFFFFF)));
      expect(AppColors.isDark, isTrue);
    });
  });
}
