import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Original vector interpretation of the coral companion in the supplied mockup.
class Companion extends StatefulWidget {
  final double size;
  final bool animated, speaking, reducedMotion;
  const Companion({
    super.key,
    this.size = 220,
    this.animated = true,
    this.speaking = false,
    this.reducedMotion = false,
  });
  @override
  State<Companion> createState() => _CompanionState();
}

class _CompanionState extends State<Companion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  bool _motionAllowed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant Companion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    _motionAllowed =
        widget.animated &&
        !widget.reducedMotion &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (_motionAllowed && !_animation.isAnimating) {
      _animation.repeat();
    } else if (!_motionAllowed && _animation.isAnimating) {
      _animation.stop();
    }
  }

  void _greet() {
    if (!_motionAllowed) return;
    _animation.value = 0;
    _animation.repeat();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'AIRA, your coral-coloured AI companion',
    image: true,
    child: GestureDetector(
      onTap: _motionAllowed ? _greet : null,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            final phase = _motionAllowed ? _animation.value : 0.0;
            final breath = _motionAllowed ? math.sin(phase * math.pi * 2) : 0.0;
            return Transform.translate(
              offset: Offset(0, breath * 4),
              child: Transform.rotate(
                angle: breath * .025,
                child: Transform.scale(
                  scale: 1 + breath * .018,
                  child: CustomPaint(
                    painter: _CompanionPainter(
                      widget.speaking,
                      phase,
                      _motionAllowed,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _CompanionPainter extends CustomPainter {
  final bool speaking, motion;
  final double phase;
  _CompanionPainter(this.speaking, this.phase, this.motion);
  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.scale(s.width / 240, s.height / 240);
    c.drawOval(
      const Rect.fromLTWH(49, 205, 151, 15),
      Paint()
        ..color = AiraColors.forest.withValues(alpha: .08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    final body = Path()
      ..moveTo(54, 179)
      ..cubicTo(35, 142, 45, 87, 69, 65)
      ..cubicTo(90, 45, 157, 39, 181, 69)
      ..cubicTo(208, 105, 209, 167, 187, 192)
      ..cubicTo(173, 212, 71, 217, 54, 179)
      ..close();
    final grad = const RadialGradient(
      center: Alignment(-.55, -.6),
      radius: 1.4,
      colors: [Color(0xFFFFC9A4), Color(0xFFFFAB87), Color(0xFFE78668)],
    );
    final p = Paint()
      ..shader = grad.createShader(const Rect.fromLTWH(35, 40, 175, 170));
    c.drawOval(const Rect.fromLTWH(69, 185, 44, 33), p);
    c.drawOval(const Rect.fromLTWH(144, 185, 42, 32), p);
    c.drawPath(body, p);
    c.save();
    c.translate(123, 52);
    c.rotate(-.45);
    c.drawOval(const Rect.fromLTWH(-16, -30, 21, 40), p);
    c.restore();
    c.save();
    c.translate(127, 49);
    c.rotate(.45);
    c.drawOval(const Rect.fromLTWH(-2, -33, 23, 40), p);
    c.restore();
    c.save();
    c.translate(57, 136);
    final wave = motion && phase < .3
        ? math.sin(phase / .3 * math.pi * 4)
        : 0.0;
    c.rotate(-.65 - wave * .55);
    c.drawOval(const Rect.fromLTWH(-20, -37, 34, 65), p);
    c.restore();
    c.save();
    c.translate(188, 160);
    c.rotate(.48);
    c.drawOval(const Rect.fromLTWH(-18, -24, 35, 53), p);
    c.restore();
    final dark = Paint()..color = const Color(0xFF322925);
    final blink = motion
        ? (1 - (phase - .48).abs() / .025).clamp(0.0, 1.0)
        : 0.0;
    final eyeHeight = 19 * (1 - blink * .93);
    c.drawOval(
      Rect.fromCenter(
        center: const Offset(96, 108.5),
        width: 12,
        height: eyeHeight,
      ),
      dark,
    );
    c.drawOval(
      Rect.fromCenter(
        center: const Offset(156, 110.5),
        width: 12,
        height: eyeHeight,
      ),
      dark,
    );
    if (blink < .5) {
      c.drawCircle(
        const Offset(94, 104),
        2,
        Paint()..color = Colors.white.withValues(alpha: .65),
      );
      c.drawCircle(
        const Offset(154, 106),
        2,
        Paint()..color = Colors.white.withValues(alpha: .65),
      );
    }
    final blush = Paint()
      ..color = const Color(0xFFF37963).withValues(alpha: .34)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    c.drawOval(const Rect.fromLTWH(74, 120, 26, 13), blush);
    c.drawOval(const Rect.fromLTWH(151, 122, 27, 13), blush);
    final speechOpen = speaking && motion
        ? 5 + math.sin(phase * math.pi * 20) * 5
        : 0.0;
    final mouth = Path()
      ..moveTo(114, 124)
      ..quadraticBezierTo(128, 130, 141, 125)
      ..cubicTo(143, 150 + speechOpen, 112, 155, 114, 124);
    c.drawPath(mouth, Paint()..color = const Color(0xFF73352B));
    c.drawOval(
      const Rect.fromLTWH(119, 138, 18, 8),
      Paint()..color = const Color(0xFFEE8D78),
    );
    final sparkle = Paint()
      ..color = const Color(0xFFEACB71)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    c.drawLine(const Offset(35, 81), const Offset(28, 72), sparkle);
    c.drawLine(const Offset(28, 98), const Offset(15, 94), sparkle);
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _CompanionPainter old) =>
      old.speaking != speaking ||
      old.motion != motion ||
      (motion && old.phase != phase);
}
