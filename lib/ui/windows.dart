import 'package:flutter/material.dart';

import '../app/settings.dart';
import '../sim/alarms.dart';
import '../sim/ecg_shapes.dart';
import '../sim/patient_sim.dart';
import 'theme.dart';

/// A menu window in the monitor's own style: title bar, close box, content.
class MonitorWindow extends StatelessWidget {
  const MonitorWindow({super.key, required this.title, required this.onClose, required this.child, this.width = 400});
  final String title;
  final VoidCallback onClose;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    return Container(
      width: width * s,
      decoration: BoxDecoration(
        color: MC.window,
        border: Border.all(color: const Color(0xFF6B7F92)),
        borderRadius: BorderRadius.circular(4 * s),
        boxShadow: const [BoxShadow(color: Color(0xCC000000), blurRadius: 18, offset: Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: MC.windowTitle,
            padding: EdgeInsets.only(left: 10 * s),
            child: Row(
              children: [
                Expanded(child: Text(title, style: labelStyle(15 * s, MC.text, weight: 650))),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: Padding(
                    padding: EdgeInsets.all(7 * s),
                    child: Icon(Icons.close, size: 20 * s, color: MC.text),
                  ),
                ),
              ],
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// One line of a setup menu. Tap to step to the next choice, or use the
/// minus / plus boxes when they are given.
class SetupRow extends StatelessWidget {
  const SetupRow(this.label, this.value, {super.key, this.onTap, this.onMinus, this.onPlus, this.selected = false});
  final String label;
  final String value;
  final VoidCallback? onTap;
  final VoidCallback? onMinus, onPlus;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    Widget box(IconData i, VoidCallback? f) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: f,
      child: Container(
        width: 34 * s,
        height: 30 * s,
        margin: EdgeInsets.only(left: 5 * s),
        decoration: BoxDecoration(
          color: MC.key,
          border: Border.all(color: const Color(0xFF6B7F92)),
          borderRadius: BorderRadius.circular(3 * s),
        ),
        child: Icon(i, size: 20 * s, color: MC.text),
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: 38 * s),
        padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 3 * s),
        decoration: BoxDecoration(
          color: selected ? MC.select : null,
          border: const Border(bottom: BorderSide(color: Color(0xFF2B3947))),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: labelStyle(14 * s, MC.text))),
            SizedBox(width: 8 * s),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle(14 * s, selected ? MC.text : MC.spo2, weight: 650),
              ),
            ),
            if (onMinus != null) box(Icons.remove, onMinus),
            if (onPlus != null) box(Icons.add, onPlus),
          ],
        ),
      ),
    );
  }
}

T _cycle<T>(List<T> all, T cur) => all[(all.indexOf(cur) + 1) % all.length];

Future<String?> _askText(BuildContext context, String title, String initial) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: MC.window,
      title: Text(title, style: const TextStyle(color: MC.text, fontSize: 16)),
      content: TextField(
        controller: c,
        autofocus: true,
        style: const TextStyle(color: MC.text),
        textCapitalization: TextCapitalization.characters,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK')),
      ],
    ),
  );
}

class MainSetupWindow extends StatelessWidget {
  const MainSetupWindow({super.key, required this.settings, required this.onClose});
  final MonitorSettings settings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final st = settings;
    String onOff(bool v) => v ? 'On' : 'Off';
    return MonitorWindow(
      title: 'Main Setup',
      onClose: onClose,
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          if (st.layout == ScreenLayout.full) const SetupRow('The ICU full screen shows every wave', ''),
          SetupRow(
            'Patient name',
            st.patientName.isEmpty ? '(none)' : st.patientName,
            onTap: () async {
              final v = await _askText(context, 'Patient name', st.patientName);
              if (v != null) st.update(() => st.patientName = v.trim());
            },
          ),
          SetupRow(
            'Bed label',
            st.bedLabel,
            onTap: () async {
              final v = await _askText(context, 'Bed label', st.bedLabel);
              if (v != null && v.trim().isNotEmpty) st.update(() => st.bedLabel = v.trim());
            },
          ),
          SetupRow(
            'Age, sex, weight',
            st.patientInfo,
            onTap: () async {
              final v = await _askText(context, 'Age, sex, weight', st.patientInfo);
              if (v != null) st.update(() => st.patientInfo = v.trim());
            },
          ),
          SetupRow(
            'Patient category',
            st.category,
            onTap: () => st.update(() => st.category = _cycle(const ['Adult', 'Pedi', 'Neo'], st.category)),
          ),
          SetupRow(
            'ECG wave 1',
            kLeadNames[st.ecg1]!,
            onTap: () => st.update(() => st.ecg1 = _cycle(Lead.values, st.ecg1)),
          ),
          SetupRow(
            'ECG wave 2',
            st.showEcg2 ? kLeadNames[st.ecg2]! : 'Off',
            onTap: () => st.update(() {
              if (!st.showEcg2) {
                st.showEcg2 = true;
                st.ecg2 = Lead.i;
              } else if (st.ecg2 == Lead.v6) {
                st.showEcg2 = false;
              } else {
                st.ecg2 = _cycle(Lead.values, st.ecg2);
              }
            }),
          ),
          SetupRow(
            'ECG size',
            '×${st.ecgGain == 0.5 ? '½' : st.ecgGain.toStringAsFixed(0)}',
            onTap: () => st.update(() => st.ecgGain = _cycle(const [0.5, 1.0, 2.0], st.ecgGain)),
          ),
          SetupRow(
            'Sweep speed',
            '${st.sweep == 12.5 ? '12.5' : st.sweep.toStringAsFixed(0)} mm/s',
            onTap: () => st.update(() => st.sweep = _cycle(const [12.5, 25.0, 50.0], st.sweep)),
          ),
          SetupRow(
            'Arterial pressure (ABP)',
            onOff(st.showAbp),
            onTap: () => st.update(() => st.showAbp = !st.showAbp),
          ),
          SetupRow('Capnography (CO₂)', onOff(st.showCo2), onTap: () => st.update(() => st.showCo2 = !st.showCo2)),
          SetupRow('Respiration wave', onOff(st.showResp), onTap: () => st.update(() => st.showResp = !st.showResp)),
          SetupRow('Pulmonary artery (PAP)', onOff(st.showPap), onTap: () => st.update(() => st.showPap = !st.showPap)),
          SetupRow('Central venous (CVP)', onOff(st.showCvp), onTap: () => st.update(() => st.showCvp = !st.showCvp)),
          SetupRow('Intracranial (ICP)', onOff(st.showIcp), onTap: () => st.update(() => st.showIcp = !st.showIcp)),
          SetupRow('EEG and BIS', onOff(st.showEeg), onTap: () => st.update(() => st.showEeg = !st.showEeg)),
          SetupRow(
            'Mini-trends',
            onOff(st.showMiniTrends),
            onTap: () => st.update(() => st.showMiniTrends = !st.showMiniTrends),
          ),
          SetupRow(
            'Lower rows (C.O., TOF, ST, pumps)',
            onOff(st.showExtras),
            onTap: () => st.update(() => st.showExtras = !st.showExtras),
          ),
          SetupRow(
            'QRS volume',
            st.qrsVolume == 0 ? 'Off' : '${st.qrsVolume}',
            onMinus: () => st.update(() => st.qrsVolume = (st.qrsVolume - 1).clamp(0, 5)),
            onPlus: () => st.update(() => st.qrsVolume = (st.qrsVolume + 1).clamp(0, 5)),
          ),
          SetupRow(
            'Alarm volume',
            st.alarmVolume == 0 ? 'Off' : '${st.alarmVolume}',
            onMinus: () => st.update(() => st.alarmVolume = (st.alarmVolume - 1).clamp(0, 5)),
            onPlus: () => st.update(() => st.alarmVolume = (st.alarmVolume + 1).clamp(0, 5)),
          ),
          SetupRow(
            'Temperature unit',
            st.fahrenheit ? '°F' : '°C',
            onTap: () => st.update(() => st.fahrenheit = !st.fahrenheit),
          ),
        ],
      ),
    );
  }
}

class AlarmLimitsWindow extends StatelessWidget {
  const AlarmLimitsWindow({super.key, required this.sim, required this.onClose, required this.onChanged});
  final PatientSim sim;
  final VoidCallback onClose;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    Widget cell(Limit l, bool high) {
      void bump(double d) {
        if (high) {
          l.hi = (l.hi + d).clamp(l.lo + l.step, l.max).toDouble();
        } else {
          l.lo = (l.lo + d).clamp(l.min, l.hi - l.step).toDouble();
        }
        onChanged();
      }

      Widget b(IconData i, double d) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => bump(d),
        child: Container(
          width: 30 * s,
          height: 30 * s,
          decoration: BoxDecoration(
            color: MC.key,
            border: Border.all(color: const Color(0xFF6B7F92)),
            borderRadius: BorderRadius.circular(3 * s),
          ),
          child: Icon(i, size: 18 * s, color: MC.text),
        ),
      );
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          b(Icons.remove, -l.step),
          SizedBox(
            width: 50 * s,
            child: Text(
              l.fmt(high ? l.hi : l.lo),
              textAlign: TextAlign.center,
              style: labelStyle(15 * s, MC.spo2, weight: 650),
            ),
          ),
          b(Icons.add, l.step),
        ],
      );
    }

    final head = labelStyle(12 * s, MC.dim, weight: 600);
    return MonitorWindow(
      title: 'Alarm Limits',
      width: 440,
      onClose: onClose,
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(10 * s, 6 * s, 10 * s, 2 * s),
            child: Row(
              children: [
                Expanded(child: Text('Parameter', style: head)),
                SizedBox(
                  width: 116 * s,
                  child: Text('Low', textAlign: TextAlign.center, style: head),
                ),
                SizedBox(width: 10 * s),
                SizedBox(
                  width: 116 * s,
                  child: Text('High', textAlign: TextAlign.center, style: head),
                ),
              ],
            ),
          ),
          for (final l in sim.limits.values)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF2B3947))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(l.label, style: labelStyle(14 * s, MC.text)),
                        SizedBox(width: 5 * s),
                        Text(l.unit, style: labelStyle(11 * s, MC.dim)),
                      ],
                    ),
                  ),
                  cell(l, false),
                  SizedBox(width: 10 * s),
                  cell(l, true),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class NibpWindow extends StatelessWidget {
  const NibpWindow({super.key, required this.sim, required this.onClose});
  final PatientSim sim;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    const modes = [0, 1, 2, 3, 5, 10, 15, 30];
    return MonitorWindow(
      title: 'NIBP Mode',
      width: 300,
      onClose: onClose,
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final m in modes)
            SetupRow(
              m == 0 ? 'Manual' : 'Auto every $m min',
              sim.nibpAuto == m ? '●' : '',
              selected: sim.nibpAuto == m,
              onTap: () => sim.setNibpAuto(m),
            ),
        ],
      ),
    );
  }
}

class TrendsWindow extends StatelessWidget {
  const TrendsWindow({super.key, required this.sim, required this.settings, required this.onClose});
  final PatientSim sim;
  final MonitorSettings settings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    String t2(int n) => n.toString().padLeft(2, '0');
    String v(num? x) => x == null ? '-?-' : '$x';
    final rows = sim.trends.reversed.take(14).toList();
    final cols = <(String, Color, String Function(TrendRow))>[
      ('Time', MC.text, (r) => '${t2(r.time.hour)}:${t2(r.time.minute)}'),
      ('HR', MC.ecg, (r) => v(r.hr)),
      ('SpO₂', MC.spo2, (r) => v(r.spo2)),
      ('NIBP', MC.nibp, (r) => r.nibp ?? ''),
      ('awRR', MC.co2, (r) => v(r.rr)),
      ('etCO₂', MC.co2, (r) => v(r.etco2)),
      (
        'Temp',
        MC.temp,
        (r) => settings.fahrenheit ? (r.temp * 9 / 5 + 32).toStringAsFixed(1) : r.temp.toStringAsFixed(1),
      ),
    ];
    const flex = [3, 2, 2, 5, 2, 2, 2];
    Widget line(List<String> cells, {bool head = false}) => Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4.5 * s),
      decoration: BoxDecoration(
        color: head ? const Color(0xFF223040) : null,
        border: const Border(bottom: BorderSide(color: Color(0xFF2B3947))),
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              flex: flex[i],
              child: Text(
                cells[i],
                style: labelStyle(
                  13.5 * s,
                  cols[i].$2,
                  weight: head ? 650 : 500,
                ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
        ],
      ),
    );
    return MonitorWindow(
      title: 'Vital Signs Trend',
      width: 560,
      onClose: onClose,
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          line([for (final c in cols) c.$1], head: true),
          for (final r in rows) line([for (final c in cols) c.$3(r)]),
        ],
      ),
    );
  }
}

/// Lead and size picker shown when an ECG trace is touched.
class EcgWindow extends StatelessWidget {
  const EcgWindow({super.key, required this.settings, required this.second, required this.onClose});
  final MonitorSettings settings;

  /// True when this is for the second ECG row.
  final bool second;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = Scale.of(context);
    final cur = second ? settings.ecg2 : settings.ecg1;
    return MonitorWindow(
      title: second ? 'ECG Wave 2 Lead' : 'ECG Wave 1 Lead',
      width: 330,
      onClose: onClose,
      child: Padding(
        padding: EdgeInsets.all(8 * s),
        child: Wrap(
          spacing: 6 * s,
          runSpacing: 6 * s,
          children: [
            for (final l in Lead.values)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => settings.update(() => second ? settings.ecg2 = l : settings.ecg1 = l),
                child: Container(
                  width: 72 * s,
                  height: 38 * s,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: l == cur ? MC.select : MC.key,
                    border: Border.all(color: const Color(0xFF6B7F92)),
                    borderRadius: BorderRadius.circular(3 * s),
                  ),
                  child: Text(kLeadNames[l]!, style: labelStyle(15 * s, MC.text, weight: 650)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Picks which arrangement of the screen is showing.
class ScreenWindow extends StatelessWidget {
  const ScreenWindow({super.key, required this.settings, required this.onClose});
  final MonitorSettings settings;
  final VoidCallback onClose;

  static const _notes = {
    ScreenLayout.full: 'Every wave and number',
    ScreenLayout.standard: 'Waves from Main Setup',
    ScreenLayout.big: 'Readable from afar',
    ScreenLayout.trends: 'The last hour as graphs',
    ScreenLayout.review: 'ST map and alarm history',
  };

  @override
  Widget build(BuildContext context) {
    return MonitorWindow(
      title: 'Change Screen',
      width: 400,
      onClose: onClose,
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final l in ScreenLayout.values)
            SetupRow(
              kLayoutNames[l]!,
              _notes[l]!,
              selected: settings.layout == l,
              onTap: () => settings.update(() => settings.layout = l),
            ),
        ],
      ),
    );
  }
}
