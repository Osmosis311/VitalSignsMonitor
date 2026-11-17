import 'package:flutter/material.dart';

import '../app/settings.dart';
import '../sim/alarms.dart';
import '../sim/patient_sim.dart';
import 'theme.dart';

/// The information line across the top: bed and patient on the left, the
/// three alarm message fields in the middle, alarm state and clock on the
/// right.
class StatusBar extends StatelessWidget {
  const StatusBar({
    super.key,
    required this.sim,
    required this.settings,
    required this.blink,
    required this.now,
    required this.onSecret,
    required this.height,
  });

  final PatientSim sim;
  final MonitorSettings settings;
  final bool blink;
  final DateTime now;

  /// Long-press on the clock: opens the control panel.
  final VoidCallback onSecret;
  final double height;

  static String _two(int n) => n.toString().padLeft(2, '0');

  Widget _field(double s, AlarmPriority p) {
    final list = [
      for (final a in sim.alarms)
        if (a.priority == p) a,
    ];
    if (list.isEmpty || sim.alarmsPaused) {
      return Container(
        margin: EdgeInsets.symmetric(horizontal: 2 * s, vertical: 3 * s),
        decoration: BoxDecoration(color: MC.field, borderRadius: BorderRadius.circular(2 * s)),
      );
    }
    // Several alarms of one priority take turns in the field.
    final a = list[(sim.t ~/ 2) % list.length];
    final lit = a.acked || blink;
    final c = MC.alarm(p);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 2 * s, vertical: 3 * s),
      padding: EdgeInsets.symmetric(horizontal: 6 * s),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: lit ? c : c.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(2 * s)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (a.acked) ...[Icon(Icons.check, size: height * 0.5, color: MC.onAlarm(p)), SizedBox(width: 3 * s)],
            Text(
              list.length > 1 ? '${a.marked}   ${list.indexOf(a) + 1}/${list.length}' : a.marked,
              maxLines: 1,
              style: labelStyle(height * 0.46, lit ? MC.onAlarm(p) : c, weight: 700),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    final ts = labelStyle(height * 0.44, MC.text, weight: 600);
    final dim = labelStyle(height * 0.4, MC.dim);
    final name = settings.patientName.trim();
    final paused = sim.alarmsPaused;
    final rem = sim.pauseRemaining;

    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: MC.bar,
        border: Border(bottom: BorderSide(color: MC.barLine)),
      ),
      child: Row(
        children: [
          Container(
            margin: EdgeInsets.all(3 * s),
            padding: EdgeInsets.symmetric(horizontal: 8 * s),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: MC.windowTitle, borderRadius: BorderRadius.circular(2 * s)),
            child: Text(settings.bedLabel, style: ts),
          ),
          SizedBox(width: 4 * s),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 190 * s),
            child: Text(
              name.isEmpty ? settings.category : '$name   ${settings.category}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: name.isEmpty ? dim : ts,
            ),
          ),
          SizedBox(width: 8 * s),
          Expanded(flex: 5, child: _field(s, AlarmPriority.technical)),
          Expanded(flex: 5, child: _field(s, AlarmPriority.medium)),
          Expanded(flex: 5, child: _field(s, AlarmPriority.high)),
          SizedBox(width: 6 * s),
          if (paused) ...[
            Icon(Icons.notifications_paused, size: height * 0.62, color: MC.alarmRed),
            SizedBox(width: 3 * s),
            Text(
              'ALARMS PAUSED ${rem ~/ 60}:${_two(rem % 60)}',
              style: labelStyle(height * 0.42, MC.alarmRed, weight: 700),
            ),
          ] else if (settings.alarmVolume == 0)
            Icon(Icons.volume_off, size: height * 0.6, color: MC.alarmYellow)
          else
            Icon(Icons.notifications_active_outlined, size: height * 0.56, color: MC.dim),
          SizedBox(width: 8 * s),
          if (settings.showDemoTag) ...[
            Container(
              padding: EdgeInsets.symmetric(horizontal: 5 * s, vertical: 1.5 * s),
              decoration: BoxDecoration(
                border: Border.all(color: MC.dim),
                borderRadius: BorderRadius.circular(2 * s),
              ),
              child: Text('DEMO', style: labelStyle(height * 0.36, MC.dim, weight: 700)),
            ),
            SizedBox(width: 8 * s),
          ],
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: onSecret,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4 * s),
              child: Center(
                child: Text(
                  '${_two(now.day)} ${_months[now.month - 1]} ${now.year}   ${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}',
                  style: ts.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ),
          ),
          Icon(Icons.wifi, size: height * 0.5, color: MC.dim),
          SizedBox(width: 4 * s),
          Icon(Icons.battery_full, size: height * 0.62, color: MC.ecg),
          SizedBox(width: 5 * s),
        ],
      ),
    );
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
