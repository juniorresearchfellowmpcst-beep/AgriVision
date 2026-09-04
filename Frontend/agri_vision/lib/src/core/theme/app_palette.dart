import 'package:flutter/material.dart';

/// One complete set of the app's colours.
///
/// The names are the ones the app already had, and they are *tonal* rather
/// than semantic: `light100` is the lightest surface, `dark900` the darkest
/// ink. That naming is what makes a second palette tractable — every one of
/// them already means "a surface" or "a piece of text", so the dark theme is
/// the same roles rebuilt on a dark ground, not a rename of 1200 call sites.
///
/// The one thing not to do here is invert the ramps arithmetically. Flipping
/// `#FFFFFF` to `#000000` gives a black that vibrates against white text and
/// hides every border the light theme drew in `light500`. Dark surfaces are
/// built up from a near-black ground in deliberate steps instead, and the
/// accents are lifted rather than mirrored: the app's green is legible on
/// white and muddy on charcoal, so the dark palette carries a brighter one.
@immutable
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.primary,
    required this.primary2,
    required this.primary3,
    required this.primary4,
    required this.primary5,
    required this.primary6,
    required this.primaryFade,
    required this.themeSecondary,
    required this.themeSuccess,
    required this.themeError,
    required this.themeWarning,
    required this.themeToolTipIcon,
    required this.secondary,
    required this.tertiary,
    required this.googleColor,
    required this.darkGreen,
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.contrastSurface,
    required this.light100,
    required this.light300,
    required this.light500,
    required this.light700,
    required this.light900,
    required this.light2,
    required this.dark100,
    required this.dark300,
    required this.dark500,
    required this.dark700,
    required this.dark900,
  });

  final Brightness brightness;

  final Color primary;
  final Color primary2;
  final Color primary3;
  final Color primary4;
  final Color primary5;
  final Color primary6;
  final Color primaryFade;
  final Color themeSecondary;
  final Color themeSuccess;
  final Color themeError;
  final Color themeWarning;
  final Color themeToolTipIcon;

  final Color secondary;
  final Color tertiary;
  final Color googleColor;
  final Color darkGreen;
  final Color background;

  /// The card surface. Split out from `light100` because that name carries two
  /// roles which move in opposite directions when the ground goes dark -- ink
  /// on a brand colour stays white, a card does not.
  final Color surface;

  /// One step above [surface], for something raised on top of a card.
  final Color surfaceRaised;

  /// A deliberately high-contrast slab — the secondary button that is
  /// near-black with white text in the light theme.
  ///
  /// It needs its own name because the light theme builds it out of `dark700`,
  /// which is an *ink* colour everywhere else. Inverting the ink ramp turned
  /// that button white, and its white label with it.
  final Color contrastSurface;

  /// Surfaces, lightest first in the light theme and darkest first in dark.
  final Color light100;
  final Color light300;
  final Color light500;
  final Color light700;
  final Color light900;
  final Color light2;

  /// Ink, faintest first. Reads as grey-on-white in light, grey-on-black in
  /// dark — the *contrast* is what is preserved, not the literal colour.
  final Color dark100;
  final Color dark300;
  final Color dark500;
  final Color dark700;
  final Color dark900;

  bool get isDark => brightness == Brightness.dark;

  /// The palette the app has always shipped. Unchanged, deliberately: the
  /// light theme is what every screen was designed and reviewed against, and
  /// adding a dark one is not a licence to quietly restyle the light one.
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    primary: Color(0xFF569150),
    primary2: Color(0xFF569150),
    primary3: Color(0xFFb2ceb0),
    primary4: Color(0xFFbbd3b9),
    primary5: Color(0xFFd0dcce),
    primary6: Color(0xFF5d9c59),
    primaryFade: Color(0xFFd0e2cf),
    themeSecondary: Color(0x66569150),
    themeSuccess: Color(0xFF5D9C59),
    themeError: Color(0xFFE64848),
    themeWarning: Color(0xFFE7B10A),
    themeToolTipIcon: Color(0xFF000000),
    secondary: Color(0xFFededed),
    tertiary: Color(0xFFF8F8F8),
    googleColor: Color(0xFF318AF5),
    darkGreen: Color(0xFF1F4D38),
    background: Color(0xFFF4F6F4),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF8F9FE),
    contrastSurface: Color(0xFF2F3036),
    light100: Color(0xFFFFFFFF),
    light300: Color(0xFFF8F9FE),
    light500: Color(0xFFE8E9F1),
    light700: Color(0xFFD4D6DD),
    light900: Color(0xFFC5C6CC),
    light2: Color(0xFFececec),
    dark100: Color(0xFF8F9098),
    dark300: Color(0xFF71727A),
    dark500: Color(0xFF494A50),
    dark700: Color(0xFF2F3036),
    dark900: Color(0xFF1F2024),
  );

  /// The same roles on a dark ground.
  ///
  /// Two choices worth keeping if this is ever retuned:
  ///
  /// *Surfaces climb, they do not invert.* `light100` is the card and stays
  /// one step above `background`, so a card still reads as raised. Pure black
  /// is avoided — on OLED it makes white text bloom, and it leaves nothing
  /// darker to put behind an elevated surface.
  ///
  /// *The green is a compromise, and deliberately so.* `primary` has to do two
  /// contradictory jobs here: carry white button labels (which wants a dark
  /// green) and read as accent ink on a near-black ground (which wants a light
  /// one). Solving both at AA is impossible with one token — white text needs
  /// luminance below 0.183, accent contrast needs above 0.223 — so this sits
  /// at the balance point: 4.2:1 for white on the button, 4.4:1 against the
  /// background. An earlier, prettier `#6FBF67` scored 2.25 for white labels,
  /// which is the "Start Survey Flight" button being hard to read.
  ///
  /// The status colours are lifted, though: a red legible on white is muddy on
  /// black, and error text is the last thing that should be hard to read.
  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    primary: Color(0xFF478A42),
    primary2: Color(0xFF478A42),
    primary3: Color(0xFF3E5B3C),
    primary4: Color(0xFF44643F),
    primary5: Color(0xFF2E3F2C),
    primary6: Color(0xFF539B4D),
    primaryFade: Color(0xFF27351F),
    themeSecondary: Color(0x66478A42),
    themeSuccess: Color(0xFF6ECB6A),
    themeError: Color(0xFFFF6B6B),
    themeWarning: Color(0xFFF0C244),
    themeToolTipIcon: Color(0xFFFFFFFF),
    secondary: Color(0xFF23262B),
    tertiary: Color(0xFF1B1E22),
    googleColor: Color(0xFF5A9DF8),
    // Stays deep. Counted across the app it is a *surface* 23 times against 3
    // as ink -- it is the app-bar green, carrying white text. Lifting it to a
    // pale green turned every header into a bright bar on a dark app. The
    // three ink uses moved to `primary`, which is what an accent should have
    // been anyway.
    darkGreen: Color(0xFF1F4D38),
    background: Color(0xFF121417),
    surface: Color(0xFF1C1F24),
    surfaceRaised: Color(0xFF23272D),
    // Already on a dark ground, so "high contrast" means lifted, not darker.
    contrastSurface: Color(0xFF39404A),
    // NOT inverted, deliberately. Measured across the app, `light100` is used
    // 161 times as ink and 68 times as a surface: overwhelmingly it means
    // "white text or icon on the brand green", and that green stays green in
    // dark mode, so the text on it stays white. Inverting this is what turned
    // the home banner's greeting into dark-on-dark. The surface role moved to
    // `surface` below.
    light100: Color(0xFFFFFFFF),
    light300: Color(0xFF23272D),
    light500: Color(0xFF31363D),
    light700: Color(0xFF3C424A),
    light900: Color(0xFF4A515A),
    light2: Color(0xFF262A30),
    // Ink: faintest -> strongest, the same ordering the light ramp has.
    dark100: Color(0xFF8B929C),
    dark300: Color(0xFFA8AFB9),
    dark500: Color(0xFFC6CCD4),
    dark700: Color(0xFFE2E6EB),
    dark900: Color(0xFFF4F6F8),
  );
}
