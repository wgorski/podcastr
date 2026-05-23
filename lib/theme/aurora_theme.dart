import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Aurora theme — the default variant from the design canvas (`screens.jsx`)
/// merged with the `cyanviolet` palette tweak from `app.jsx`.
class AuroraTheme {
  static const bg = Color(0xFF05070F);
  static const bgGradientInner = Color(0xFF0D1530); // radial center
  static const surface = Color(0xFF0D1224);
  static const surface2 = Color(0xFF141A30);
  static const border = Color(0x1AA0C8FF); // rgba(160,200,255,0.10)
  static const border2 = Color(0x2EA0C8FF); // rgba(160,200,255,0.18)
  static const text = Color(0xFFE8EFFF);
  static const muted = Color(0xFF8A98C2);
  static const dim = Color(0xFF525C80);
  static const accent = Color(0xFF7DD3FC);
  static const accentSoft = Color(0x297DD3FC); // rgba(125,211,252,0.16)
  static const onAccent = Color(0xFF03102B);
  static const accentEnd = Color(0xFFC084FC);

  /// 135deg gradient — matches `linear-gradient(135deg, #7dd3fc, #c084fc)`.
  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentEnd],
  );

  static const cardRadius = 20.0;
  static const artRadius = 16.0;
  static const titleOverlay = true;

  static TextStyle display({double size = 32, FontWeight weight = FontWeight.w700, Color? color, double letterSpacing = -0.6}) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color ?? text,
      letterSpacing: letterSpacing,
      height: 1.0,
    );
  }

  static TextStyle body({double size = 13, FontWeight weight = FontWeight.w500, Color? color, double? height, double letterSpacing = 0}) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color ?? text,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle mono({double size = 11, FontWeight weight = FontWeight.w500, Color? color, double letterSpacing = 0.2}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      color: color ?? text,
      letterSpacing: letterSpacing,
    );
  }

  /// The full-page radial background gradient.
  static BoxDecoration get backgroundDecoration {
    return const BoxDecoration(
      color: bg,
      gradient: RadialGradient(
        center: Alignment(0, -1),
        radius: 1.1,
        colors: [bgGradientInner, bg],
        stops: [0.0, 0.55],
      ),
    );
  }
}
