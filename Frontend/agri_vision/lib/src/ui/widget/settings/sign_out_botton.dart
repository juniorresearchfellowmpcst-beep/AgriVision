import 'package:flutter/material.dart';
import 'package:agri_vision/src/src.dart';

/// Full-width destructive sign-out button used at the bottom of
/// the Settings screen.
class SignOutButton extends StatelessWidget {
  const SignOutButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      label: 'Sign Out',
      startIcon: Icons.logout_rounded,
      color: const Color(0xFFFFEEEE),
      pressedColor: const Color(0xFFFFDDDD),
      showBorder: true,
      borderColor: const Color(0xFFFFCCCC),
      pressedBorderColor: AppColors.themeError,
      iconColor: AppColors.themeError,
      pressedIconColor: AppColors.themeError,
      textColor: AppColors.themeError,
      pressedTextColor: AppColors.themeError,
      textStyle: AppTextStyle.textMdSemibold,
      width: double.infinity,
      height: 50,
      borderRadius: AppRadius.lg,
      mainAxisAlignment: MainAxisAlignment.center,
      onPressed: onTap ?? () {},
    );
  }
}
