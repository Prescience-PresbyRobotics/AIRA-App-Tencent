import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'companion.dart';

/// Original vector scenery: no remote images, camera capture or provider media.
class CompanionPark extends StatefulWidget {
  const CompanionPark({
    super.key,
    required this.activity,
    required this.expression,
    required this.voiceLevel,
    required this.narrow,
  });
  final CompanionActivity activity;
  final CompanionExpression expression;
  final double voiceLevel;
  final bool narrow;

  @override
  State<CompanionPark> createState() => _CompanionParkState();
}

class _CompanionParkState extends State<CompanionPark>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );
  bool moving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    moving =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (moving && !motion.isAnimating) motion.repeat();
    if (!moving) motion.stop();
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'AIRA in a sunny illustrated park',
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = widget.narrow
                ? (constraints.maxHeight * .46).clamp(160.0, 200.0)
                : (constraints.maxHeight * .64).clamp(220.0, 320.0);
            // On a phone the mascot stays below the enlarged self-view. On a
            // desktop it roams the left part of the park, outside that rectangle.
            final maxX = math.max(
              14.0,
              constraints.maxWidth - size - (widget.narrow ? 14 : 250),
            );
            final ground = constraints.maxHeight - size - 10;
            return AnimatedBuilder(
              animation: motion,
              builder: (context, _) {
                final phase = moving ? motion.value * math.pi * 2 : 0.0;
                final stroll = moving ? (1 - math.cos(phase)) / 2 : .4;
                final hop = moving
                    ? math.pow(math.max(0, math.sin(phase * 5)), 4) *
                          (widget.activity == CompanionActivity.speaking
                              ? 4
                              : 10)
                    : 0.0;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: _ParkPainter(phase)),
                    ),
                    Positioned(
                      left: 14 + (maxX - 14) * stroll,
                      top: ground - hop,
                      child: Companion(
                        size: size,
                        activity: widget.activity,
                        expression: widget.expression,
                        voiceLevel: widget.voiceLevel,
                        reducedMotion: !moving,
                      ),
                    ),
                    const Positioned(
                      top: 18,
                      left: 18,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xCCFFF9E9),
                          borderRadius: BorderRadius.all(Radius.circular(14)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            'AIRA’s little park',
                            style: TextStyle(
                              color: Color(0xFF355C46),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    ),
  );
}

class _ParkPainter extends CustomPainter {
  const _ParkPainter(this.phase);
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint();
    canvas.drawRect(
      Offset.zero & size,
      paint
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFBBDCD4), Color(0xFFF6E8C2)],
        ).createShader(Offset.zero & size),
    );
    paint.shader = null;
    canvas.drawCircle(
      Offset(w * .25, h * .20),
      34,
      paint..color = const Color(0xFFF9D774),
    );
    canvas.drawCircle(
      Offset(w * .25, h * .20),
      45,
      paint..color = const Color(0x22FFF5C3),
    );
    void cloud(double x, double y, double scale) {
      paint.color = const Color(0xBBFFFEF5);
      for (final circle in [
        const Offset(-22, 5),
        const Offset(0, -4),
        const Offset(24, 7),
      ]) {
        canvas.drawCircle(
          Offset(x + circle.dx * scale, y + circle.dy * scale),
          19 * scale,
          paint,
        );
      }
    }

    cloud(w * .43 + math.sin(phase) * 8, h * .16, .8);
    cloud(w * .08 + math.cos(phase) * 6, h * .36, .65);
    final farHill = Path()
      ..moveTo(0, h * .58)
      ..quadraticBezierTo(w * .28, h * .32, w * .55, h * .53)
      ..quadraticBezierTo(w * .8, h * .36, w, h * .54)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(farHill, paint..color = const Color(0xFF8DBA90));
    final meadow = Path()
      ..moveTo(0, h * .69)
      ..quadraticBezierTo(w * .5, h * .50, w, h * .66)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(meadow, paint..color = const Color(0xFFB9CF8E));
    final path = Path()
      ..moveTo(w * .55, h * .57)
      ..cubicTo(w * .33, h * .69, w * .82, h * .77, w * .64, h)
      ..lineTo(w * .95, h)
      ..cubicTo(w * .95, h * .75, w * .42, h * .69, w * .58, h * .57)
      ..close();
    canvas.drawPath(path, paint..color = const Color(0xFFEAD7AA));
    void tree(double x, double ground, double scale) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x - 6 * scale,
            ground - 95 * scale,
            12 * scale,
            100 * scale,
          ),
          const Radius.circular(6),
        ),
        paint..color = const Color(0xFFAA8260),
      );
      for (final leaf in [
        const Offset(-22, -94),
        const Offset(22, -100),
        const Offset(0, -127),
      ]) {
        canvas.drawCircle(
          Offset(x + leaf.dx * scale, ground + leaf.dy * scale),
          40 * scale,
          paint..color = const Color(0xFF5F9476),
        );
      }
      canvas.drawCircle(
        Offset(x - 12 * scale, ground - 132 * scale),
        26 * scale,
        paint..color = const Color(0xFF78A77A),
      );
    }

    tree(w * .07, h * .78, h / 470);
    tree(w * .86, h * .72, h / 530);
    // A small bench and flower patches make the scene feel like a place.
    final benchX = w * .49, benchY = h * .62;
    paint.color = const Color(0xFFAF8765);
    for (final y in [0.0, 10.0, 21.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(benchX, benchY + y, 65, 6),
          const Radius.circular(3),
        ),
        paint,
      );
    }
    paint
      ..color = const Color(0xFF6D7C60)
      ..strokeWidth = 3;
    canvas.drawLine(
      Offset(benchX + 8, benchY + 25),
      Offset(benchX + 8, benchY + 38),
      paint,
    );
    canvas.drawLine(
      Offset(benchX + 58, benchY + 25),
      Offset(benchX + 58, benchY + 38),
      paint,
    );
    for (var i = 0; i < 15; i++) {
      final x = (i * 67.0 + 20) % w;
      final y = h * .84 + (i % 3) * 15;
      paint
        ..color = const Color(0xFF739657)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(x, y), Offset(x, y - 9), paint);
      paint.color = i.isEven
          ? const Color(0xFFFAE5B4)
          : const Color(0xFFDF9B8B);
      canvas.drawCircle(Offset(x, y - 10), 4, paint);
    }
    final birdX = w * .36 + math.sin(phase) * 22, birdY = h * .28;
    paint
      ..color = const Color(0xFF668C7B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(
      Path()
        ..moveTo(birdX - 9, birdY)
        ..quadraticBezierTo(
          birdX - 4,
          birdY - 5 - math.sin(phase * 6) * 2,
          birdX,
          birdY,
        )
        ..quadraticBezierTo(birdX + 5, birdY - 6, birdX + 10, birdY),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ParkPainter oldDelegate) => oldDelegate.phase != phase;
}
