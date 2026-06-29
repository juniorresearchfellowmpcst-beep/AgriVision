import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';

class Toast {
  static final GlobalKey<ScaffoldMessengerState> _scaffoldKey =
      GlobalKey<ScaffoldMessengerState>();

  static GlobalKey<ScaffoldMessengerState> get scaffoldKey => _scaffoldKey;

  static const _defaultDuration = Duration(seconds: 3);
  static const _padding = EdgeInsets.symmetric(horizontal: 10, vertical: 10);

  static void error(
    String message,
    Color backgroundColor, {
    Duration? duration,
  }) => _showToast(
    message,
    icon: const Icon(Icons.error, color: AppColors.light100),
    backgroundColor: backgroundColor,
    textColor: AppColors.light100,
    duration: duration,
  );

  static void success(
    String message,
    Color backgroundColor, {
    Duration? duration,
  }) => _showToast(
    message,
    icon: const Icon(Icons.check_circle, color: AppColors.light100),
    backgroundColor: backgroundColor,
    textColor: AppColors.light100,
    duration: duration,
  );

  static void warning(
    String message,
    Color backgroundColor, {
    Duration? duration,
  }) => _showToast(
    message,
    icon: const Icon(Icons.warning, color: AppColors.light100),
    backgroundColor: backgroundColor,
    duration: duration,
  );

  static void show(
    String message, {
    Duration? duration,
    Widget? icon,
    Color? backgroundColor,
    Color? textColor,
  }) => _showToast(
    message,
    icon: icon,
    backgroundColor: backgroundColor ?? AppColors.light500,
    duration: duration,
    textColor: textColor,
  );

  static void _showToast(
    String message, {
    Widget? icon,
    required Color backgroundColor,
    Duration? duration,
    Color? textColor,
  }) {
    _scaffoldKey.currentState?.showSnackBar(
      SnackBar(
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // if (icon != null) ...[icon, const SizedBox(width: 10)],
            Flexible(
              child: Text(
                message,
                maxLines: 10,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.textMdMedium.copyWith(
                  color: textColor ?? AppColors.dark900,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: duration ?? _defaultDuration,
        dismissDirection: DismissDirection.startToEnd,
        behavior: SnackBarBehavior.floating,
        padding: _padding,
        margin: const EdgeInsets.all(20),
        elevation: 10,
      ),
    );
  }
}
