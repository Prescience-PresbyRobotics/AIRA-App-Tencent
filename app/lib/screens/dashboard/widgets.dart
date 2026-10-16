import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Shared presentation widgets for clearly labelled dashboard sample data.
class DashCard extends StatelessWidget {
  const DashCard({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AiraColors.line),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.35,
                    ),
                  ),
                  if (action != null) action!,
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AiraColors.muted,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              child,
            ],
          ),
        ),
      );
}

class DashboardMetric extends StatelessWidget {
  const DashboardMetric({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    this.color,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AiraColors.forest;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AiraColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AiraColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 19, color: accent),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            detail,
            style: const TextStyle(
              fontSize: 12,
              color: AiraColors.muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardTag extends StatelessWidget {
  const DashboardTag({super.key, required this.label, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AiraColors.forest;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: accent,
        ),
      ),
    );
  }
}

/// Uses available card width rather than device width, so nested views adapt too.
class DashboardColumns extends StatelessWidget {
  const DashboardColumns({
    super.key,
    required this.children,
    this.breakpoint = 850,
  });
  final List<Widget> children;
  final double breakpoint;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= breakpoint ? 2 : 1;
          final width = columns == 2
              ? (constraints.maxWidth - 16) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final child in children)
                SizedBox(width: width, child: child),
            ],
          );
        },
      );
}

class DashboardTrend extends StatelessWidget {
  const DashboardTrend({
    super.key,
    required this.values,
    required this.labels,
    this.color,
    this.unit = '',
    this.maxY,
  });
  final List<double> values;
  final List<String> labels;
  final Color? color;
  final String unit;
  final double? maxY;

  @override
  Widget build(BuildContext context) => _DashboardChart(
        values: values,
        labels: labels,
        color: color ?? AiraColors.forest,
        unit: unit,
        maxY: maxY,
        bars: false,
      );
}

class DashboardBars extends StatelessWidget {
  const DashboardBars({
    super.key,
    required this.values,
    required this.labels,
    this.color,
    this.unit = '',
    this.maxY,
  });
  final List<double> values;
  final List<String> labels;
  final Color? color;
  final String unit;
  final double? maxY;

  @override
  Widget build(BuildContext context) => _DashboardChart(
        values: values,
        labels: labels,
        color: color ?? AiraColors.forest,
        unit: unit,
        maxY: maxY,
        bars: true,
      );
}

class _DashboardChart extends StatelessWidget {
  const _DashboardChart({
    required this.values,
    required this.labels,
    required this.color,
    required this.unit,
    required this.maxY,
    required this.bars,
  });
  final List<double> values;
  final List<String> labels;
  final Color color;
  final String unit;
  final double? maxY;
  final bool bars;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const SizedBox(
        height: 140,
        child: Center(
          child: Text(
            'No sample points yet',
            style: TextStyle(fontSize: 13, color: AiraColors.muted),
          ),
        ),
      );
    }
    final safe =
        values.map((v) => v.isFinite ? math.max(0.0, v) : 0.0).toList();
    final upper = math.max(
      1.0,
      math.max(maxY ?? 0, safe.reduce(math.max)).ceilToDouble(),
    );
    final scale = MediaQuery.textScalerOf(context).scale(11) / 11;
    final axisWidth = 33.0 * math.max(1.0, scale);
    final chartHeight = math.max(158.0, 80.0 * scale);
    final names = [
      for (var i = 0; i < values.length; i++)
        i < labels.length ? labels[i] : '${i + 1}',
    ];
    final description = [
      for (var i = 0; i < safe.length; i++)
        '${names[i]}: ${_number(safe[i])}${unit.isEmpty ? '' : ' $unit'}',
    ].join('; ');
    return Semantics(
      label:
          '${bars ? 'Bar' : 'Trend'} chart. $description. Vertical axis 0 to ${_number(upper)} ${unit.isEmpty ? 'units' : unit}.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (unit.isNotEmpty) ...[
              Text(
                unit,
                style: const TextStyle(fontSize: 11, color: AiraColors.muted),
              ),
              const SizedBox(height: 6),
            ],
            SizedBox(
              height: chartHeight,
              child: Row(
                children: [
                  SizedBox(
                    width: axisWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final value in [upper, upper / 2, 0.0])
                            Text(
                              _number(value),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AiraColors.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: CustomPaint(
                      size: Size(double.infinity, chartHeight),
                      painter: _ChartPainter(
                        values: safe,
                        maxY: upper,
                        color: color,
                        bars: bars,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: EdgeInsets.only(left: axisWidth),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < names.length; i++)
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            _number(safe[i]),
                            style: TextStyle(
                              fontSize: 13,
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            names[i],
                            style: const TextStyle(
                              fontSize: 11,
                              color: AiraColors.muted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _number(double number) => number == number.roundToDouble()
      ? number.toInt().toString()
      : number.toStringAsFixed(1);
}

class _ChartPainter extends CustomPainter {
  const _ChartPainter({
    required this.values,
    required this.maxY,
    required this.color,
    required this.bars,
  });
  final List<double> values;
  final double maxY;
  final Color color;
  final bool bars;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || values.isEmpty) return;
    const top = 28.0;
    final bottom = size.height - 7;
    final height = bottom - top;
    final gridPaint = Paint()
      ..color = AiraColors.line.withValues(alpha: .75)
      ..strokeWidth = 1;
    for (var line = 0; line <= 2; line++) {
      final y = top + height * line / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final slot = size.width / values.length;
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(slot * (i + .5), bottom - (values[i] / maxY) * height),
    ];
    if (bars) {
      final width = math.min(34.0, slot * .58);
      for (var i = 0; i < points.length; i++) {
        final height = math.max(
          values[i] == 0 ? 0.0 : 3.0,
          bottom - points[i].dy,
        );
        final rect = Rect.fromLTWH(
          points[i].dx - width / 2,
          bottom - height,
          width,
          height,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(7)),
          Paint()
            ..color = color.withValues(alpha: i == points.length - 1 ? 1 : .65),
        );
      }
      return;
    }
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    final fill = Path.from(line)
      ..lineTo(points.last.dx, bottom)
      ..lineTo(points.first.dx, bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .16), color.withValues(alpha: .015)],
        ).createShader(Rect.fromLTWH(0, top, size.width, height)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final point in points) {
      canvas.drawCircle(point, 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(point, 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.maxY != maxY ||
      oldDelegate.color != color ||
      oldDelegate.bars != bars;
}
