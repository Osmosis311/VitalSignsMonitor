import 'package:flutter/material.dart';

import '../app/settings.dart';
import '../sim/patient_sim.dart';
import '../sim/rhythms.dart';
import '../sim/scenarios.dart';

/// The operator's panel: everything that decides what the monitor shows.
///
/// It is not part of the monitor's own interface and nothing on the screen
/// hints at it. Long-press the clock (or press H on a keyboard) to open it.
class ControlPanel extends StatefulWidget {
  const ControlPanel({
    super.key,
    required this.sim,
    required this.settings,
    required this.onClose,
    this.beds = const [],
    this.bed = 0,
    this.onBed,
  });
  final PatientSim sim;
  final MonitorSettings settings;
  final VoidCallback onClose;

  /// Bed labels when the central station is in use; the panel drives one
  /// patient at a time.
  final List<String> beds;
  final int bed;
  final ValueChanged<int>? onBed;

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  int _tab = 0;

  PatientSim get sim => widget.sim;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D8BD9), brightness: Brightness.dark),
        visualDensity: VisualDensity.compact,
      ),
      child: Material(
        color: const Color(0xFB141B23),
        elevation: 12,
        child: SafeArea(
          left: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Control panel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    IconButton(onPressed: widget.onClose, icon: const Icon(Icons.close), tooltip: 'Close'),
                  ],
                ),
              ),
              if (widget.beds.length > 1)
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                    children: [
                      for (var i = 0; i < widget.beds.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(widget.beds[i]),
                            selected: i == widget.bed,
                            showCheckmark: false,
                            onSelected: (_) => widget.onBed?.call(i),
                          ),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Rhythm')),
                    ButtonSegment(value: 1, label: Text('Vitals')),
                    ButtonSegment(value: 2, label: Text('Scenarios')),
                    ButtonSegment(value: 3, label: Text('Events')),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (v) => setState(() => _tab = v.first),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListenableBuilder(
                  listenable: sim,
                  builder: (context, _) => switch (_tab) {
                    0 => _rhythms(),
                    1 => _vitals(),
                    2 => _scenarios(),
                    _ => _events(),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- rhythm --

  Widget _rhythms() {
    final r = sim.rhythm;
    final groups = <String, List<RhythmDef>>{};
    for (final d in kRhythms) {
      groups.putIfAbsent(d.group, () => []).add(d);
    }
    return Column(
      children: [
        if (!r.fixedRate)
          _slider(
            'Rate',
            sim.rate.target,
            r.minRate.toDouble(),
            r.maxRate.toDouble(),
            (v) => sim.setRate(v, over: 1.5),
            unit: 'bpm',
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('This rhythm sets its own rate', style: TextStyle(color: Colors.white54)),
          ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              for (final g in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: Text(
                    g.key.toUpperCase(),
                    style: const TextStyle(fontSize: 11, letterSpacing: 1.1, color: Colors.white54),
                  ),
                ),
                for (final d in g.value)
                  ListTile(
                    dense: true,
                    selected: d.id == r.id,
                    selectedTileColor: const Color(0xFF244A73),
                    selectedColor: Colors.white,
                    title: Text(d.name),
                    trailing: Text(
                      d.fixedRate ? (d.rate > 0 ? '${d.rate}' : '') : '${d.rate}',
                      style: const TextStyle(color: Colors.white54),
                    ),
                    onTap: () {
                      sim.stopScenario();
                      sim.setRhythm(d.id);
                    },
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- vitals --

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    String unit = '',
    int decimals = 0,
    int? divisions,
  }) {
    final v = value.clamp(min, max).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 0),
      child: Row(
        children: [
          SizedBox(width: 78, child: Text(label)),
          Expanded(
            child: Slider(
              value: v,
              min: min,
              max: max,
              divisions: divisions ?? (max - min).round(),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 74,
            child: Text('${v.toStringAsFixed(decimals)} $unit', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _vitals() {
    final r = sim.rhythm;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (!r.fixedRate)
          _slider(
            'Heart rate',
            sim.rate.target,
            r.minRate.toDouble(),
            r.maxRate.toDouble(),
            (v) => sim.setRate(v, over: 1.5),
            unit: 'bpm',
          ),
        _slider('SpO₂', sim.spo2.target, 50, 100, (v) => sim.spo2.set(v, 6), unit: '%'),
        _slider(
          'BP systolic',
          sim.sys.target,
          40,
          240,
          (v) => sim.setBp(v, sim.dia.target.clamp(20, v - 10).toDouble(), over: 4),
          unit: 'mmHg',
        ),
        _slider(
          'BP diastolic',
          sim.dia.target,
          20,
          140,
          (v) => sim.setBp(sim.sys.target < v + 10 ? v + 10 : sim.sys.target, v, over: 4),
          unit: 'mmHg',
        ),
        _slider('Resp rate', sim.respRate.target, 0, 50, (v) => sim.respRate.set(v, 4), unit: '/min'),
        _slider('etCO₂', sim.etco2.target, 5, 90, (v) => sim.etco2.set(v, 6), unit: 'mmHg'),
        _slider('Temp', sim.temp.target, 33, 41.5, (v) => sim.temp.set(v, 4), unit: '°C', decimals: 1, divisions: 85),
        _slider(
          'Airway obstr.',
          sim.obstruction.target * 100,
          0,
          100,
          (v) => sim.obstruction.set(v / 100, 3),
          unit: '%',
          divisions: 20,
        ),
        _slider('CVP', sim.cvp.target, 0, 25, (v) => sim.cvp.set(v, 5), unit: 'mmHg'),
        _slider('PA systolic', sim.paSys.target, 10, 80, (v) {
          sim.paSys.set(v, 5);
          sim.paDia.set(v * 0.4, 5);
        }, unit: 'mmHg'),
        _slider('ICP', sim.icp.target, 0, 50, (v) => sim.icp.set(v, 6), unit: 'mmHg'),
        _slider('Sedation', sim.bis.target, 0, 98, (v) => sim.bis.set(v, 8), unit: 'BIS'),
        _slider('Paralysis', sim.nmt.target * 100, 0, 100, (v) => sim.nmt.set(v / 100, 3), unit: '%', divisions: 20),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              const SizedBox(width: 78, child: Text('Breathing')),
              Expanded(
                child: SegmentedButton<VentMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: VentMode.spontaneous, label: Text('Own')),
                    ButtonSegment(value: VentMode.assisted, label: Text('Bagged')),
                    ButtonSegment(value: VentMode.none, label: Text('None')),
                  ],
                  selected: {sim.vent},
                  onSelectionChanged: (v) => sim.setVent(v.first),
                ),
              ),
            ],
          ),
        ),
        SwitchListTile(
          dense: true,
          title: const Text('No pulse (PEA)'),
          subtitle: const Text('Keeps the rhythm, removes the pulse'),
          value: sim.forcePulseless,
          onChanged: sim.setForcePulseless,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
          child: OutlinedButton.icon(
            onPressed: sim.reset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset to a healthy patient'),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- scenarios --

  Widget _scenarios() {
    final running = sim.scenario;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (running != null)
          Container(
            margin: const EdgeInsets.fromLTRB(10, 2, 10, 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFF244A73), borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(running.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    TextButton(onPressed: sim.stopScenario, child: const Text('Stop')),
                  ],
                ),
                Text(sim.scenarioNote),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: running.length <= 0 ? 1 : (sim.scenarioElapsed / running.length).clamp(0.0, 1.0).toDouble(),
                ),
                const SizedBox(height: 4),
                Text(
                  sim.scenarioElapsed >= running.length
                      ? 'Finished - holding the last state'
                      : '${sim.scenarioElapsed.round()} s of ${running.length.round()} s',
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ],
            ),
          ),
        for (final sc in kScenarios)
          ListTile(
            dense: true,
            selected: sc.id == running?.id,
            title: Text(sc.name),
            subtitle: Text(sc.summary),
            trailing: const Icon(Icons.play_arrow),
            onTap: () => sim.runScenario(sc),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------- events --

  Widget _events() {
    Widget b(String label, IconData icon, VoidCallback f) =>
        FilledButton.tonalIcon(onPressed: f, icon: Icon(icon, size: 18), label: Text(label));
    final st = widget.settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            b('PVC', Icons.bolt, () => sim.injectPvcs(1)),
            b('Couplet', Icons.bolt, () => sim.injectPvcs(2)),
            b('Run of VT', Icons.bolt, () => sim.injectPvcs(7)),
            b('Shock', Icons.flash_on, () => sim.shock()),
            b('Patient moves', Icons.directions_run, () => sim.motionArtifact(5)),
            b('Take a blood pressure', Icons.compress, sim.startNibp),
            b('Silence alarms', Icons.notifications_off, sim.silence),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'PVCs land after the next normal beat, in sinus rhythms and A-fib. '
          'A shock converts shockable rhythms to sinus.',
          style: TextStyle(fontSize: 12, color: Colors.white60),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('CPR in progress'),
          subtitle: const Text('Compression artifact; low etCO₂ if being bagged'),
          value: sim.cpr,
          onChanged: sim.setCpr,
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('ECG leads off'),
          value: sim.leadsOff,
          onChanged: sim.setLeadsOff,
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('SpO₂ probe off'),
          value: sim.probeOff,
          onChanged: sim.setProbeOff,
        ),
        const Divider(),
        ListenableBuilder(
          listenable: st,
          builder: (context, _) => SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Show the DEMO tag'),
            subtitle: const Text('Small label in the top bar marking this as a simulation'),
            value: st.showDemoTag,
            onChanged: (v) => st.update(() => st.showDemoTag = v),
          ),
        ),
      ],
    );
  }
}
