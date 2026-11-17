import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../sim/wave_buffer.dart';
import 'theme.dart';

/// Logical pixels per millimetre, so "25 mm/s" means what it says on a
/// typical screen.
const double kPxPerMm = 6.3;

/// A dotted reference line with its value printed at the left edge.
class ScaleMark {
  const ScaleMark(this.value, this.label);
  final double value;
  final String label;
}

/// One trace, drawn the way a monitor draws it: the pen sweeps left to right
/// and overwrites the previous pass behind a short blank gap. Nothing scrolls.
class WaveChannel extends StatelessWidget {
  const WaveChannel({
    super.key,
    required this.source,
    required this.repaint,
    required this.color,
    required this.mmPerSec,
    required this.lo,
    required this.hi,
    this.label,
    this.sublabel,
    this.marks = const [],
    this.calBar,
    this.fill = false,
    this.message,
    this.onTap,
    this.compact = false,
  });

  final WaveSource source;
  final Listenable repaint;
  final Color color;
  final double mmPerSec;

  /// Signal values at the bottom and top of the row.
  final double lo, hi;
  final String? label;
  final String? sublabel;
  final List<ScaleMark> marks;

  /// Height of a calibration bar in signal units (1 mV for ECG).
  final double? calBar;
  final bool fill;

  /// Replaces the trace with a status message (leads off and the like).
  final String? message;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    final labelSize = (compact ? 11 : 14) * s.clamp(0.8, 1.6);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: _SweepPainter(
                  source: source,
                  repaint: repaint,
                  color: color,
                  pxPerSec: mmPerSec * kPxPerMm,
                  lo: lo,
                  hi: hi,
                  marks: marks,
                  calBar: calBar,
                  fill: fill,
                  stroke: (compact ? 1.25 : 1.7) * s.clamp(0.75, 1.5),
                  gap: 16 * s.clamp(0.75, 1.5),
                  markStyle: labelStyle(10 * s.clamp(0.85, 1.4), color.withValues(alpha: 0.75)),
                ),
              ),
            ),
            if (label != null)
              Positioned(
                left: (calBar != null ? 16 : (marks.isNotEmpty ? 34 : 6)) * s,
                top: 3 * s,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(label!, style: labelStyle(labelSize, color, weight: 600)),
                    if (sublabel != null) ...[
                      SizedBox(width: 8 * s),
                      Text(sublabel!, style: labelStyle(labelSize * 0.74, color.withValues(alpha: 0.8))),
                    ],
                  ],
                ),
              ),
            if (message != null)
              Center(child: Text(message!, style: labelStyle(15 * s.clamp(0.8, 1.6), color, weight: 600))),
          ],
        ),
      ),
    );
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter({
    required this.source,
    required Listenable repaint,
    required this.color,
    required this.pxPerSec,
    required this.lo,
    required this.hi,
    required this.marks,
    required this.calBar,
    required this.fill,
    required this.stroke,
    required this.gap,
    required this.markStyle,
  }) : super(repaint: repaint);

  final WaveSource source;
  final Color color;
  final double pxPerSec;
  final double lo, hi;
  final List<ScaleMark> marks;
  final double? calBar;
  final bool fill;
  final double stroke;
  final double gap;
  final TextStyle markStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final pad = stroke + 1;
    double yOf(double v) => (h - pad - (v - lo) / (hi - lo) * (h - 2 * pad)).clamp(pad, h - pad);

    // Scale lines sit behind the trace.
    if (marks.isNotEmpty) {
      final dash = Paint()
        ..color = color.withValues(alpha: 0.35)
        ..strokeWidth = 1;
      var lastBottom = double.negativeInfinity;
      for (final m in marks) {
        final y = yOf(m.value);
        final tp = TextPainter(
          text: TextSpan(text: m.label, style: markStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final ty = (y - tp.height / 2).clamp(0.0, h - tp.height);
        // In a short row the labels would pile up; keep the ones that fit.
        final fits = ty >= lastBottom - 1 || (m == marks.last && h > tp.height * 2);
        if (fits && !(m != marks.last && m != marks.first && h < tp.height * 3.4)) {
          tp.paint(canvas, Offset(3, ty));
          lastBottom = ty + tp.height;
        }
        for (var x = tp.width + 8; x < w; x += 7) {
          canvas.drawLine(Offset(x, y), Offset(x + 2, y), dash);
        }
      }
    }

    final pen = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    if (calBar != null) {
      final y0 = yOf(0), y1 = yOf(calBar!);
      final cal = Path()
        ..moveTo(2, y0)
        ..lineTo(5, y0)
        ..lineTo(5, y1)
        ..lineTo(9, y1)
        ..lineTo(9, y0)
        ..lineTo(12, y0);
      canvas.drawPath(cal, pen..strokeWidth = math.max(1, stroke * 0.8));
      pen.strokeWidth = stroke;
    }

    final n = source.length;
    if (n < 2) return;
    final fs = source.fs;
    final tLast = source.tLast;
    final count = math.min(n, ((w - gap) / pxPerSec * fs).floor());
    if (count < 2) return;

    final line = Path();
    final area = fill ? Path() : null;
    final base = h - pad;
    var prevX = double.infinity;
    var segStart = 0.0;
    for (var i = count - 1; i >= 0; i--) {
      final x = ((tLast - i / fs) * pxPerSec) % w;
      final y = yOf(source.back(i));
      if (x < prevX) {
        if (area != null && prevX.isFinite) {
          area
            ..lineTo(prevX, base)
            ..lineTo(segStart, base)
            ..close();
        }
        line.moveTo(x, y);
        area?.moveTo(x, y);
        segStart = x;
      } else {
        line.lineTo(x, y);
        area?.lineTo(x, y);
      }
      prevX = x;
    }
    if (area != null) {
      area
        ..lineTo(prevX, base)
        ..lineTo(segStart, base)
        ..close();
      canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.22));
    }
    canvas.drawPath(line, pen);
  }

  @override
  bool shouldRepaint(_SweepPainter old) =>
      old.source != source ||
      old.color != color ||
      old.pxPerSec != pxPerSec ||
      old.lo != lo ||
      old.hi != hi ||
      old.stroke != stroke ||
      old.fill != fill ||
      old.marks != marks;
}
