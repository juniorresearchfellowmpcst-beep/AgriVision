import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const Color primary = Color(0xFF569150);
  static const Color primary2 = Color(0xFF569150);
  static const Color primary3 = Color(0xFFb2ceb0);
  static const Color primary4 = Color(0xFFbbd3b9);
  static const Color primary5 = Color(0xFFd0dcce);
  static const Color primary6 = Color(0xFF5d9c59);
  static const Color primaryFade = Color(0xFFd0e2cf);
  static const Color themeSecondary = Color(0x66569150);
  static const Color themeSuccess = Color(0xFF5D9C59);
  static const Color themeError = Color(0xFFE64848);
  static const Color themeWarning = Color(0xFFE7B10A);
  static const Color themeToolTipIcon = Color(0xFF000000);

  static const Color secondary = Color(0xFFededed);
  static const Color tertiary = Color(0xFFF8F8F8);

  static const Color googleColor = Color(0xFF318AF5);

  static const Color darkGreen = Color(0xFF1F4D38);
  static const Color background = Color(0xFFF4F6F4);

  static const Color light100 = Color(0xFFFFFFFF);
  static const Color light300 = Color(0xFFF8F9FE);
  static const Color light500 = Color(0xFFE8E9F1);
  static const Color light700 = Color(0xFFD4D6DD);
  static const Color light900 = Color(0xFFC5C6CC);
  static const Color light2 = Color(0xFFececec);

  static const Color dark100 = Color(0xFF8F9098);
  static const Color dark300 = Color(0xFF71727A);
  static const Color dark500 = Color(0xFF494A50);
  static const Color dark700 = Color(0xFF2F3036);
  static const Color dark900 = Color(0xFF1F2024);

  static BoxShadow boxShadow = BoxShadow(
    color: AppColors.dark900.withAlpha(50),
    offset: const Offset(0, 1),
    blurRadius: 5,
    spreadRadius: 1,
  );
}
