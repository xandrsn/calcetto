import 'package:flutter/material.dart';

// skinId format: "{skin}_{hairshape}_{haircolour}_{beard}"
//   skin      : white | tan | brown | black
//   hairshape : bald  | short | long | afro
//   haircolour: black | brown | blond | gray
//   beard     : none  | moustache | goatee | full

const _skinWhite = Color(0xFFF5D0A8);
const _skinTan = Color(0xFFCC8855);
const _skinBrown = Color(0xFF8B5E3C);
const _skinBlack = Color(0xFF3D2314);

const _hairBlack = Color(0xFF1A1A1A);
const _hairBrown = Color(0xFF6B3A2A);
const _hairBlond = Color(0xFFFFD070);
const _hairGray = Color(0xFFAAAAAA);

const _eyeWhite = Color(0xFFF5F5F5);
const _pupil = Color(0xFF111111);
const _mouth = Color(0xFF111111);

final _skinMap = <String, Color>{
  'white': _skinWhite,
  'tan': _skinTan,
  'brown': _skinBrown,
  'black': _skinBlack,
};
final _hairMap = <String, Color>{
  'black': _hairBlack,
  'brown': _hairBrown,
  'blond': _hairBlond,
  'gray': _hairGray,
};

class PixelPlayerPainter extends CustomPainter {
  final String skinId;
  final Color kitColor;
  final bool isCaptain;
  final bool isSelected;

  const PixelPlayerPainter({
    required this.skinId,
    required this.kitColor,
    this.isCaptain = false,
    this.isSelected = false,
  });

  void _r(Canvas c, Paint p, double x, double y, double w, double h, double s) {
    c.drawRect(Rect.fromLTWH(x * s, y * s, w * s, h * s), p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final parts = skinId.split('_');
    final skinKey = parts.isNotEmpty ? parts[0] : 'white';
    final shape = parts.length > 1 ? parts[1] : 'short';
    final colKey = parts.length > 2 ? parts[2] : 'black';
    final beard = parts.length > 3 ? parts[3] : 'none';

    final skinColor = _skinMap[skinKey] ?? _skinWhite;
    final hairColor = _hairMap[colKey] ?? _hairBlack;

    final s = size.width / 16.0;
    final sk = Paint()
      ..color = skinColor
      ..isAntiAlias = false;
    final hr = Paint()
      ..color = hairColor
      ..isAntiAlias = false;
    final ew = Paint()
      ..color = _eyeWhite
      ..isAntiAlias = false;
    final ep = Paint()
      ..color = _pupil
      ..isAntiAlias = false;
    final mt = Paint()
      ..color = _mouth
      ..isAntiAlias = false;
    final cr = Paint()
      ..color = const Color(0xFFFFD700)
      ..isAntiAlias = false;
    final kt = Paint()
      ..color = kitColor
      ..isAntiAlias = false;
    final sl = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..isAntiAlias = false;

    // ── BACK HAIR (afro / long hang-down drawn before face) ──────────────
    if (shape == 'afro') {
      _r(canvas, hr, 0, 1, 16, 6, s); // wide top mass
      _r(canvas, hr, 0, 6, 2, 6, s); // left bulk
      _r(canvas, hr, 14, 6, 2, 6, s); // right bulk
    } else if (shape == 'long') {
      _r(canvas, hr, 1, 8, 1, 6, s); // left hang
      _r(canvas, hr, 14, 8, 1, 6, s); // right hang
    }

    // ── FACE BLOCK  x=2..13, y=3..14 ─────────────────────────────────────
    _r(canvas, sk, 2, 3, 12, 12, s);

    // Ears
    _r(canvas, sk, 1, 7, 1, 3, s);
    _r(canvas, sk, 14, 7, 1, 3, s);

    // ── FRONT HAIR ────────────────────────────────────────────────────────
    switch (shape) {
      case 'short':
        _r(canvas, hr, 2, 1, 12, 4, s); // top cap
        _r(canvas, hr, 1, 3, 1, 3, s); // left side
        _r(canvas, hr, 14, 3, 1, 3, s); // right side
        break;
      case 'long':
        _r(canvas, hr, 2, 1, 12, 4, s); // top cap
        _r(canvas, hr, 1, 3, 1, 10, s); // left side (long)
        _r(canvas, hr, 14, 3, 1, 10, s); // right side (long)
        break;
      case 'afro':
        _r(canvas, hr, 2, 3, 12, 2, s); // hairline strip over forehead
        break;
      case 'bald':
      default:
        break;
    }

    // ── EYEBROWS (hair colour) ─────────────────────────────────────────────
    _r(canvas, hr, 4, 6, 3, 1, s); // left brow
    _r(canvas, hr, 9, 6, 3, 1, s); // right brow

    // ── EYES ──────────────────────────────────────────────────────────────
    _r(canvas, ew, 4, 7, 3, 2, s); // left white
    _r(canvas, ew, 9, 7, 3, 2, s); // right white
    _r(canvas, ep, 5, 7, 2, 2, s); // left pupil
    _r(canvas, ep, 10, 7, 2, 2, s); // right pupil

    // ── NOSE ──────────────────────────────────────────────────────────────
    _r(canvas, ep, 7, 10, 2, 1, s);

    // ── MOUTH ─────────────────────────────────────────────────────────────
    _r(canvas, mt, 5, 12, 6, 1, s);

    // ── BEARD ─────────────────────────────────────────────────────────────
    switch (beard) {
      case 'moustache':
        _r(canvas, hr, 5, 11, 6, 1, s); // upper lip strip
        break;
      case 'goatee':
        _r(canvas, hr, 6, 13, 4, 2, s); // chin patch
        break;
      case 'full':
        _r(canvas, hr, 5, 11, 6, 1, s); // moustache
        _r(canvas, hr, 3, 12, 2, 3, s); // left cheek
        _r(canvas, hr, 11, 12, 2, 3, s); // right cheek
        _r(canvas, hr, 5, 13, 6, 2, s); // chin / jaw
        break;
      default:
        break;
    }

    // ── KIT COLLAR (small strip at bottom) ────────────────────────────────
    _r(canvas, kt, 5, 15, 6, 1, s);

    // ── CAPTAIN CROWN ─────────────────────────────────────────────────────
    if (isCaptain) {
      _r(canvas, cr, 3, 0, 1, 2, s); // left spike
      _r(canvas, cr, 6, 0, 2, 2, s); // centre spike
      _r(canvas, cr, 11, 0, 1, 2, s); // right spike
      _r(canvas, cr, 3, 1, 10, 1, s); // crown base
    }

    // ── SELECTION OVERLAY ─────────────────────────────────────────────────
    if (isSelected) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), sl);
    }
  }

  @override
  bool shouldRepaint(PixelPlayerPainter old) =>
      old.skinId != skinId ||
      old.kitColor != kitColor ||
      old.isCaptain != isCaptain ||
      old.isSelected != isSelected;
}
