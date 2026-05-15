import 'dart:math' as math;
import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════════════════════════════
// PUBLIC WIDGET — Use this everywhere in the app
// RiskRadarLoader(size: 48) or RiskRadarLoader(size: 24, color: Colors.white)
// ══════════════════════════════════════════════════════════════════════════════
class RiskRadarLoader extends StatelessWidget {
  final Color? color;
  final double size;

  const RiskRadarLoader({
    super.key,
    this.color,
    this.size = 48.0,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? const Color(0xFF1B3D3D);
    return Center(
      child: _RadarSweepLoader(size: size, color: effectiveColor),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FULL SCREEN LOADING OVERLAY — Use for page-level loading
// RiskRadarLoadingScreen(message: "Loading dashboard...")
// ══════════════════════════════════════════════════════════════════════════════
class RiskRadarLoadingScreen extends StatelessWidget {
  final String message;

  const RiskRadarLoadingScreen({
    super.key,
    this.message = 'Loading...',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const RiskRadarLoader(size: 72),
            const SizedBox(height: 28),
            Text(
              message,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// ══════════════════════════════════════════════════════════════════════════════
// INTERNAL ANIMATED WIDGET
// ══════════════════════════════════════════════════════════════════════════════
class _RadarSweepLoader extends StatefulWidget {
  final double size;
  final Color color;

  const _RadarSweepLoader({
    required this.size,
    required this.color,
  });

  @override
  State<_RadarSweepLoader> createState() => _RadarSweepLoaderState();
}

class _RadarSweepLoaderState extends State<_RadarSweepLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
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
            painter: _RadarSweepPainter(
              color: widget.color,
              animationValue: _controller.value,
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTER — Draws the radar sweep
// ══════════════════════════════════════════════════════════════════════════════
class _RadarSweepPainter extends CustomPainter {
  final Color color;
  final double animationValue;

  // Gold accent for the sweep beam
  static const Color _gold = Color(0xFFE6A050);

  _RadarSweepPainter({
    required this.color,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // ── 1. Outer circle rings ─────────────────────────────────────────────
    _drawRings(canvas, center, radius);

    // ── 2. Cross hairs ───────────────────────────────────────────────────
    _drawCrosshairs(canvas, center, radius);

    // ── 3. Sweep trail (fading arc behind the beam) ───────────────────────
    _drawSweepTrail(canvas, center, radius);

    // ── 4. Rotating beam line ─────────────────────────────────────────────
    _drawBeam(canvas, center, radius);

    // ── 5. Blip dots (appear and fade as beam passes) ─────────────────────
    _drawBlips(canvas, center, radius);

    // ── 6. Center dot ─────────────────────────────────────────────────────
    _drawCenterDot(canvas, center);
  }

  void _drawRings(Canvas canvas, Offset center, double radius) {
    final ringPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw 3 concentric rings
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * (i / 3), ringPaint);
    }

    // Outer ring slightly brighter
    canvas.drawCircle(
      center,
      radius * 0.98,
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawCrosshairs(Canvas canvas, Offset center, double radius) {
    final crossPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..strokeWidth = 0.8;

    // Horizontal line
    canvas.drawLine(
      Offset(center.dx - radius * 0.95, center.dy),
      Offset(center.dx + radius * 0.95, center.dy),
      crossPaint,
    );

    // Vertical line
    canvas.drawLine(
      Offset(center.dx, center.dy - radius * 0.95),
      Offset(center.dx, center.dy + radius * 0.95),
      crossPaint,
    );

    // Diagonal lines
    canvas.drawLine(
      Offset(center.dx - radius * 0.67, center.dy - radius * 0.67),
      Offset(center.dx + radius * 0.67, center.dy + radius * 0.67),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx + radius * 0.67, center.dy - radius * 0.67),
      Offset(center.dx - radius * 0.67, center.dy + radius * 0.67),
      crossPaint,
    );
  }

  void _drawSweepTrail(Canvas canvas, Offset center, double radius) {
    // Current angle of the beam
    final sweepAngle = animationValue * 2 * math.pi;

    // Draw a fading arc behind the beam (270 degrees of trail)
    const trailSweep = (3 * math.pi / 2); // 270 degrees

    // We draw multiple gradient arcs for smooth fade
    const segments = 30;
    for (int i = 0; i < segments; i++) {
      final segmentFraction = i / segments;
      final opacity = segmentFraction * 0.25; // Fades from 0 → 0.25

      final startAngle = sweepAngle - trailSweep + (segmentFraction * trailSweep);
      final segmentSweep = trailSweep / segments;

      final trailPaint = Paint()
        ..color = _gold.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * 0.92),
        startAngle,
        segmentSweep + 0.02,
        true,
        trailPaint,
      );
    }
  }

  void _drawBeam(Canvas canvas, Offset center, double radius) {
    final sweepAngle = animationValue * 2 * math.pi;

    // Beam end point
    final beamEnd = Offset(
      center.dx + radius * 0.92 * math.cos(sweepAngle),
      center.dy + radius * 0.92 * math.sin(sweepAngle),
    );

    // Glowing beam line
    canvas.drawLine(
      center,
      beamEnd,
      Paint()
        ..color = _gold.withValues(alpha: 0.9)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // Bright tip glow at beam end
    canvas.drawCircle(
      beamEnd,
      3.0,
      Paint()..color = _gold.withValues(alpha: 0.95),
    );

    // Outer glow
    canvas.drawCircle(
      beamEnd,
      5.5,
      Paint()..color = _gold.withValues(alpha: 0.3),
    );
  }

  void _drawBlips(Canvas canvas, Offset center, double radius) {
    // Fixed blip positions (angle, distance from center)
    final blips = [
      (math.pi * 0.3, 0.55),
      (math.pi * 0.85, 0.72),
      (math.pi * 1.4, 0.45),
      (math.pi * 1.75, 0.65),
    ];

    final sweepAngle = animationValue * 2 * math.pi;

    for (final blip in blips) {
      final blipAngle = blip.$1;
      final blipDistance = blip.$2;

      // Calculate how far the beam has passed this blip
      double angleDiff = sweepAngle - blipAngle;
      // Normalize to 0 → 2π
      while (angleDiff < 0) {
        angleDiff += 2 * math.pi;
      }
      while (angleDiff > 2 * math.pi) {
        angleDiff -= 2 * math.pi;
      }

      // Blip is visible for 90 degrees after beam passes it
      final visibleRange = math.pi / 2;
      if (angleDiff < visibleRange) {
        final opacity = (1.0 - (angleDiff / visibleRange)) * 0.9;

        final blipPos = Offset(
          center.dx + radius * blipDistance * math.cos(blipAngle),
          center.dy + radius * blipDistance * math.sin(blipAngle),
        );

        // Outer glow
        canvas.drawCircle(
          blipPos,
          5.0,
          Paint()..color = _gold.withValues(alpha: opacity * 0.3),
        );

        // Inner dot
        canvas.drawCircle(
          blipPos,
          2.5,
          Paint()..color = _gold.withValues(alpha: opacity),
        );
      }
    }
  }

  void _drawCenterDot(Canvas canvas, Offset center) {
    // Pulsing center dot
    final pulseOpacity = 0.6 + (0.4 * math.sin(animationValue * 4 * math.pi));

    // Outer ring
    canvas.drawCircle(
      center,
      5.0,
      Paint()
        ..color = _gold.withValues(alpha: pulseOpacity * 0.4)
        ..style = PaintingStyle.fill,
    );

    // Inner dot
    canvas.drawCircle(
      center,
      3.0,
      Paint()
        ..color = _gold.withValues(alpha: pulseOpacity)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarSweepPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.color != color;
  }
}
