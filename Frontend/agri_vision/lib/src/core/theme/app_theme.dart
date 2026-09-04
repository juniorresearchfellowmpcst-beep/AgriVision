import 'package:agri_vision/src/core/core.dart';
import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  /// The light theme. Kept as the name every existing call site uses.
  static ThemeData get standard => _build(AppPalette.light);

  /// The same theme on a dark ground.
  static ThemeData get dark => _build(AppPalette.dark);

  /// One builder for both, so a control styled in light cannot be forgotten in
  /// dark. Every colour below comes from the palette; nothing is hard-coded,
  /// which is what stops the two drifting apart.
  static ThemeData _build(AppPalette c) {
    return ThemeData(
      brightness: c.brightness,
      scaffoldBackgroundColor: c.background,
      // No `canvasColor`. Setting it changed how chips render in the
      // *light* theme -- the survey screen's detection chips moved --
      // and dark mode does not need it: `scaffoldBackgroundColor` covers
      // the page ground and Material derives the canvas from brightness.
      cardColor: c.light100,
      dividerColor: c.light500,
      colorScheme: ColorScheme(
        brightness: c.brightness,
        primary: c.primary,
        onPrimary: c.isDark ? const Color(0xFF10240F) : const Color(0xFFFFFFFF),
        secondary: c.primary6,
        onSecondary: c.isDark ? const Color(0xFF10240F) : const Color(0xFFFFFFFF),
        error: c.themeError,
        onError: c.isDark ? const Color(0xFF2A0B0B) : const Color(0xFFFFFFFF),
        surface: c.light100,
        onSurface: c.dark900,
      ),
      // Dialogs, sheets and menus are the surfaces that most often get missed:
      // they are built by Flutter rather than by this app's widgets, so they
      // take their colour from here or they stay white on a black app.
      dialogTheme: DialogThemeData(
        backgroundColor: c.light100,
        titleTextStyle: AppTextStyle.textLgSemibold.copyWith(color: c.dark900),
        contentTextStyle: AppTextStyle.textMdRegular.copyWith(color: c.dark500),
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.light100),
      popupMenuTheme: PopupMenuThemeData(color: c.light100),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.isDark ? c.light500 : c.dark900,
        contentTextStyle: AppTextStyle.textSmRegular.copyWith(
          color: c.isDark ? c.dark900 : c.light100,
        ),
      ),
      // No global `iconTheme` or `listTileTheme` either, for the same reason:
      // both override Material's defaults in the light theme as well, and an
      // icon colour applied app-wide moved every icon on the screens that had
      // been signed off. Flutter already derives sensible icon and list
      // colours from `colorScheme.brightness`, which is set above.
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.primary,
        selectionColor: c.primary.withAlpha(70),
        selectionHandleColor: c.primary,
      ),
      // Deliberately no `inputDecorationTheme`. Setting `filled`, a hint style
      // or a label style here changes the metrics of every text field in the
      // *light* theme too -- it shifted the survey screen down by several
      // pixels -- and adding a dark theme is not a licence to restyle the one
      // every screen was designed against. The colorScheme above already gives
      // fields a readable ground in dark.
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
      useMaterial3: false,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
        },
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: WidgetStateProperty.all(true),
        thickness: WidgetStateProperty.all(5),
        radius: const Radius.circular(5),
        thumbColor: WidgetStateProperty.all(c.light900),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        trackBorderColor: WidgetStateProperty.all(Colors.transparent),
      ),
      searchBarTheme: SearchBarThemeData(
        constraints: const BoxConstraints(minHeight: 0, minWidth: 0),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: c.light900),
        ),
        backgroundColor: WidgetStateProperty.all(c.light100),
        elevation: WidgetStateProperty.all(0),
        hintStyle: WidgetStateProperty.all(
          AppTextStyle.textMdRegular.copyWith(color: c.dark500),
        ),
        textStyle: WidgetStateProperty.all(
          AppTextStyle.textMdRegular.copyWith(color: c.dark900),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
      ),

      searchViewTheme: SearchViewThemeData(
        backgroundColor: c.light100,
        headerHintStyle: AppTextStyle.textMdRegular.copyWith(
          color: c.dark500,
        ),
        headerTextStyle: AppTextStyle.textMdMedium.copyWith(
          color: c.dark900,
        ),
      ),
    );
  }
}

class ScrollBehaviorModified extends ScrollBehavior {
  const ScrollBehaviorModified();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics();
  }
}

class CustomBehaviour extends StatelessWidget {
  const CustomBehaviour({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Stack(
        children: [
          ScrollConfiguration(
            behavior: const ScrollBehaviorModified(),
            child: child,
          ),
        ],
      ),
    );
  }
}
