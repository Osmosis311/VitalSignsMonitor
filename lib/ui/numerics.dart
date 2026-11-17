import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../sim/alarms.dart';
import 'theme.dart';

String _v(num? v) => v == null ? '-?-' : '$v';

/// Frame shared by every numeric: label and unit top-left, alarm limits under
/// the label, the measured value large on the right, small extras along the
/// bottom. An active alarm flashes the whole tile in its priority colour.
class ParamTile extends StatelessWidget {
  const ParamTile({
    super.key,
    required this.label,
    required this.color,
    required this.value,
    this.unit,
    this.limitHi,
    this.limitLo,
    this.alarm,
    this.blink = false,
    this.alarmsOff = false,
    this.footer = const [],
    this.side,
    this.corner,
    this.gauge,
    this.badge,
    this.onTap,
    this.valueScale = 1,
  });

  final String label;
  final String? unit;
  final Color color;

  /// The headline number, already formatted.
  final String value;
  final String? limitHi, limitLo;
  final Alarm? alarm;
  final bool blink;
  final bool alarmsOff;
  final List<String> footer;

  /// A secondary value shown smaller, right of the main one: `(mean)`.
  final String? side;
  final Widget? corner;

  /// A narrow vertical indicator between the limits and the value.
  final Widget? gauge;

  /// A small symbol after the unit, on the label line.
  final Widget? badge;
  final VoidCallback? onTap;
  final double valueScale;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    final a = alarm;
    final flashing = a != null && !a.acked && blink;
    final fg = flashing ? MC.onAlarm(a.priority) : color;
    final bg = flashing ? MC.alarm(a.priority) : MC.bg;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          final small = (12.5 * s).clamp(9.0, 22.0);
          final chars = value.length + (side == null ? 0 : side!.length * 0.62 + 0.4);
          final numSize = math.max(
            12.0,
            math.min(h * 0.78 - small * 1.1, (w - small * 3.4) / (chars * 0.56)) * valueScale,
          );
          return Container(
            decoration: BoxDecoration(
              color: bg,
              border: Border(
                left: const BorderSide(color: MC.barLine),
                bottom: const BorderSide(color: MC.barLine),
                top: a != null && !flashing ? BorderSide(color: MC.alarm(a.priority), width: 2) : BorderSide.none,
              ),
            ),
            padding: EdgeInsets.fromLTRB(6 * s, 4 * s, 7 * s, 3 * s),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(label, style: labelStyle(small * 1.22, fg, weight: 650)),
                          if (unit != null) ...[
                            SizedBox(width: 5 * s),
                            Text(unit!, style: labelStyle(small * 0.86, fg.withValues(alpha: 0.8))),
                          ],
                          if (badge != null) ...[SizedBox(width: 6 * s), badge!],
                        ],
                      ),
                      SizedBox(height: 2 * s),
                      if (alarmsOff)
                        Icon(Icons.notifications_off, size: small * 1.25, color: fg.withValues(alpha: 0.85))
                      else if (limitHi != null && h > small * 5.2) ...[
                        Text(limitHi!, style: labelStyle(small * 0.84, fg.withValues(alpha: 0.78))),
                        Text(limitLo ?? '', style: labelStyle(small * 0.84, fg.withValues(alpha: 0.78))),
                      ],
                    ],
                  ),
                ),
                if (corner != null) Positioned(right: 0, top: 0, child: corner!),
                if (gauge != null && h > small * 3.4)
                  Positioned(
                    left: small * 2.6,
                    top: small * 1.75,
                    bottom: footer.isEmpty || h < small * 4.6 ? 1 : small * 1.3,
                    width: small * 0.7,
                    child: gauge!,
                  ),
                Positioned(
                  right: 0,
                  bottom: footer.isEmpty || h < small * 4.6 ? 0 : small * 0.9,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(value, style: numericStyle(numSize, fg)),
                      if (side != null) ...[
                        SizedBox(width: numSize * 0.16),
                        Text(side!, style: numericStyle(numSize * 0.6, fg)),
                      ],
                    ],
                  ),
                ),
                if (footer.isNotEmpty && h >= small * 4.6)
                  Positioned(
                    left: 0,
                    bottom: 0,
                    child: Text(footer.join('    '), style: labelStyle(small * 0.92, fg.withValues(alpha: 0.9))),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Heart symbol that lights for a moment on every detected QRS.
class BeatHeart extends StatefulWidget {
  const BeatHeart({super.key, required this.tick, required this.size, required this.color});
  final ValueListenable<int> tick;
  final double size;
  final Color color;

  @override
  State<BeatHeart> createState() => _BeatHeartState();
}

class _BeatHeartState extends State<BeatHeart> {
  bool _on = false;
  Timer? _off;

  @override
  void initState() {
    super.initState();
    widget.tick.addListener(_beat);
  }

  @override
  void didUpdateWidget(BeatHeart old) {
    super.didUpdateWidget(old);
    if (old.tick != widget.tick) {
      old.tick.removeListener(_beat);
      widget.tick.addListener(_beat);
    }
  }

  void _beat() {
    _off?.cancel();
    setState(() => _on = true);
    _off = Timer(const Duration(milliseconds: 160), () {
      if (mounted) setState(() => _on = false);
    });
  }

  @override
  void dispose() {
    widget.tick.removeListener(_beat);
    _off?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.favorite, size: widget.size, color: _on ? widget.color : widget.color.withValues(alpha: 0.18));
}

String fmt(num? v) => _v(v);

/// `120/80`, or the placeholder when there is no reading.
String fmtBp(int? s, int? d) => s == null || d == null ? '-?-/-?-' : '$s/$d';
