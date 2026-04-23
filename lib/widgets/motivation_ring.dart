import 'package:flutter/material.dart';
import '../core/theme.dart';

class MotivationRing extends StatelessWidget {
  final int completed;
  final int total;
  final double size;
  final Color? ringColor;
  final Color? backgroundColor;

  const MotivationRing({
    super.key,
    required this.completed,
    required this.total,
    this.size = 80.0,
    this.ringColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? completed / total : 0.0;
    final accentColor = ringColor ?? JarvisTheme.pallavAccent;
    final bgColor = backgroundColor ?? JarvisTheme.surface2;
    
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background ring
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              progress: 1.0,
              color: bgColor,
              strokeWidth: 8.0,
            ),
          ),
          
          // Progress ring
          if (progress > 0)
            CustomPaint(
              size: Size(size, size),
              painter: _RingPainter(
                progress: progress,
                color: accentColor,
                strokeWidth: 8.0,
              ),
            ),
          
          // Center text — padded so it never crosses the ring. Shorter
          // phrases + fitted sizing so it never overflows on small rings.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size * 0.15),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$completed/$total',
                  style: TextStyle(
                    fontSize: size * 0.22,
                    fontWeight: FontWeight.w700,
                    color: JarvisTheme.textPrimary,
                    fontFamily: 'DMSans',
                    height: 1.0,
                  ),
                ),
                SizedBox(height: size * 0.04),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _getMotivationalText(progress),
                    style: TextStyle(
                      fontSize: size * 0.11,
                      color: JarvisTheme.textMuted,
                      fontFamily: 'DMSans',
                      height: 1.15,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getMotivationalText(double progress) {
    // Short, 2-word phrases (max ~16 chars) that safely fit the ring
    // center regardless of size. Longer taglines overflowed on the
    // board greeting at size 80 — especially on narrow screens.
    final percentage = (progress * 100).round();
    if (percentage == 0) return 'Let\'s go';
    if (percentage <= 30) return 'Good start';
    if (percentage <= 60) return 'Halfway';
    if (percentage < 100) return 'Finish strong';
    return 'Nailed it 💪';
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    
    // Draw the arc
    final sweepAngle = 2 * 3.14159 * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159 / 2, // Start at top
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}