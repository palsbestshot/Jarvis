import 'package:flutter/material.dart';
import '../core/theme.dart';

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
    return Text(
      'JARVIS',
      style: JarvisTheme.displayLarge.copyWith(
        fontSize: fontSize,
        color: color ?? JarvisTheme.textPrimary,
      ),
    );
  }
}