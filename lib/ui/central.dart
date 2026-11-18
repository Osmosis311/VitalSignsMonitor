import 'package:flutter/material.dart';

import '../sim/alarms.dart';
import '../sim/patient_sim.dart';
import '../sim/wave_buffer.dart';
import 'numerics.dart';
import 'theme.dart';
import 'wave_channel.dart';

/// One patient on the unit. Bed 1 is the app's main patient and takes its
/// label and name from the settings; the others carry their own.
class Bed {
  Bed(this.sim, {this.label, this.name, this.info});
  final PatientSim sim;
  final String? label;
  final String? name;
  final String? info;
}

/// The rest of the ward: who is in each bed and what their monitor shows.
class WardPatient {
  const WardPatient(
    this.name,
    this.info,
    this.rhythm,
    this.rate,
    this.spo2,
    this.sys,
    this.dia,
    this.resp, {
    this.temp = 36.8,
  });
  final String name;
  final String info;
  final String rhythm;
  final int rate;
  final double spo2, sys, dia, resp, temp;
}

const List<WardPatient> kWard = [
  WardPatient('OKAFOR, N', '71 y   F   64 kg', 'afib', 92, 96, 134, 82, 18),
  WardPatient('LINDQVIST, E', '44 y   M   91 kg', 'sinus_tach', 112, 97, 104, 62, 22, temp: 38.3),
  WardPatient('MORALES, D', '83 y   M   70 kg', 'paced_v', 70, 98, 118, 70, 14),
  WardPatient('TANAKA, H', '29 y   F   58 kg', 'sinus_brady', 52, 99, 110, 66, 12),
  WardPatient('BAPTISTE, C', '66 y   M   88 kg', 'pvc_occ', 78, 94, 146, 88, 16),
  WardPatient('NOVAK, M', '59 y   F   73 kg', 'avb1', 64, 97, 128, 76, 15),
  WardPatient('HASSAN, L', '77 y   M   67 kg', 'nsr', 84, 92, 138, 84, 20),
];

/// Builds bed [index] (1-based among the extra beds) and runs it forward so
/// it arrives with traces, numbers and a first cuff reading already there.
Bed makeWardBed(int index, String label, DateTime Function() clock) {
  final p = kWard[(index - 1) % kWard.length];
  final sim = PatientSim(seed: 100 + index, clock: clock)
    ..abpOn = false
    ..papOn = false
    ..cvpOn = false
    ..icpOn = false;
  sim.setRhythm(p.rhythm, bpm: p.rate);
  sim.spo2.set(p.spo2);
  sim.setBp(p.sys, p.dia, over: 0);
  sim.respRate.set(p.resp);
  sim.temp.set(p.temp);
  for (var i = 0; i < 4 * (34 + 5 * index); i++) {
    sim.advance(0.25);
  }
  // Whatever is already alarming is old news to the staff: acknowledged.
  sim.silence();
  sim.events.clear();
  sim.seedHistory(fromNow: true);
  return Bed(sim, label: label, name: p.name, info: p.info);
}

String _two(int n) => n.toString().padLeft(2, '0');
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Top line of the central station: unit name, how many beds to show, how
/// many are alarming, and the clock.
class CentralBar extends StatelessWidget {
  const CentralBar({
    super.key,
    required this.height,
    required this.count,
    required this.onCount,
    required this.alarming,
    required this.now,
    required this.onSecret,
    required this.showDemo,
  });

  final double height;
  final int count;
  final ValueChanged<int> onCount;

  /// Beds with an active alarm.
  final int alarming;
  final DateTime now;
  final VoidCallback onSecret;
  final bool showDemo;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    final ts = labelStyle(height * 0.44, MC.text, weight: 600);
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
            child: Text('CENTRAL STATION', style: ts),
          ),
          SizedBox(width: 6 * s),
          Flexible(
            child: Text(
              'ICU-East',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle(height * 0.42, MC.dim),
            ),
          ),
          SizedBox(width: 14 * s),
          Text('Beds', style: labelStyle(height * 0.42, MC.dim)),
          for (final n in const [4, 6, 8])
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onCount(n),
              child: Container(
                width: height * 1.25,
                margin: EdgeInsets.only(left: 4 * s, top: 3 * s, bottom: 3 * s),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: n == count ? MC.keyOn : MC.key,
                  border: Border.all(color: const Color(0xFF6B7F92)),
                  borderRadius: BorderRadius.circular(3 * s),
                ),
                child: Text('$n', style: labelStyle(height * 0.46, n == count ? Colors.black : MC.text, weight: 700)),
              ),
            ),
          SizedBox(width: 8 * s),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (alarming > 0) ...[
                    Icon(Icons.notifications_active, size: height * 0.58, color: MC.alarmYellow),
                    SizedBox(width: 3 * s),
                    Text(
                      '$alarming ${alarming == 1 ? 'bed' : 'beds'} alarming',
                      style: labelStyle(height * 0.42, MC.alarmYellow, weight: 700),
                    ),
                  ] else
                    Text('No alarms', style: labelStyle(height * 0.42, MC.dim)),
                  SizedBox(width: 10 * s),
                  if (showDemo) ...[
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
                  Icon(Icons.lan_outlined, size: height * 0.5, color: MC.dim),
                  SizedBox(width: 6 * s),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One patient's sector on the central station: who they are, any alarm,
/// two traces and four numbers. Touch it to open that bed's full monitor.
class BedSector extends StatelessWidget {
  const BedSector({
    super.key,
    required this.label,
    required this.name,
    required this.sim,
    required this.ecg,
    required this.pleth,
    required this.repaint,
    required this.blink,
    required this.mmPerSec,
    required this.onTap,
  });

  final String label;
  final String name;
  final PatientSim sim;
  final WaveSource ecg;
  final WaveSource pleth;
  final Listenable repaint;
  final bool blink;
  final double mmPerSec;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    final paused = sim.alarmsPaused;
    final top = paused || sim.alarms.isEmpty ? null : sim.alarms.first;
    final lit = top != null && (top.acked || blink);
    final measuring = sim.nibpPhase != NibpPhase.idle;
    Alarm? forParam(Param p) => sim.alarmFor(p);
    bool flash(Alarm? a) => a != null && blink;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, box) {
          final headH = (box.maxHeight * 0.15).clamp(13.0, 26 * s < 13 ? 13.0 : 26 * s).toDouble();
          return Container(
            margin: EdgeInsets.all(1.5 * s),
            decoration: BoxDecoration(
              border: Border.all(
                color: top == null
                    ? MC.barLine
                    : (lit ? MC.alarm(top.priority) : MC.alarm(top.priority).withValues(alpha: 0.3)),
                width: top == null ? 1 : 2,
              ),
            ),
            child: Column(
              children: [
                Container(
                  height: headH,
                  color: const Color(0xFF121B24),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6 * s),
                        alignment: Alignment.center,
                        color: MC.windowTitle,
                        child: Text(label, style: labelStyle(headH * 0.56, MC.text, weight: 700)),
                      ),
                      SizedBox(width: 6 * s),
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: labelStyle(headH * 0.54, MC.text, weight: 600),
                        ),
                      ),
                      SizedBox(width: 6 * s),
                      if (top != null)
                        Expanded(
                          child: Container(
                            margin: EdgeInsets.symmetric(vertical: 1.5 * s, horizontal: 2 * s),
                            alignment: Alignment.center,
                            color: lit ? MC.alarm(top.priority) : MC.alarm(top.priority).withValues(alpha: 0.25),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                top.marked,
                                maxLines: 1,
                                style: labelStyle(
                                  headH * 0.54,
                                  lit ? MC.onAlarm(top.priority) : MC.alarm(top.priority),
                                  weight: 700,
                                ),
                              ),
                            ),
                          ),
                        )
                      else ...[
                        const Spacer(),
                        if (paused) Icon(Icons.notifications_paused, size: headH * 0.8, color: MC.alarmRed),
                        SizedBox(width: 4 * s),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 11,
                        child: Column(
                          children: [
                            Expanded(
                              flex: 3,
                              child: WaveChannel(
                                source: ecg,
                                repaint: repaint,
                                color: MC.ecg,
                                mmPerSec: mmPerSec,
                                lo: -0.95,
                                hi: 1.5,
                                label: 'II',
                                message: sim.leadsOff ? 'LEADS OFF' : null,
                                compact: true,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: WaveChannel(
                                source: pleth,
                                repaint: repaint,
                                color: MC.spo2,
                                mmPerSec: mmPerSec,
                                lo: -0.08,
                                hi: 1.08,
                                label: 'Pleth',
                                compact: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 9,
                        child: Column(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ParamTile(
                                      label: 'HR',
                                      color: MC.ecg,
                                      value: fmt(sim.hr),
                                      alarm: forParam(Param.hr),
                                      blink: flash(forParam(Param.hr)),
                                      corner: BeatHeart(
                                        tick: sim.beatTick,
                                        size: (13 * s).clamp(8.0, 22.0),
                                        color: MC.ecg,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: ParamTile(
                                      label: 'SpO₂',
                                      color: MC.spo2,
                                      value: fmt(sim.spo2Value),
                                      alarm: forParam(Param.spo2),
                                      blink: flash(forParam(Param.spo2)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 8,
                                    child: ParamTile(
                                      label: 'NIBP',
                                      color: MC.nibp,
                                      value: measuring ? '${sim.cuff.round()}' : fmtBp(sim.nibpS, sim.nibpD),
                                      side: measuring ? null : '(${fmt(sim.nibpM)})',
                                      alarm: forParam(Param.nibp),
                                      blink: flash(forParam(Param.nibp)),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 5,
                                    child: ParamTile(
                                      label: 'RR',
                                      color: MC.resp,
                                      value: fmt(sim.awrr),
                                      alarm: forParam(Param.co2),
                                      blink: flash(forParam(Param.co2)),
                                    ),
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
              ],
            ),
          );
        },
      ),
    );
  }
}
