import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The CALCETTO brand mark: a pixel football beside the wordmark.
///
/// This is the one place the blocky arcade font ([kFontLogo]) is still used —
/// everything else uses the compact UI font. Two layouts:
///  - [CalcettoLogo] — full lockup (ball + big gradient wordmark + tagline),
///    for the splash screen.
///  - [CalcettoLogo.bar] — small inline lockup for app bars.
class CalcettoLogo extends StatelessWidget {
  final double wordSize;
  final bool showTagline;
  final bool horizontal;

  const CalcettoLogo({
    super.key,
    this.wordSize = 30,
    this.showTagline = true,
    this.horizontal = false,
  });

  /// Compact horizontal lockup for app bars.
  const CalcettoLogo.bar({super.key, this.wordSize = 14})
    : showTagline = false,
      horizontal = true;

  @override
  Widget build(BuildContext context) {
    final ball = SizedBox(
      width: wordSize * 1.15,
      height: wordSize * 1.15,
      child: CustomPaint(painter: PixelBallPainter()),
    );

    final word = ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [kAccentGreen, kAccentYellow],
      ).createShader(bounds),
      child: Text(
        'CALCETTO',
        style: TextStyle(
          fontFamily: kFontLogo,
          fontSize: wordSize,
          color: Colors.white,
          height: 1.1,
          letterSpacing: wordSize * 0.06,
        ),
      ),
    );

    if (horizontal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ball,
          SizedBox(width: wordSize * 0.5),
          word,
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ball,
        SizedBox(height: wordSize * 0.55),
        word,
        if (showTagline) ...[
          SizedBox(height: wordSize * 0.4),
          Text(
            'LALIGA FANTASY',
            style: TextStyle(
              fontFamily: kFontUI,
              fontSize: wordSize * 0.34,
              color: kTextMuted,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// A crisp pixel-art football, scaled to fill its canvas.
class PixelBallPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 8;
    void r(double x, double y, Color c) {
      canvas.drawRect(
        Rect.fromLTWH(x * s, y * s, s + 0.5, s + 0.5),
        Paint()
          ..color = c
          ..isAntiAlias = false,
      );
    }

    const w = Colors.white;
    const b = Color(0xFF15151f);
    // 8x8 pixel football.
    r(3, 0, w);
    r(4, 0, w);
    r(2, 1, w);
    r(3, 1, b);
    r(4, 1, w);
    r(5, 1, w);
    r(1, 2, w);
    r(2, 2, w);
    r(3, 2, w);
    r(4, 2, b);
    r(5, 2, w);
    r(6, 2, w);
    r(1, 3, w);
    r(2, 3, b);
    r(3, 3, w);
    r(4, 3, w);
    r(5, 3, b);
    r(6, 3, w);
    r(1, 4, w);
    r(2, 4, w);
    r(3, 4, b);
    r(4, 4, w);
    r(5, 4, w);
    r(6, 4, w);
    r(1, 5, w);
    r(2, 5, w);
    r(3, 5, w);
    r(4, 5, b);
    r(5, 5, w);
    r(6, 5, w);
    r(2, 6, w);
    r(3, 6, w);
    r(4, 6, w);
    r(5, 6, w);
    r(3, 7, w);
    r(4, 7, w);
  }

  @override
  bool shouldRepaint(_) => false;
}
