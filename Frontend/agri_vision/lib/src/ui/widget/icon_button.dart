import 'package:flutter/material.dart';

/// A general-purpose button that supports:
///  - an icon at the start and/or end (both optional)
///  - configurable background color (normal + pressed states)
///  - configurable border (normal + selected/pressed states)
///  - icon color that changes when pressed/selected
///  - a `selected` flag for toggle/role-style buttons (like the
///    Operator / Field Engineer / Administrator cards on the
///    Sign In page) in addition to plain momentary press feedback.
///
/// Internally it's a [StatefulWidget] only to track the live
/// "currently being pressed" state via [GestureDetector] —
/// everything else is driven by the props you pass in.
class AppIconButton extends StatefulWidget {
  /// Button label. Pass null/empty for an icon-only button.
  final String? label;

  /// Optional second line shown under [label], smaller and muted
  /// (e.g. a role description like "Fly & monitor missions").
  final String? subtitle;

  /// Icon shown before the label.
  final IconData? startIcon;

  /// Icon shown after the label (e.g. a check mark, chevron).
  final IconData? endIcon;

  /// Called when the button is tapped.
  final VoidCallback? onPressed;

  /// Whether this button is in a "selected" state (e.g. a chosen
  /// role). When true, [selectedColor]/[selectedBorderColor]/
  /// [selectedIconColor]/[selectedTextColor] are used instead of
  /// the normal ones — independent of whether it's currently
  /// being pressed.
  final bool selected;

  // --- Background ---
  final Color color;
  final Color pressedColor;
  final Color selectedColor;
  final Color disabledColor;

  // --- Border ---
  final bool showBorder;
  final Color borderColor;
  final Color pressedBorderColor;
  final Color selectedBorderColor;
  final double borderWidth;

  // --- Icon ---
  final Color iconColor;
  final Color pressedIconColor;
  final Color selectedIconColor;
  final double iconSize;

  // --- Text ---
  final TextStyle? textStyle;
  final Color textColor;
  final Color pressedTextColor;
  final Color selectedTextColor;
  final TextStyle? subtitleStyle;
  final Color subtitleColor;

  // --- Shape / sizing ---
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double? height;
  final double? width;
  final MainAxisAlignment mainAxisAlignment;

  const AppIconButton({
    super.key,
    this.label,
    this.subtitle,
    this.startIcon,
    this.endIcon,
    this.onPressed,
    this.selected = false,

    this.color = const Color(0xFFFFFFFF),
    this.pressedColor = const Color(0xFFF0F4EF),
    this.selectedColor = const Color(0xFFEAF3E8),
    this.disabledColor = const Color(0xFFE8E9F1),

    this.showBorder = true,
    this.borderColor = const Color(0xFFE3E6E2),
    this.pressedBorderColor = const Color(0xFF569150),
    this.selectedBorderColor = const Color(0xFF569150),
    this.borderWidth = 1.2,

    this.iconColor = const Color(0xFF6B7A72),
    this.pressedIconColor = const Color(0xFF569150),
    this.selectedIconColor = const Color(0xFF569150),
    this.iconSize = 20,

    this.textStyle,
    this.textColor = const Color(0xFF1A1F1C),
    this.pressedTextColor = const Color(0xFF1A1F1C),
    this.selectedTextColor = const Color(0xFF1A1F1C),
    this.subtitleStyle,
    this.subtitleColor = const Color(0xFF6B7A72),

    this.borderRadius = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.height,
    this.width,
    this.mainAxisAlignment = MainAxisAlignment.start,
  });

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _isPressed = false;

  bool get _isDisabled => widget.onPressed == null;

  Color get _backgroundColor {
    if (_isDisabled) return widget.disabledColor;
    if (widget.selected) return widget.selectedColor;
    if (_isPressed) return widget.pressedColor;
    return widget.color;
  }

  Color get _borderColor {
    if (widget.selected) return widget.selectedBorderColor;
    if (_isPressed) return widget.pressedBorderColor;
    return widget.borderColor;
  }

  Color get _iconColor {
    if (widget.selected) return widget.selectedIconColor;
    if (_isPressed) return widget.pressedIconColor;
    return widget.iconColor;
  }

  Color get _textColor {
    if (widget.selected) return widget.selectedTextColor;
    if (_isPressed) return widget.pressedTextColor;
    return widget.textColor;
  }

  void _setPressed(bool value) {
    if (_isDisabled) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (widget.startIcon != null) ...[
        Icon(widget.startIcon, size: widget.iconSize, color: _iconColor),
        if (widget.label != null && widget.label!.isNotEmpty)
          const SizedBox(width: 10),
      ],
      if (widget.label != null && widget.label!.isNotEmpty)
        Flexible(
          child: widget.subtitle == null
              ? Text(
                  widget.label!,
                  style:
                      (widget.textStyle ??
                              const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ))
                          .copyWith(color: _textColor),
                  overflow: TextOverflow.ellipsis,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label!,
                      style:
                          (widget.textStyle ??
                                  const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ))
                              .copyWith(color: _textColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      style:
                          (widget.subtitleStyle ??
                                  const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                  ))
                              .copyWith(color: widget.subtitleColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
        ),
      if (widget.endIcon != null) ...[
        if (widget.label != null && widget.label!.isNotEmpty)
          const SizedBox(width: 10),
        Icon(widget.endIcon, size: widget.iconSize, color: _iconColor),
      ],
    ];

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: widget.height,
        width: widget.width,
        padding: widget.padding,
        decoration: BoxDecoration(
          color: _backgroundColor,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: widget.showBorder
              ? Border.all(color: _borderColor, width: widget.borderWidth)
              : null,
        ),
        child: Row(
          mainAxisSize: widget.width == null
              ? MainAxisSize.min
              : MainAxisSize.max,
          mainAxisAlignment: widget.mainAxisAlignment,
          children: children,
        ),
      ),
    );
  }
}
