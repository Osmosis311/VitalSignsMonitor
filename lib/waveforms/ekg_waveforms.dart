import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../waveform_data/100_points.dart';

class EkgWaveform extends StatefulWidget {
  final double visibleSeconds; // how many seconds of waveform visible on screen
  final double scaleY;         // vertical scaling
  final Color color;

  const EkgWaveform({
    super.key,
    this.visibleSeconds = 8.0,
    this.scaleY = 100.0,
    this.color = Colors.green,
  });

  @override
  State<EkgWaveform> createState() => _EkgWaveformState();
}

class _EkgWaveformState extends State<EkgWaveform>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _offsetTime = 0.0; // seconds scrolled off the left
  late double _sampleDuration;
  late DateTime _lastFrameTime;

  @override
  void initState() {
    super.initState();
    _sampleDuration = ekgPoints.last.dx; // total seconds in dataset
    _lastFrameTime = DateTime.now();

    _ticker = createTicker((_) {
      final now = DateTime.now();
      final dt = now.difference(_lastFrameTime).inMicroseconds / 1e6; // frame delta in seconds
      _lastFrameTime = now;

      setState(() {
        _offsetTime += dt; // 1 second of data moves left per real second
        if (_offsetTime > _sampleDuration) {
          _offsetTime -= _sampleDuration; // seamless loop
        }
      });
    });

    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _EkgPainter(
        points: ekgPoints,
        offsetTime: _offsetTime,
        visibleSeconds: widget.visibleSeconds,
        scaleY: widget.scaleY,
        color: widget.color,
      ),
      size: Size.infinite,
    );
  }
}

class _EkgPainter extends CustomPainter {
  final List<Offset> points;
  final double offsetTime;
  final double visibleSeconds;
  final double scaleY;
  final Color color;

  _EkgPainter({
    required this.points,
    required this.offsetTime,
    required this.visibleSeconds,
    required this.scaleY,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final double width = size.width;
    final double baseline = size.height / 2;
    final double scaleX = width / visibleSeconds;
    final double segmentDuration = points.last.dx;

    void drawSegment(double timeOffset) {
      final path = Path();
      bool started = false;

      for (int i = 0; i < points.length; i++) {
        double time = points[i].dx - offsetTime + timeOffset;

        // Convert to screen X
        final double px = time * scaleX;
        if (px >= 0 && px <= width) {
          final double py = baseline - points[i].dy * scaleY;
          if (!started) {
            path.moveTo(px, py);
            started = true;
          } else {
            path.lineTo(px, py);
          }
        }
      }

      canvas.drawPath(path, paint);
    }

    // Draw the segment twice for seamless looping
    drawSegment(0.0);
    drawSegment(segmentDuration);
  }

  @override
  bool shouldRepaint(_EkgPainter oldDelegate) => true;
}

