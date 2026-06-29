import 'package:agri_vision/src/core/core.dart';
import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get standard {
    return ThemeData(
      brightness: Brightness.light,
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
        thumbColor: WidgetStateProperty.all(AppColors.light900),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        trackBorderColor: WidgetStateProperty.all(Colors.transparent),
      ),
      searchBarTheme: SearchBarThemeData(
        constraints: const BoxConstraints(minHeight: 0, minWidth: 0),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        side: const WidgetStatePropertyAll(
          BorderSide(color: AppColors.light900),
        ),
        backgroundColor: WidgetStateProperty.all(AppColors.light100),
        elevation: WidgetStateProperty.all(0),
        hintStyle: WidgetStateProperty.all(
          AppTextStyle.textMdRegular.copyWith(color: AppColors.dark500),
        ),
        textStyle: WidgetStateProperty.all(
          AppTextStyle.textMdRegular.copyWith(color: AppColors.dark900),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
      ),

      searchViewTheme: SearchViewThemeData(
        backgroundColor: AppColors.light100,
        headerHintStyle: AppTextStyle.textMdRegular.copyWith(
          color: AppColors.dark500,
        ),
        headerTextStyle: AppTextStyle.textMdMedium.copyWith(
          color: AppColors.dark900,
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
