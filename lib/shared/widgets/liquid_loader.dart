import 'dart:math' as math;
import 'package:flutter/material.dart';

// ✅ 1. Create the custom painter for the dot animation
class _DotSpinnerPainter extends CustomPainter {
  final Color color;
  final double animationValue;
  static const int dotCount = 8;

  _DotSpinnerPainter({
    required this.color,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final double dotRadius = radius / 4;
    final Paint paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < dotCount; i++) {
      // Calculate the angle for each dot
      final double angle = (i * 2 * math.pi / dotCount) - (math.pi / 2);

      // Calculate position of the dot
      final double x = radius + (radius - dotRadius) * math.cos(angle);
      final double y = radius + (radius - dotRadius) * math.sin(angle);

      // Calculate opacity for the trailing effect
      // The (i + 1) / dotCount gives a base opacity from light to dark
      // The -animationValue shifts this pattern around the circle
      double opacity = ((i + 1) / dotCount) - animationValue;
      if (opacity < 0) opacity += 1.0;

      // Ensure opacity is within a good range (e.g., 0.2 to 1.0)
      final double effectiveOpacity = 0.2 + (0.8 * opacity);

      paint.color = color.withValues(alpha: effectiveOpacity);
      canvas.drawCircle(Offset(x, y), dotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DotSpinnerPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.color != color;
  }
}

// ✅ 2. Create the animated widget that uses the painter
class CustomLoadingIndicator extends StatefulWidget {
  final double size;
  final Color color;

  const CustomLoadingIndicator({
    super.key,
    this.size = 40.0,
    this.color = Colors.blue,
  });

  @override
  State<CustomLoadingIndicator> createState() => _CustomLoadingIndicatorState();
}

class _CustomLoadingIndicatorState extends State<CustomLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(); // Loop the animation
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _DotSpinnerPainter(
              color: widget.color,
              animationValue: _controller.value,
            ),
          );
        },
      ),
    );
  }
}

// ✅ 3. Create the global RiskRadarLoader widget
// This is the widget you will use throughout your app.
class RiskRadarLoader extends StatelessWidget {
  final Color? color;
  final double size;

  const RiskRadarLoader({
    super.key,
    this.color,
    this.size = 40.0,
  });

  @override
  Widget build(BuildContext context) {
    // Default color is your app's teal, but can be overridden (e.g., for buttons)
    final effectiveColor = color ?? const Color(0xFF1B3D3D);

    return Center(
      child: CustomLoadingIndicator(
        size: size,
        color: effectiveColor,
      ),
    );
  }
}
