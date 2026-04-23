import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../core/theme.dart';

/// The "JARVIS" wordmark.
///
/// Pallav's Android APK renders it in Instrument Serif with the light
/// cream [JarvisTheme.textPrimary] — unchanged. Rakhi's Web PWA wraps the
/// wordmark in a soft pink vertical gradient (her #D47BA0 accent at the
/// top, a deeper rose below), since the surrounding theme is light.
///
/// Pass a [color] to override the default for a one-off use site.
class JarvisLogo extends StatelessWidget {
  final double fontSize;
  final Color? color;

  const JarvisLogo({
    super.key,
    this.fontSize = 40,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = JarvisTheme.displayLarge.copyWith(
      fontSize: fontSize,
      letterSpacing: fontSize > 24 ? 2.0 : 1.0,
      color: color ?? JarvisTheme.textPrimary,
    );

    // If the caller pinned a colour we honour it (used by some legacy
    // sites). Otherwise on web we render the pink-gradient variant.
    if (kIsWeb && color == null) {
      return ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFD47BA0), // rakhiAccent — top, lighter rose
            Color(0xFF9B4B6D), // deeper plum at the bottom for contrast
          ],
        ).createShader(bounds),
        blendMode: BlendMode.srcIn,
        child: Text(
          'JARVIS',
          style: textStyle.copyWith(color: Colors.white),
        ),
      );
    }

    return Text('JARVIS', style: textStyle);
  }
}
