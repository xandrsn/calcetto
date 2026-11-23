import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PixelButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final Color textColor;
  final double fontSize;
  final EdgeInsets padding;
  final bool selected;

  const PixelButton({
    super.key,
    required this.label,
    this.onTap,
    this.color = kAccentGreen,
    this.textColor = Colors.white,
    this.fontSize = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    this.selected = false,
  });

  @override
  State<PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<PixelButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    final bgColor = widget.selected ? kAccentGreen : widget.color;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        padding: widget.padding,
        decoration: BoxDecoration(
          color: disabled
              ? kSurface2
              : bgColor.withValues(alpha: _pressed ? 0.80 : 1.0),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: disabled ? kBorder : bgColor,
            width: 1,
          ),
        ),
        child: Text(
          widget.label.toUpperCase(),
          style: TextStyle(
            fontFamily: kFontUI,
            fontSize: widget.fontSize,
            fontWeight: FontWeight.w600,
            color: disabled ? kTextDim : widget.textColor,
            height: 1.25,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
