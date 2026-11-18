import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/settings.dart';
import '../sim/alarms.dart';
import '../sim/ecg_shapes.dart';
import '../sim/patient_sim.dart';
import '../sim/wave_buffer.dart';
import 'theme.dart';

const _cell = BoxDecoration(
  border: Border(
    left: BorderSide(color: MC.barLine),
    bottom: BorderSide(color: MC.barLine),
  ),
);

String _two(int n) => n.toString().padLeft(2, '0');

// ----------------------------------------------------------------- lamp ----

/// The alarm light: a band across the top edge that shows the most urgent
/// active alarm from across the room.
class AlarmLamp extends StatelessWidget {
  const AlarmLamp({super.key, required this.sim, required this.blink, required this.height});
  final PatientSim sim;
  final bool blink;
  final double height;

  @override
  Widget build(BuildContext context) {
    Alarm? top;
    if (!sim.alarmsPaused && sim.alarms.isNotEmpty) top = sim.alarms.first;
    final lit = top != null && (top.acked || blink);
    return Container(
      height: height,
      color: top == null ? const Color(0xFF1E2831) : (lit ? MC.alarm(top.priority) : const Color(0xFF10161C)),
    );
  }
}

// ------------------------------------------------------------ info line ----

/// Second status line: who the patient is and how the monitor is configured.
class InfoLine extends StatelessWidget {
  const InfoLine({super.key, required this.sim, required this.settings, required this.height, this.patientInfo});
  final PatientSim sim;
  final MonitorSettings settings;
  final double height;

  /// Age, sex and weight when showing a bed other than the main patient.
  final String? patientInfo;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    final size = height * 0.56;
    Widget chip(String text, {Color color = MC.dim, IconData? icon, bool strong = false}) => Padding(
      padding: EdgeInsets.only(right: 12 * s),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: size * 1.15, color: color), SizedBox(width: 3 * s)],
          Text(text, maxLines: 1, style: labelStyle(size, color, weight: strong ? 650 : 500)),
        ],
      ),
    );
    final st = settings;
    final rec = sim.recording > 0;
    final g = st.ecgGain;
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: 6 * s),
      decoration: const BoxDecoration(
        color: Color(0xFF0E151C),
        border: Border(bottom: BorderSide(color: MC.barLine)),
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          maxWidth: double.infinity,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              chip(patientInfo ?? st.patientInfo, color: MC.text),
              chip('Profile: ICU ${st.category}'),
              chip(sim.pacing ? 'Paced' : 'Non-paced', color: sim.pacing ? MC.ecg : MC.dim),
              chip('Arrhythmia: On'),
              chip('ST: On'),
              chip('QT: On'),
              chip('Filter: Monitor'),
              chip('${st.sweep == 12.5 ? '12.5' : st.sweep.round()} mm/s'),
              chip('${(10 * g).round()} mm/mV'),
              chip('NIBP: ${sim.nibpAuto == 0 ? 'Manual' : 'Auto ${sim.nibpAuto} min'}'),
              chip(
                rec ? 'Recording ${sim.recording.ceil()} s' : 'Recorder ready',
                icon: Icons.print_outlined,
                color: rec ? MC.alarmYellow : MC.dim,
                strong: rec,
              ),
              chip('Central: ICU-East', icon: Icons.lan_outlined),
              chip('AC power', icon: Icons.power_outlined),
              chip(kLayoutNames[st.layout]!, icon: Icons.dashboard_outlined),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------- mini trends ----

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.series, this.colors, this.textStyle, {this.grid = false});
  final List<List<double?>> series;
  final List<Color> colors;
  final TextStyle textStyle;
  final bool grid;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = double.infinity, hi = -double.infinity;
    for (final s in series) {
      for (final v in s) {
        if (v == null) continue;
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    if (!lo.isFinite) return;
    final pad = math.max((hi - lo) * 0.18, hi.abs() < 12 ? 0.6 : 3.0);
    lo -= pad;
    hi += pad;
    if (hi - lo < 1e-6) hi = lo + 1;

    final loText = TextPainter(
      text: TextSpan(text: lo.abs() < 10 && hi - lo < 6 ? lo.toStringAsFixed(1) : '${lo.round()}', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final hiText = TextPainter(
      text: TextSpan(text: lo.abs() < 10 && hi - lo < 6 ? hi.toStringAsFixed(1) : '${hi.round()}', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final left = math.max(loText.width, hiText.width) + 4;
    final w = size.width - left - 2, h = size.height - 4;
    if (w < 8 || h < 6) return;
    if (h > loText.height * 2.2) {
      hiText.paint(canvas, Offset(left - 3 - hiText.width, 1));
      loText.paint(canvas, Offset(left - 3 - loText.width, size.height - loText.height - 1));
    }

    final frame = Paint()
      ..color = const Color(0xFF2B3947)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(left, 2), Offset(left, 2 + h), frame);
    canvas.drawLine(Offset(left, 2 + h), Offset(left + w, 2 + h), frame);
    if (grid) {
      for (var i = 1; i <= 3; i++) {
        final y = 2 + h * i / 4;
        for (var x = left; x < left + w; x += 6) {
          canvas.drawLine(Offset(x, y - h / 4), Offset(x + 1.5, y - h / 4), frame);
        }
      }
      for (var i = 1; i < 6; i++) {
        final x = left + w * i / 6;
        canvas.drawLine(Offset(x, 2), Offset(x, 2 + h), frame..color = const Color(0xFF1B2630));
      }
    }

    for (var k = 0; k < series.length; k++) {
      final s = series[k];
      if (s.length < 2) continue;
      final pen = Paint()
        ..color = colors[k % colors.length]
        ..strokeWidth = grid ? 1.6 : 1.2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      var down = false;
      for (var i = 0; i < s.length; i++) {
        final v = s[i];
        if (v == null) {
          down = false;
          continue;
        }
        final x = left + w * i / (s.length - 1);
        final y = 2 + h * (1 - ((v - lo) / (hi - lo)).clamp(0.0, 1.0));
        if (down) {
          path.lineTo(x, y);
        } else {
          path.moveTo(x, y);
          down = true;
        }
      }
      canvas.drawPath(path, pen);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) => true;
}

List<double?> _tail(List<double?>? l, int n) => l == null ? const [] : (l.length <= n ? l : l.sublist(l.length - n));

/// A half-hour sparkline of one or more stored trends.
class MiniTrend extends StatelessWidget {
  const MiniTrend({super.key, required this.sim, required this.keys, required this.color, this.points = 180});
  final PatientSim sim;
  final List<String> keys;
  final Color color;
  final int points;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    return DecoratedBox(
      decoration: _cell,
      child: Padding(
        padding: EdgeInsets.all(2 * s),
        child: CustomPaint(
          size: Size.infinite,
          painter: _SparkPainter(
            [for (final k in keys) _tail(sim.history[k], points)],
            [color, color.withValues(alpha: 0.6)],
            labelStyle((9 * s).clamp(7.0, 13.0), color.withValues(alpha: 0.7)),
          ),
        ),
      ),
    );
  }
}

/// A full-width trend graph over the last hour, for the trends screen.
class TrendGraph extends StatelessWidget {
  const TrendGraph({super.key, required this.sim, required this.label, required this.keys, required this.colors});
  final PatientSim sim;
  final String label;
  final List<String> keys;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: MC.barLine)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(4 * s, 4 * s, 6 * s, 14 * s),
            child: CustomPaint(
              painter: _SparkPainter(
                [for (final k in keys) _tail(sim.history[k], PatientSim.historyLength)],
                colors,
                labelStyle((10 * s).clamp(8.0, 14.0), colors.first.withValues(alpha: 0.8)),
                grid: true,
              ),
            ),
          ),
          Positioned(
            left: 44 * s,
            top: 3 * s,
            child: Text(label, style: labelStyle((13 * s).clamp(9.0, 18.0), colors.first, weight: 650)),
          ),
          Positioned(
            left: 40 * s,
            right: 6 * s,
            bottom: 1 * s,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final t in const ['-60 min', '-40', '-20', 'now'])
                  Text(t, style: labelStyle((9.5 * s).clamp(7.0, 13.0), MC.dim)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------- small gauges ------

class _BarPainter extends CustomPainter {
  _BarPainter(this.src, this.color, Listenable repaint) : super(repaint: repaint);
  final WaveSource src;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final v = src.length == 0 ? 0.0 : src.back(0).clamp(0.0, 1.0);
    final frame = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Offset.zero & size, frame);
    final h = (size.height - 2) * v;
    canvas.drawRect(Rect.fromLTWH(1.5, size.height - 1 - h, size.width - 3, h), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.src != src;
}

/// Column that rises and falls with the pleth: pulse strength at a glance.
class PulseBar extends StatelessWidget {
  const PulseBar({super.key, required this.source, required this.repaint, required this.color});
  final WaveSource source;
  final Listenable repaint;
  final Color color;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(size: Size.infinite, painter: _BarPainter(source, color, repaint)),
  );
}

/// Four ascending bars; [level] of them are lit.
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.level, required this.color, required this.size});
  final int level;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size * 1.3,
    height: size,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 1),
              height: size * (0.35 + 0.2167 * i),
              color: i < level ? color : color.withValues(alpha: 0.2),
            ),
          ),
      ],
    ),
  );
}

// ------------------------------------------------------- compound tiles ----

/// A tile that carries several related values side by side.
class MultiTile extends StatelessWidget {
  const MultiTile({super.key, required this.label, required this.color, required this.items, this.unit, this.onTap});
  final String label;
  final String? unit;
  final Color color;

  /// (name, value) pairs; the first is drawn largest.
  final List<(String, String)> items;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, box) {
          final h = box.maxHeight, w = box.maxWidth;
          final small = (12.5 * s).clamp(9.0, 22.0);
          final chars = items.fold<double>(0, (a, e) => a + math.max(e.$2.length, e.$1.length * 0.55) + 1.2);
          final num = math.max(10.0, math.min(h - small * 2.5, (w - 10 * s) / (chars * 0.56)));
          return Container(
            decoration: _cell,
            padding: EdgeInsets.fromLTRB(6 * s, 4 * s, 6 * s, 3 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(label, maxLines: 1, style: labelStyle(small * 1.15, color, weight: 650)),
                    if (unit != null) ...[
                      SizedBox(width: 5 * s),
                      Flexible(
                        child: Text(
                          unit!,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: labelStyle(small * 0.84, color.withValues(alpha: 0.8)),
                        ),
                      ),
                    ],
                  ],
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          flex: (math.max(items[i].$2.length, 3) * (i == 0 ? 13 : 10)),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.bottomRight,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(items[i].$1, style: labelStyle(small * 0.82, color.withValues(alpha: 0.8))),
                                Text(items[i].$2, style: numericStyle(i == 0 ? num : num * 0.78, color)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Train-of-four: four twitch bars, the count and the ratio.
class TofTile extends StatelessWidget {
  const TofTile({super.key, required this.sim});
  final PatientSim sim;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    final small = (12.5 * s).clamp(9.0, 22.0);
    return Container(
      decoration: _cell,
      padding: EdgeInsets.fromLTRB(6 * s, 4 * s, 6 * s, 4 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('TOF', style: labelStyle(small * 1.15, MC.nmt, weight: 650)),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text('${sim.tofCount}/4', style: labelStyle(small, MC.nmt, weight: 650)),
                ),
              ),
            ],
          ),
          SizedBox(height: 3 * s),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 5,
                  child: ValueListenableBuilder<int>(
                    valueListenable: sim.tofTick,
                    builder: (context, _, _) => Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final h in sim.tof)
                          Expanded(
                            child: FractionallySizedBox(
                              heightFactor: math.max(0.03, h),
                              child: Container(
                                margin: EdgeInsets.only(right: 2 * s),
                                color: MC.nmt,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 4 * s),
                Expanded(
                  flex: 6,
                  child: FittedBox(
                    alignment: Alignment.bottomRight,
                    fit: BoxFit.scaleDown,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('${sim.tofRatio}', style: numericStyle(small * 2.4, MC.nmt)),
                        Text('%', style: labelStyle(small, MC.nmt)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _st(double? v) => v == null ? '-?-' : '${v >= 0.05 ? '+' : ''}${(v.abs() < 0.05 ? 0.0 : v).toStringAsFixed(1)}';

/// ST deviation for all twelve leads, with QT and QTc.
class StPanel extends StatelessWidget {
  const StPanel({super.key, required this.sim});
  final PatientSim sim;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    final small = (11.5 * s).clamp(8.0, 20.0);
    Widget cell(Lead l) {
      final v = sim.stAll[l.index];
      final hot = v != null && v.abs() >= 1;
      return Expanded(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(kLeadNames[l]!, style: labelStyle(small * 0.9, MC.ecg.withValues(alpha: 0.75))),
              SizedBox(width: 3 * s),
              Text(
                _st(v),
                style: labelStyle(
                  small,
                  hot ? MC.alarmYellow : MC.ecg,
                  weight: 650,
                ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: _cell,
      padding: EdgeInsets.fromLTRB(6 * s, 3 * s, 4 * s, 2 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('ST', style: labelStyle(small * 1.2, MC.ecg, weight: 650)),
              SizedBox(width: 4 * s),
              Text('mm', style: labelStyle(small * 0.85, MC.ecg.withValues(alpha: 0.8))),
              SizedBox(width: 6 * s),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    'QT ${sim.qt ?? '-?-'}   QTc ${sim.qtc ?? '-?-'} ms',
                    style: labelStyle(small, MC.ecg, weight: 600),
                  ),
                ),
              ),
            ],
          ),
          Expanded(child: Row(children: [for (final l in Lead.values.take(6)) cell(l)])),
          Expanded(child: Row(children: [for (final l in Lead.values.skip(6)) cell(l)])),
        ],
      ),
    );
  }
}

/// The pumps running beside the bed.
class InfusionStrip extends StatelessWidget {
  const InfusionStrip({super.key, required this.sim, required this.blink});
  final PatientSim sim;
  final bool blink;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    const c = Color(0xFFBFD4E6);
    return LayoutBuilder(
      builder: (context, box) {
        final small = math.min((11.5 * s).clamp(8.0, 20.0), (box.maxHeight - 6 * s) / 3.7);
        return _strip(s, small, c);
      },
    );
  }

  Widget _strip(double s, double small, Color c) {
    return Container(
      decoration: _cell,
      child: Row(
        children: [
          for (final inf in sim.infusions)
            Expanded(
              child: Container(
                padding: EdgeInsets.fromLTRB(6 * s, 3 * s, 4 * s, 2 * s),
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Color(0xFF1E2A35))),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.water_drop,
                          size: small,
                          color: inf.remaining > 0 ? (blink ? MC.ecg : MC.ecg.withValues(alpha: 0.35)) : MC.alarmYellow,
                        ),
                        SizedBox(width: 3 * s),
                        Expanded(
                          child: Text(
                            inf.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: labelStyle(small, c, weight: 650),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      inf.dose,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: labelStyle(small * 0.92, MC.text),
                    ),
                    Text(
                      '${inf.rate.toStringAsFixed(1)} mL/h   ${inf.remaining.round()} mL left',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: labelStyle(small * 0.86, MC.dim),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Stopwatch plus the most recent entry in the event log. Tap to start or
/// stop the timer, hold to reset it.
class TimerTile extends StatelessWidget {
  const TimerTile({super.key, required this.sim});
  final PatientSim sim;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    final small = (11.5 * s).clamp(8.0, 20.0);
    final t = sim.timerSeconds.floor();
    final running = sim.timerStart != null;
    final last = sim.events.isEmpty ? null : sim.events.last;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: sim.toggleTimer,
      onLongPress: sim.resetTimer,
      child: Container(
        decoration: _cell,
        padding: EdgeInsets.fromLTRB(6 * s, 3 * s, 6 * s, 2 * s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(running ? Icons.timer : Icons.timer_outlined, size: small * 1.2, color: MC.text),
                SizedBox(width: 3 * s),
                Text('Timer', style: labelStyle(small, MC.text, weight: 650)),
                SizedBox(width: 4 * s),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${_two(t ~/ 3600)}:${_two(t % 3600 ~/ 60)}:${_two(t % 60)}',
                      style: numericStyle(small * 1.7, running ? MC.text : MC.dim),
                    ),
                  ),
                ),
              ],
            ),
            Text(
              last == null ? 'No events' : '${_two(last.time.hour)}:${_two(last.time.minute)}  ${last.text}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle(small * 0.9, last?.priority == null ? MC.dim : MC.alarm(last!.priority!)),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------- review screen -----

class _StBarPainter extends CustomPainter {
  _StBarPainter(this.values, this.style);
  final List<double?> values;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    final top = style.fontSize! * 1.4, bottom = style.fontSize! * 1.5;
    final h = size.height - top - bottom;
    final mid = top + h / 2;
    const range = 5.0;
    final line = Paint()
      ..color = const Color(0xFF34424F)
      ..strokeWidth = 1;
    for (final mm in const [-4, -2, 0, 2, 4]) {
      final y = mid - mm / range * h / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line..color = mm == 0 ? MC.dim : const Color(0xFF26323E));
    }
    final slot = size.width / n;
    for (var i = 0; i < n; i++) {
      final v = values[i];
      final x = slot * i + slot * 0.22;
      final name = TextPainter(
        text: TextSpan(
          text: kLeadNames[Lead.values[i]],
          style: style.copyWith(color: MC.dim),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      name.paint(canvas, Offset(slot * i + (slot - name.width) / 2, size.height - bottom + 2));
      if (v == null) continue;
      final hot = v.abs() >= 1;
      final y = mid - v.clamp(-range, range) / range * h / 2;
      canvas.drawRect(
        Rect.fromLTRB(x, math.min(mid, y), x + slot * 0.56, math.max(mid, y) + 1),
        Paint()..color = hot ? MC.alarmYellow : MC.ecg,
      );
      final val = TextPainter(
        text: TextSpan(
          text: _st(v),
          style: style.copyWith(color: hot ? MC.alarmYellow : MC.ecg),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      val.paint(canvas, Offset(slot * i + (slot - val.width) / 2, v >= 0 ? y - val.height - 1 : y + 3));
    }
  }

  @override
  bool shouldRepaint(_StBarPainter old) => true;
}

/// ST deviation as a bar per lead, in millimetres.
class StBars extends StatelessWidget {
  const StBars({super.key, required this.sim});
  final PatientSim sim;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    final size = (11.5 * s).clamp(8.0, 18.0);
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: MC.barLine),
          right: BorderSide(color: MC.barLine),
        ),
      ),
      padding: EdgeInsets.fromLTRB(8 * s, 4 * s, 8 * s, 2 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('ST map', style: labelStyle(size * 1.2, MC.ecg, weight: 650)),
              SizedBox(width: 6 * s),
              Text('mm', style: labelStyle(size * 0.9, MC.ecg.withValues(alpha: 0.8))),
              SizedBox(width: 6 * s),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    'QT ${sim.qt ?? '-?-'}   QTc ${sim.qtc ?? '-?-'} ms',
                    style: labelStyle(size, MC.ecg, weight: 600),
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: _StBarPainter(sim.stAll, labelStyle(size * 0.95, MC.ecg, weight: 600)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The alarm and event history, newest first.
class EventLog extends StatelessWidget {
  const EventLog({super.key, required this.sim});
  final PatientSim sim;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    final size = (12 * s).clamp(8.5, 18.0);
    final list = sim.events.reversed.toList();
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: MC.barLine)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xFF16202A),
            padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 3 * s),
            child: Text('Alarm and event review', style: labelStyle(size * 1.1, MC.text, weight: 650)),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text('No alarms or events yet', style: labelStyle(size, MC.dim)))
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final e = list[i];
                      final c = e.priority == null ? MC.text : MC.alarm(e.priority!);
                      return Container(
                        padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 2.5 * s),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Color(0xFF1B2630))),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '${_two(e.time.hour)}:${_two(e.time.minute)}:${_two(e.time.second)}',
                              style: labelStyle(
                                size,
                                MC.dim,
                              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                            ),
                            SizedBox(width: 10 * s),
                            Container(width: 4 * s, height: size, color: c),
                            SizedBox(width: 6 * s),
                            Expanded(
                              child: Text(
                                e.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: labelStyle(size, c, weight: 600),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------- recorder strip --

class _StripPainter extends CustomPainter {
  _StripPainter(this.src, this.seconds);
  final WaveSource src;
  final double seconds;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFF4EE));
    // 1 mm and 5 mm paper grid at 25 mm/s.
    final mm = size.width / (seconds * 25);
    final fine = Paint()
      ..color = const Color(0xFFF5C3BD)
      ..strokeWidth = 0.6;
    final bold = Paint()
      ..color = const Color(0xFFE8958C)
      ..strokeWidth = 1;
    for (var i = 0; i * mm <= size.width; i++) {
      canvas.drawLine(Offset(i * mm, 0), Offset(i * mm, size.height), i % 5 == 0 ? bold : fine);
    }
    for (var i = 0; i * mm <= size.height; i++) {
      canvas.drawLine(Offset(0, i * mm), Offset(size.width, i * mm), i % 5 == 0 ? bold : fine);
    }
    final n = math.min(src.length, (seconds * src.fs).round());
    if (n < 2) return;
    final base = size.height * 0.62;
    final path = Path();
    for (var i = n - 1; i >= 0; i--) {
      final x = size.width * (1 - i / (n - 1));
      final y = (base - src.back(i) * 10 * mm).clamp(1.0, size.height - 1);
      if (i == n - 1) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF111111)
        ..strokeWidth = 1.3
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_StripPainter old) => old.src != src;
}

/// What came out of the recorder: a paper strip of the lead that was
/// showing when the key was pressed.
class RecorderStrip extends StatelessWidget {
  const RecorderStrip({super.key, required this.source, required this.header, this.seconds = 6});
  final WaveSource source;
  final String header;
  final double seconds;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: const Color(0xFFFFF4EE),
          padding: EdgeInsets.fromLTRB(8 * s, 4 * s, 8 * s, 2 * s),
          child: Text(header, maxLines: 1, style: labelStyle(11.5 * s, const Color(0xFF222222), weight: 600)),
        ),
        AspectRatio(
          aspectRatio: seconds * 25 / 40,
          child: CustomPaint(painter: _StripPainter(source, seconds)),
        ),
      ],
    );
  }
}
