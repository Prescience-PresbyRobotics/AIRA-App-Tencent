import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// Original vector interpretation of the coral companion in the supplied mockup.
class Companion extends StatefulWidget {
  final double size;
  final bool animated;
  final bool speaking;
  const Companion(
      {super.key,
      this.size = 220,
      this.animated = true,
      this.speaking = false});
  @override
  State<Companion> createState() => _CompanionState();
}

class _CompanionState extends State<Companion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))
        ..repeat(reverse: true);
  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
      label: 'AIRA, your coral-coloured AI companion',
      image: true,
      child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                final move =
                    widget.animated && !MediaQuery.of(context).disableAnimations
                        ? _animation.value
                        : 0.5;
                return Transform.translate(
                    offset: Offset(0, math.sin(move * math.pi * 2) * 3),
                    child: CustomPaint(
                        painter: _CompanionPainter(widget.speaking, move)));
              })));
}

class _CompanionPainter extends CustomPainter {
  final bool speaking;
  final double phase;
  _CompanionPainter(this.speaking, this.phase);
  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.scale(s.width / 240, s.height / 240);
    c.drawOval(
        const Rect.fromLTWH(49, 205, 151, 15),
        Paint()
          ..color = AiraColors.forest.withValues(alpha: .08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
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
        colors: [Color(0xFFFFC9A4), Color(0xFFFFAB87), Color(0xFFE78668)]);
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
    c.rotate(-.65);
    c.drawOval(const Rect.fromLTWH(-20, -37, 34, 65), p);
    c.restore();
    c.save();
    c.translate(188, 160);
    c.rotate(.48);
    c.drawOval(const Rect.fromLTWH(-18, -24, 35, 53), p);
    c.restore();
    final dark = Paint()..color = const Color(0xFF322925);
    c.drawOval(const Rect.fromLTWH(90, 99, 12, 19), dark);
    c.drawOval(const Rect.fromLTWH(150, 101, 12, 19), dark);
    c.drawCircle(const Offset(94, 104), 2,
        Paint()..color = Colors.white.withValues(alpha: .65));
    c.drawCircle(const Offset(154, 106), 2,
        Paint()..color = Colors.white.withValues(alpha: .65));
    final blush = Paint()
      ..color = const Color(0xFFF37963).withValues(alpha: .34)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    c.drawOval(const Rect.fromLTWH(74, 120, 26, 13), blush);
    c.drawOval(const Rect.fromLTWH(151, 122, 27, 13), blush);
    final mouth = Path()
      ..moveTo(114, 124)
      ..quadraticBezierTo(128, 130, 141, 125)
      ..cubicTo(143, 150 + (speaking ? phase * 6 : 0), 112, 155, 114, 124);
    c.drawPath(mouth, Paint()..color = const Color(0xFF73352B));
    c.drawOval(const Rect.fromLTWH(119, 138, 18, 8),
        Paint()..color = const Color(0xFFEE8D78));
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
      old.speaking != speaking || (speaking && old.phase != phase);
}
