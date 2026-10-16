import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// These are the character's actions, never a claim about the user's feelings.
enum CompanionActivity {
  idle,
  connecting,
  greeting,
  listening,
  thinking,
  speaking,
}

enum CompanionExpression { warm, playful, thoughtful, reassuring }

/// AIRA's original vector character. Voice movement follows actual playback;
/// the other gestures are a deliberately expressive character performance.
class Companion extends StatefulWidget {
  final double size, voiceLevel;
  final bool animated, speaking, reducedMotion;
  final CompanionActivity activity;
  final CompanionExpression expression;
  const Companion({
    super.key,
    this.size = 220,
    this.animated = true,
    this.speaking = false,
    this.reducedMotion = false,
    this.activity = CompanionActivity.idle,
    this.expression = CompanionExpression.warm,
    this.voiceLevel = 0,
  });
  @override
  State<Companion> createState() => _CompanionState();
}

class _CompanionState extends State<Companion> with TickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );
  late final AnimationController _hello = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
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
    if (_motionAllowed &&
        widget.activity == CompanionActivity.greeting &&
        oldWidget.activity != widget.activity) {
      _hello.forward(from: 0);
    }
  }

  void _syncMotion() {
    _motionAllowed =
        widget.animated &&
        !widget.reducedMotion &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (_motionAllowed && !_animation.isAnimating) {
      _animation.repeat();
    } else if (!_motionAllowed) {
      _animation.stop();
      _hello.stop();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _hello.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activity = widget.speaking
        ? CompanionActivity.speaking
        : widget.activity;
    return Semantics(
      label: 'AIRA, your coral-coloured AI companion, ${activity.name}',
      image: true,
      child: GestureDetector(
        onTap: _motionAllowed ? () => _hello.forward(from: 0) : null,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_animation, _hello]),
            builder: (context, _) => CustomPaint(
              painter: _CompanionPainter(
                seconds: _motionAllowed ? _animation.value * 18 : 0,
                hello: _motionAllowed && _hello.isAnimating ? _hello.value : -1,
                motion: _motionAllowed,
                activity: activity,
                expression: widget.expression,
                voiceLevel: widget.voiceLevel.clamp(0, 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanionPainter extends CustomPainter {
  final double seconds, hello, voiceLevel;
  final bool motion;
  final CompanionActivity activity;
  final CompanionExpression expression;
  const _CompanionPainter({
    required this.seconds,
    required this.hello,
    required this.motion,
    required this.activity,
    required this.expression,
    required this.voiceLevel,
  });

  double pulse(double start, double duration) {
    if (!motion || seconds < start || seconds > start + duration) return 0;
    return math.sin((seconds - start) / duration * math.pi);
  }

  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.scale(s.width / 260, s.height / 260);
    final t = motion ? seconds : 0.0;
    final speaking = activity == CompanionActivity.speaking;
    final listening = activity == CompanionActivity.listening;
    final thinking = activity == CompanionActivity.thinking;
    final connecting = activity == CompanionActivity.connecting;
    final playful = expression == CompanionExpression.playful;
    final reassuring = expression == CompanionExpression.reassuring;
    final thoughtful = expression == CompanionExpression.thoughtful;
    final breath = motion ? math.sin(t * math.pi / 2.8) : 0.0;
    final reaction = hello >= 0 ? math.sin(hello * math.pi) : 0.0;
    final idleHop = activity == CompanionActivity.idle || playful
        ? pulse(9.5, 1.2) * 13 + pulse(11.1, .8) * 7
        : 0.0;
    final hop = reaction * 17 + idleHop;
    final stretch = pulse(14.6, 1.7);
    final wave = hello >= 0
        ? math.sin(hello * math.pi * 7) * reaction
        : activity == CompanionActivity.greeting
        ? math.sin(t * 7) * .7
        : pulse(3, 2.3) * math.sin(t * 7);
    final nod = listening ? pulse(4.4, 1) * 3 + pulse(5.7, .8) * 2 : 0.0;
    final lean = listening
        ? .045
        : thinking
        ? -.05
        : 0.0;
    final sway = motion ? math.sin(t * 1.3) * (playful ? .045 : .018) : 0.0;

    c.drawOval(
      Rect.fromCenter(
        center: const Offset(131, 235),
        width: 145 - hop * 1.4,
        height: 13 - hop * .18,
      ),
      Paint()
        ..color = AiraColors.forest.withValues(alpha: .10 - hop * .0015)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    c.save();
    c.translate(130 + hop * math.sin(t * 7) * .2, 222 - hop + breath * 2 + nod);
    c.rotate(lean + sway + reaction * math.sin(hello * 10) * .04);
    c.scale(1 - stretch * .025, 1 + stretch * .045 + breath * .007);
    c.translate(-120, -213);

    final paint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-.55, -.6),
        radius: 1.4,
        colors: [Color(0xFFFFD1AD), Color(0xFFFFAE8A), Color(0xFFE78668)],
      ).createShader(const Rect.fromLTWH(35, 40, 175, 170));
    final body = Path()
      ..moveTo(54, 179)
      ..cubicTo(35, 142, 45, 87, 69, 65)
      ..cubicTo(90, 45, 157, 39, 181, 69)
      ..cubicTo(208, 105, 209, 167, 187, 192)
      ..cubicTo(173, 212, 71, 217, 54, 179)
      ..close();
    c.save();
    c.translate(89, 200);
    c.rotate(-hop * .015);
    c.drawOval(const Rect.fromLTWH(-21, -14, 44, 33), paint);
    c.restore();
    c.save();
    c.translate(165, 200);
    c.rotate(hop * .018);
    c.drawOval(const Rect.fromLTWH(-21, -14, 42, 32), paint);
    c.restore();
    c.drawPath(body, paint);
    for (final left in [true, false]) {
      c.save();
      c.translate(left ? 123 : 127, left ? 52 : 49);
      c.rotate((left ? -.45 : .45) + breath * .06 + hop * .004);
      c.drawOval(
        left
            ? const Rect.fromLTWH(-16, -30, 21, 40)
            : const Rect.fromLTWH(-2, -33, 23, 40),
        paint,
      );
      c.restore();
    }

    // Wave, cup an ear, gesture while talking, or hold a reassuring pose.
    c.save();
    c.translate(57, 139);
    final talkingGesture = speaking && motion ? math.sin(t * 4.1) * .22 : 0.0;
    c.rotate(
      listening
          ? -1.9 + breath * .04
          : reassuring
          ? .15
          : -.65 - wave * .72 - talkingGesture - reaction * .5,
    );
    c.drawOval(const Rect.fromLTWH(-20, -37, 34, 65), paint);
    c.restore();
    c.save();
    c.translate(
      thinking
          ? 161
          : reassuring
          ? 155
          : 188,
      thinking
          ? 151
          : reassuring
          ? 166
          : 160,
    );
    c.rotate(
      thinking
          ? -1.2 + breath * .025
          : reassuring
          ? -1.15
          : .48 + talkingGesture + stretch * .7,
    );
    c.drawOval(const Rect.fromLTWH(-18, -24, 35, 53), paint);
    c.restore();

    final dark = Paint()..color = const Color(0xFF322925);
    var blink = 0.0;
    for (final moment in [2.2, 6.8, 7.2, 12.5, 16.4]) {
      blink = math.max(
        blink,
        motion ? (1 - (t - moment).abs() / .11).clamp(0, 1).toDouble() : 0,
      );
    }
    final gazeX = thinking || thoughtful
        ? 3.5
        : connecting
        ? math.sin(t * .8) * 3
        : listening
        ? -1.5
        : math.sin(t * .45) * (motion ? 1.5 : 0);
    final gazeY = thinking || thoughtful
        ? -4.0
        : listening
        ? 1.0
        : 0.0;
    final eyeHeight = (reassuring ? 15.0 : 19.0) * (1 - blink * .94);
    for (final eye in [const Offset(96, 108.5), const Offset(156, 110.5)]) {
      final centre = eye + Offset(gazeX, gazeY);
      if (playful && hello > .45 && hello < .8 && eye.dx > 120) {
        c.drawArc(
          Rect.fromCenter(
            center: centre + const Offset(0, 3),
            width: 14,
            height: 9,
          ),
          math.pi,
          math.pi,
          false,
          Paint()
            ..color = dark.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      } else {
        c.drawOval(
          Rect.fromCenter(center: centre, width: 12, height: eyeHeight),
          dark,
        );
        if (blink < .5) {
          c.drawCircle(
            centre + const Offset(-2, -4),
            2,
            Paint()..color = Colors.white.withValues(alpha: .7),
          );
        }
      }
    }
    if (thinking || thoughtful || reassuring || connecting) {
      final eyebrow = Paint()
        ..color = const Color(0xFF985848)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.3
        ..strokeCap = StrokeCap.round;
      c.drawArc(
        Rect.fromLTWH(86, thinking ? 88 : 90, 17, 6),
        math.pi,
        math.pi,
        false,
        eyebrow,
      );
      c.drawArc(
        Rect.fromLTWH(147, thinking ? 86 : 92, 17, 6),
        math.pi,
        math.pi,
        false,
        eyebrow,
      );
    }
    final blush = Paint()
      ..color = const Color(0xFFF37963).withValues(alpha: playful ? .44 : .30)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    c.drawOval(const Rect.fromLTWH(74, 120, 26, 13), blush);
    c.drawOval(const Rect.fromLTWH(151, 122, 27, 13), blush);

    if (!speaking && (thinking || (listening && !playful) || reassuring)) {
      final smile = Path()
        ..moveTo(116, 131)
        ..quadraticBezierTo(127, reassuring ? 140 : 136, 139, 131);
      c.drawPath(
        smile,
        Paint()
          ..color = const Color(0xFF73352B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    } else {
      final speechOpen = speaking && motion
          ? (voiceLevel > .015
                ? voiceLevel * 14
                : 2 + math.sin(t * 15).abs() * 4)
          : 0.0;
      final mouth = Path()
        ..moveTo(114, 124)
        ..quadraticBezierTo(128, 130, 141, 125)
        ..cubicTo(143, 148 + speechOpen, 112, 153 + speechOpen, 114, 124);
      c.drawPath(mouth, Paint()..color = const Color(0xFF73352B));
      c.drawOval(
        Rect.fromLTWH(119, 138 + speechOpen * .55, 18, 8),
        Paint()..color = const Color(0xFFEE8D78),
      );
    }
    c.restore();

    if (thinking || connecting) {
      for (var i = 0; i < 3; i++) {
        final lift = motion
            ? math.sin(t * 3 - i * .7).clamp(0.0, 1.0) * 5
            : 0.0;
        c.drawCircle(
          Offset(205 + i * 11, 64 - lift),
          2.7,
          Paint()..color = AiraColors.forest.withValues(alpha: .35 + i * .13),
        );
      }
    } else {
      final sparkle = Paint()
        ..color = const Color(0xFFE7BD5B).withValues(alpha: .7)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      final expand = reaction * 7 + (playful ? pulse(9.5, 1.2) * 6 : 0);
      c.drawLine(Offset(34 - expand, 82), Offset(29 - expand, 75), sparkle);
      c.drawLine(Offset(27 - expand, 98), Offset(18 - expand, 96), sparkle);
      if (reaction > .2 || playful) {
        c.drawLine(Offset(224 + expand, 98), Offset(231 + expand, 93), sparkle);
        c.drawLine(
          Offset(228 + expand, 114),
          Offset(236 + expand, 115),
          sparkle,
        );
      }
    }
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _CompanionPainter old) =>
      old.seconds != seconds ||
      old.hello != hello ||
      old.motion != motion ||
      old.activity != activity ||
      old.expression != expression ||
      old.voiceLevel != voiceLevel;
}
