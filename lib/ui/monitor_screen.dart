import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app/settings.dart';
import '../app/sounds.dart';
import '../sim/alarms.dart';
import '../sim/ecg_shapes.dart';
import '../sim/patient_sim.dart';
import '../sim/wave_buffer.dart';
import 'control_panel.dart';
import 'extras.dart';
import 'numerics.dart';
import 'soft_keys.dart';
import 'status_bar.dart';
import 'theme.dart';
import 'wave_channel.dart';
import 'windows.dart';

enum _Win { none, setup, limits, trends, nibp, ecg1, ecg2, screen, strip }

/// One horizontal band of the main area: a trace, and optionally the
/// mini-trend and the numeric that sit beside it. A band without a numeric
/// (or trend) lets the one above it stretch down across it.
class _Band {
  const _Band(this.flex, this.wave, {this.tile, this.trend});
  final int flex;
  final Widget wave;
  final Widget? tile;
  final Widget? trend;
}

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({
    super.key,
    required this.sim,
    required this.settings,
    required this.sounds,
    this.showBoot = true,
  });

  final PatientSim sim;
  final MonitorSettings settings;
  final SoundBoard sounds;

  /// Start on the self-test screen that carries the simulation notice.
  final bool showBoot;

  @override
  State<MonitorScreen> createState() => MonitorScreenState();
}

class MonitorScreenState extends State<MonitorScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  Timer? _blinkTimer;
  Timer? _bootTimer;
  bool _blink = false;

  _Win _win = _Win.none;
  bool _panel = false;
  bool _standby = false;
  bool _twelve = false;
  bool _frozen = false;
  late bool _boot = widget.showBoot;

  final Map<Object, WaveSource> _live = {};
  final Map<Object, WaveSource> _snap = {};
  WaveSource? _strip;
  String _stripHeader = '';

  double _abpLo = 60, _abpHi = 140;
  int _abpWait = 0;
  AlarmPriority? _lastTone;
  double _nextToneAt = 0;

  PatientSim get sim => widget.sim;
  MonitorSettings get st => widget.settings;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _blink = !_blink);
    });
    if (_boot) {
      _bootTimer = Timer(const Duration(milliseconds: 4500), () {
        if (mounted) setState(() => _boot = false);
      });
    }
    sim.addListener(_onSim);
    st.addListener(_onSettings);
    sim.onBeat = (b) {
      if (!_standby && !_boot) widget.sounds.qrs(sim.spo2Value, st.qrsVolume);
    };
    _onSettings();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _ticker.dispose();
    _blinkTimer?.cancel();
    _bootTimer?.cancel();
    sim.removeListener(_onSim);
    st.removeListener(_onSettings);
    sim.onBeat = null;
    _frame.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_standby || _boot) return;
    sim.advance(dt);
    if (!_frozen) _frame.value++;
  }

  void _onSettings() {
    sim.abpOn = st.abpOn;
    sim.co2On = st.co2On;
    sim.papOn = st.papOn;
    sim.cvpOn = st.cvpOn;
    sim.icpOn = st.icpOn;
    if (mounted) setState(() {});
  }

  void _onSim() {
    // Arterial scale: follow the pressure, but only move when it has to.
    final s = sim.abpS, d = sim.abpD;
    if (s != null && d != null) {
      final lo = math.max(0, ((d - 12) / 20).floor() * 20).toDouble();
      final hi = math.max(lo + 40, ((s + 12) / 20).ceil() * 20).toDouble();
      final clipped = s > _abpHi - 2 || d < _abpLo + 2;
      _abpWait = lo == _abpLo && hi == _abpHi ? 0 : _abpWait + 1;
      if (clipped || _abpWait > 8) {
        _abpLo = lo;
        _abpHi = hi;
        _abpWait = 0;
      }
    }

    // Alarm tones repeat for as long as something is unacknowledged.
    final p = _standby ? null : sim.soundingPriority;
    if (p == null) {
      if (_lastTone != null) widget.sounds.stopAlarm();
      _lastTone = null;
    } else if (p != _lastTone || sim.t >= _nextToneAt) {
      widget.sounds.alarm(p, st.alarmVolume);
      _lastTone = p;
      _nextToneAt =
          sim.t +
          switch (p) {
            AlarmPriority.high => 5.0,
            AlarmPriority.medium => 8.0,
            AlarmPriority.technical => 15.0,
          };
    }
    if (mounted) setState(() {});
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) return false;
    if (e.logicalKey == LogicalKeyboardKey.keyH || e.logicalKey == LogicalKeyboardKey.backquote) {
      togglePanel();
      return true;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      setState(() {
        _win = _Win.none;
        _panel = false;
      });
      return true;
    }
    return false;
  }

  /// Opens or closes the hidden control panel.
  void togglePanel() => setState(() => _panel = !_panel);

  void _open(_Win w) {
    widget.sounds.key(st.qrsVolume == 0 ? 0 : 2);
    setState(() => _win = _win == w ? _Win.none : w);
  }

  void _press(VoidCallback f) {
    widget.sounds.key(st.qrsVolume == 0 ? 0 : 2);
    setState(f);
  }

  void _record() {
    final lead = st.ecg1;
    final now = sim.clock();
    String t2(int n) => n.toString().padLeft(2, '0');
    _strip = WaveSnapshot(_live.putIfAbsent(lead, () => sim.lead(lead)), 6);
    _stripHeader =
        '${st.bedLabel}   ${st.patientName.isEmpty ? '' : '${st.patientName}   '}'
        '${t2(now.hour)}:${t2(now.minute)}:${t2(now.second)}   Lead ${kLeadNames[lead]}   25 mm/s   10 mm/mV   '
        'HR ${fmt(sim.hr)}   SpO2 ${fmt(sim.spo2Value)}   Monitor 0.5-40 Hz';
    sim.recordStrip();
    _open(_Win.strip);
  }

  // --------------------------------------------------------------- sources --

  WaveSource _src(Object key, WaveSource Function() make, {double keep = 16}) {
    final live = _live.putIfAbsent(key, make);
    if (!_frozen) return live;
    return _snap.putIfAbsent(key, () => WaveSnapshot(live, keep));
  }

  // ----------------------------------------------------------------- waves --

  Widget _ecg(Lead lead, {VoidCallback? onTap, bool compact = false, bool cal = true}) {
    final g = st.ecgGain;
    return WaveChannel(
      source: _src(lead, () => sim.lead(lead)),
      repaint: _frame,
      color: MC.ecg,
      mmPerSec: st.sweep,
      lo: -0.95 / g,
      hi: 1.5 / g,
      label: kLeadNames[lead],
      sublabel: compact ? null : '×${g == 0.5 ? '½' : g.toStringAsFixed(0)}',
      calBar: cal ? 1 : null,
      message: sim.leadsOff ? 'LEADS OFF' : null,
      onTap: onTap,
      compact: compact,
    );
  }

  Widget _plethWave() => WaveChannel(
    source: _src('pleth', () => sim.pleth),
    repaint: _frame,
    color: MC.spo2,
    mmPerSec: st.sweep,
    lo: -0.08,
    hi: 1.08,
    label: 'Pleth',
    message: sim.probeOff ? 'SENSOR OFF' : null,
  );

  Widget _abpWave() {
    final mid = ((_abpLo + _abpHi) / 2).round();
    return WaveChannel(
      source: _src('abp', () => sim.abp),
      repaint: _frame,
      color: MC.abp,
      mmPerSec: st.sweep,
      lo: _abpLo,
      hi: _abpHi,
      label: 'ABP',
      marks: [
        ScaleMark(_abpHi, '${_abpHi.round()}'),
        ScaleMark(mid.toDouble(), '$mid'),
        ScaleMark(_abpLo, '${_abpLo.round()}'),
      ],
    );
  }

  /// A low-pressure trace on a 0-based scale that steps up when it has to.
  Widget _pressure(String key, String label, WaveBuffer buf, Color color, int? reading, double normal) {
    var hi = normal;
    while ((reading ?? 0) > hi * 0.82) {
      hi *= 2;
    }
    return WaveChannel(
      source: _src(key, () => buf),
      repaint: _frame,
      color: color,
      mmPerSec: st.sweep,
      lo: -hi * 0.06,
      hi: hi,
      label: label,
      marks: [ScaleMark(hi, '${hi.round()}'), ScaleMark(hi / 2, '${(hi / 2).round()}'), const ScaleMark(0, '0')],
    );
  }

  Widget _co2Wave() {
    final e = sim.etco2Value ?? 0;
    final hi = e > 72 ? 100.0 : (e > 46 ? 80.0 : 50.0);
    return WaveChannel(
      source: _src('co2', () => sim.co2, keep: 70),
      repaint: _frame,
      color: MC.co2,
      mmPerSec: st.sweep / 4,
      lo: -2,
      hi: hi,
      label: 'CO₂',
      fill: true,
      marks: [ScaleMark(hi, '${hi.round()}'), const ScaleMark(40, '40'), const ScaleMark(0, '0')],
    );
  }

  Widget _respWave() => WaveChannel(
    source: _src('resp', () => sim.resp, keep: 70),
    repaint: _frame,
    color: MC.resp,
    mmPerSec: st.sweep / 4,
    lo: -0.25,
    hi: 1.45,
    label: 'Resp',
  );

  Widget _eegWave() => WaveChannel(
    source: _src('eeg', () => sim.eeg),
    repaint: _frame,
    color: MC.eeg,
    mmPerSec: st.sweep,
    lo: -75,
    hi: 75,
    label: 'EEG',
    sublabel: '50 µV',
    compact: true,
  );

  Widget _twelveLead() {
    const left = [Lead.i, Lead.ii, Lead.iii, Lead.avr, Lead.avl, Lead.avf];
    const right = [Lead.v1, Lead.v2, Lead.v3, Lead.v4, Lead.v5, Lead.v6];
    Widget col(List<Lead> leads) => Expanded(
      child: Column(
        children: [
          for (final l in leads)
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF14202B)),
                    right: BorderSide(color: Color(0xFF14202B)),
                  ),
                ),
                child: _ecg(l, compact: true, cal: false),
              ),
            ),
        ],
      ),
    );
    return Row(children: [col(left), col(right)]);
  }

  // ----------------------------------------------------------------- tiles --

  bool _flash(Alarm? a) => a != null && _blink;
  String _lo(LimitKey k) => sim.limits[k]!.fmt(sim.limits[k]!.lo);
  String _hi(LimitKey k) => sim.limits[k]!.fmt(sim.limits[k]!.hi);
  void _limits() => _open(_Win.limits);

  Widget _hrTile({double scale = 1}) {
    final s = Scale.of(context);
    final a = sim.alarmFor(Param.hr);
    final stMm = sim.stFor(st.ecg1);
    return ParamTile(
      label: 'HR',
      unit: 'bpm',
      color: MC.ecg,
      value: fmt(sim.hr),
      limitHi: _hi(LimitKey.hr),
      limitLo: _lo(LimitKey.hr),
      alarm: a,
      blink: _flash(a),
      alarmsOff: sim.alarmsPaused,
      valueScale: scale,
      corner: BeatHeart(tick: sim.beatTick, size: (20 * s).clamp(12.0, 34.0), color: MC.ecg),
      footer: [
        'PVC ${sim.pvcPerMin}',
        if (stMm != null) 'ST-${kLeadNames[st.ecg1]} ${stMm >= 0.05 ? '+' : ''}${stMm.toStringAsFixed(1)}',
        if (sim.qtc != null) 'QTc ${sim.qtc}',
        if (sim.pacing) 'Paced',
      ],
      onTap: _limits,
    );
  }

  Widget _spo2Tile() {
    final s = Scale.of(context);
    final a = sim.alarmFor(Param.spo2);
    final quality = sim.spo2Value == null ? 0 : (sim.perf > 1.5 ? 4 : (sim.perf > 0.8 ? 3 : 2));
    return ParamTile(
      label: 'SpO₂',
      unit: '%',
      color: MC.spo2,
      value: fmt(sim.spo2Value),
      limitHi: _hi(LimitKey.spo2),
      limitLo: _lo(LimitKey.spo2),
      alarm: a,
      blink: _flash(a),
      alarmsOff: sim.alarmsPaused,
      gauge: PulseBar(
        source: sim.pleth,
        repaint: _frame,
        color: _flash(a) && !a!.acked ? MC.onAlarm(a.priority) : MC.spo2,
      ),
      badge: SignalBars(
        level: quality,
        color: _flash(a) && !a!.acked ? MC.onAlarm(a.priority) : MC.spo2,
        size: (11 * s).clamp(7.0, 20.0),
      ),
      footer: ['Pulse ${fmt(sim.pulse)}', if (sim.spo2Value != null) 'Perf ${sim.perf.toStringAsFixed(1)}'],
      onTap: _limits,
    );
  }

  Widget _abpTile() {
    final a = sim.alarmFor(Param.abp);
    return ParamTile(
      label: 'ABP',
      unit: 'mmHg',
      color: MC.abp,
      value: fmtBp(sim.abpS, sim.abpD),
      side: '(${fmt(sim.abpM)})',
      limitHi: _hi(LimitKey.abpSys),
      limitLo: _lo(LimitKey.abpSys),
      alarm: a,
      blink: _flash(a),
      alarmsOff: sim.alarmsPaused,
      onTap: _limits,
    );
  }

  Widget _papTile() {
    final a = sim.alarmFor(Param.pap);
    return ParamTile(
      label: 'PAP',
      unit: 'mmHg',
      color: MC.pap,
      value: fmtBp(sim.papS, sim.papD),
      side: '(${fmt(sim.papM)})',
      limitHi: _hi(LimitKey.papSys),
      limitLo: _lo(LimitKey.papSys),
      alarm: a,
      blink: _flash(a),
      alarmsOff: sim.alarmsPaused,
      onTap: _limits,
    );
  }

  Widget _cvpTile() {
    final a = sim.alarmFor(Param.cvp);
    return ParamTile(
      label: 'CVP',
      unit: 'mmHg',
      color: MC.cvp,
      value: '(${fmt(sim.cvpValue)})',
      limitHi: _hi(LimitKey.cvp),
      limitLo: _lo(LimitKey.cvp),
      alarm: a,
      blink: _flash(a),
      alarmsOff: sim.alarmsPaused,
      onTap: _limits,
    );
  }

  Widget _icpTile() {
    final a = sim.alarmFor(Param.icp);
    return ParamTile(
      label: 'ICP',
      unit: 'mmHg',
      color: MC.icp,
      value: '(${fmt(sim.icpValue)})',
      side: 'CPP ${fmt(sim.cpp)}',
      limitHi: _hi(LimitKey.icp),
      limitLo: _lo(LimitKey.icp),
      alarm: a,
      blink: _flash(a),
      alarmsOff: sim.alarmsPaused,
      onTap: _limits,
    );
  }

  Widget _co2Tile() {
    final a = sim.alarmFor(Param.co2);
    return ParamTile(
      label: 'etCO₂',
      unit: 'mmHg',
      color: MC.co2,
      value: fmt(sim.etco2Value),
      limitHi: _hi(LimitKey.etco2),
      limitLo: _lo(LimitKey.etco2),
      alarm: a,
      blink: _flash(a),
      alarmsOff: sim.alarmsPaused,
      footer: ['awRR ${fmt(sim.awrr)} rpm'],
      onTap: _limits,
    );
  }

  Widget _rrTile() => ParamTile(
    label: 'RR',
    unit: 'rpm',
    color: MC.resp,
    value: fmt(sim.awrr),
    limitHi: _hi(LimitKey.awrr),
    limitLo: _lo(LimitKey.awrr),
    alarmsOff: sim.alarmsPaused,
    onTap: _limits,
  );

  Widget _bisTile() => ParamTile(
    label: 'BIS',
    color: MC.eeg,
    value: fmt(sim.bisValue),
    side: 'SQI ${sim.sqi}',
    footer: ['EMG ${sim.emg} dB', 'SR ${sim.suppression}%'],
  );

  Widget _nibpTile() {
    final measuring = sim.nibpPhase != NibpPhase.idle;
    final a = sim.alarmFor(Param.nibp);
    final tm = sim.nibpTime;
    String t2(int n) => n.toString().padLeft(2, '0');
    final cd = sim.nibpCountdown;
    return ParamTile(
      label: 'NIBP',
      unit: 'mmHg',
      color: MC.nibp,
      value: measuring ? '${sim.cuff.round()}' : fmtBp(sim.nibpS, sim.nibpD),
      side: measuring ? null : '(${fmt(sim.nibpM)})',
      limitHi: _hi(LimitKey.nibpSys),
      limitLo: _lo(LimitKey.nibpSys),
      alarm: a,
      blink: _flash(a),
      alarmsOff: sim.alarmsPaused,
      footer: [
        if (measuring)
          'Cuff pressure - measuring'
        else ...[
          sim.nibpAuto == 0 ? 'Manual' : 'Auto ${sim.nibpAuto} min',
          if (tm != null) '@ ${t2(tm.hour)}:${t2(tm.minute)}',
          if (cd != null) 'Next ${cd ~/ 60}:${t2(cd % 60)}',
        ],
      ],
      onTap: () => _press(() => measuring ? sim.stopNibp() : sim.startNibp()),
    );
  }

  String _temp(double c) => (st.fahrenheit ? c * 9 / 5 + 32 : c).toStringAsFixed(1);

  Widget _tempTile() {
    final a = sim.alarmFor(Param.temp);
    final lt = sim.limits[LimitKey.temp]!;
    return ParamTile(
      label: 'Temp',
      unit: st.fahrenheit ? '°F' : '°C',
      color: MC.temp,
      value: _temp(sim.tempValue),
      limitHi: _temp(lt.hi),
      limitLo: _temp(lt.lo),
      alarm: a,
      blink: _flash(a),
      alarmsOff: sim.alarmsPaused,
      onTap: _limits,
    );
  }

  Widget _tempsTile() {
    final d = sim.tempValue - sim.temp2Value;
    return MultiTile(
      label: 'Temp',
      unit: st.fahrenheit ? '°F' : '°C',
      color: MC.temp,
      items: [
        ('T1 core', _temp(sim.tempValue)),
        ('T2 skin', _temp(sim.temp2Value)),
        ('ΔT', (st.fahrenheit ? d * 9 / 5 : d).toStringAsFixed(1)),
      ],
      onTap: _limits,
    );
  }

  Widget _coTile() => MultiTile(
    label: 'C.O.',
    unit: 'L/min',
    color: MC.cco,
    items: [
      ('CCO', sim.cardiacOutput?.toStringAsFixed(1) ?? '-?-'),
      ('C.I.', sim.cardiacIndex?.toStringAsFixed(1) ?? '-?-'),
      ('SV', fmt(sim.strokeVolume)),
      ('SVR', fmt(sim.svr)),
      ('SVV %', fmt(sim.svv)),
    ],
  );

  // --------------------------------------------------------------- layouts --

  List<_Band> _bands() {
    MiniTrend trend(List<String> keys, Color c) => MiniTrend(sim: sim, keys: keys, color: c);
    switch (st.layout) {
      case ScreenLayout.trends:
        TrendGraph graph(String label, List<String> keys, List<Color> colors) =>
            TrendGraph(sim: sim, label: label, keys: keys, colors: colors);
        return [
          _Band(5, _ecg(st.ecg1, onTap: () => _open(_Win.ecg1)), tile: _hrTile(scale: 0.8)),
          _Band(5, graph('HR  bpm', const ['hr'], const [MC.ecg])),
          _Band(4, _plethWave(), tile: _spo2Tile()),
          _Band(4, graph('SpO₂  %', const ['spo2'], const [MC.spo2])),
          _Band(6, graph('ABP  mmHg', const ['abpS', 'abpM', 'abpD'], const [MC.abp]), tile: _abpTile()),
          _Band(5, graph('etCO₂  mmHg   awRR  rpm', const ['etco2', 'rr'], const [MC.co2, MC.resp]), tile: _co2Tile()),
        ];
      case ScreenLayout.review:
        return [
          _Band(6, _ecg(st.ecg1, onTap: () => _open(_Win.ecg1)), tile: _hrTile(scale: 0.75)),
          _Band(5, _ecg(st.ecg2, onTap: () => _open(_Win.ecg2))),
          _Band(4, _plethWave(), tile: _spo2Tile()),
          _Band(
            14,
            Row(
              children: [
                Expanded(flex: 6, child: StBars(sim: sim)),
                Expanded(flex: 5, child: EventLog(sim: sim)),
              ],
            ),
            tile: Column(
              children: [
                Expanded(child: _abpTile()),
                Expanded(child: _co2Tile()),
              ],
            ),
          ),
        ];
      case ScreenLayout.full:
      case ScreenLayout.standard:
      case ScreenLayout.big:
        final two = st.ecg2On;
        return [
          _Band(
            6,
            _ecg(st.ecg1, onTap: () => _open(_Win.ecg1)),
            tile: _hrTile(scale: two ? 0.72 : 1),
            trend: trend(const ['hr'], MC.ecg),
          ),
          if (two) _Band(5, _ecg(st.ecg2, onTap: () => _open(_Win.ecg2))),
          _Band(5, _plethWave(), tile: _spo2Tile(), trend: trend(const ['spo2'], MC.spo2)),
          if (st.abpOn) _Band(5, _abpWave(), tile: _abpTile(), trend: trend(const ['abpS', 'abpD'], MC.abp)),
          if (st.papOn)
            _Band(
              4,
              _pressure('pap', 'PAP', sim.pap, MC.pap, sim.papS, 40),
              tile: _papTile(),
              trend: trend(const ['pap'], MC.pap),
            ),
          if (st.cvpOn)
            _Band(
              4,
              _pressure('cvp', 'CVP', sim.cvpWave, MC.cvp, sim.cvpValue, 15),
              tile: _cvpTile(),
              trend: trend(const ['cvp'], MC.cvp),
            ),
          if (st.icpOn)
            _Band(
              4,
              _pressure('icp', 'ICP', sim.icpWave, MC.icp, sim.icpValue, 20),
              tile: _icpTile(),
              trend: trend(const ['icp'], MC.icp),
            ),
          if (st.co2On) _Band(5, _co2Wave(), tile: _co2Tile(), trend: trend(const ['etco2'], MC.co2)),
          if (st.respOn) _Band(4, _respWave(), tile: _rrTile(), trend: trend(const ['rr'], MC.resp)),
          if (st.eegOn) _Band(4, _eegWave(), tile: _bisTile(), trend: trend(const ['bis'], MC.eeg)),
        ];
    }
  }

  /// Stacks one column of the bands, letting an item run down across the
  /// bands below it that have nothing of their own in this column.
  Widget _stack(List<_Band> bands, Widget? Function(_Band) pick) {
    final out = <Widget>[];
    Widget? cur;
    var flex = 0;
    for (final b in bands) {
      final w = pick(b);
      if (w != null) {
        if (cur != null) out.add(Expanded(flex: flex, child: cur));
        cur = w;
        flex = b.flex;
      } else {
        flex += b.flex;
      }
    }
    if (cur != null) out.add(Expanded(flex: flex, child: cur));
    return Column(children: out);
  }

  Widget _bigNumbers() => Column(
    children: [
      Expanded(flex: 20, child: _ecg(st.ecg1, onTap: () => _open(_Win.ecg1))),
      Expanded(
        flex: 42,
        child: Row(
          children: [
            Expanded(flex: 5, child: _hrTile()),
            Expanded(flex: 5, child: _spo2Tile()),
            Expanded(flex: 7, child: _abpTile()),
          ],
        ),
      ),
      Expanded(
        flex: 38,
        child: Row(
          children: [
            Expanded(flex: 7, child: _nibpTile()),
            Expanded(flex: 5, child: _co2Tile()),
            Expanded(flex: 5, child: _tempTile()),
          ],
        ),
      ),
    ],
  );

  List<Widget> _lowerRows() {
    if (st.extrasOn) {
      return [
        Expanded(
          flex: 15,
          child: Row(
            children: [
              Expanded(flex: 7, child: _nibpTile()),
              Expanded(flex: 6, child: _tempsTile()),
              Expanded(flex: 9, child: _coTile()),
              Expanded(flex: 3, child: TofTile(sim: sim)),
            ],
          ),
        ),
        Expanded(
          flex: 11,
          child: Row(
            children: [
              Expanded(flex: 9, child: StPanel(sim: sim)),
              Expanded(
                flex: 11,
                child: InfusionStrip(sim: sim, blink: _blink),
              ),
              Expanded(flex: 5, child: TimerTile(sim: sim)),
            ],
          ),
        ),
      ];
    }
    return [
      Expanded(
        flex: 17,
        child: Row(
          children: [
            Expanded(flex: 7, child: _nibpTile()),
            Expanded(flex: 3, child: _tempTile()),
          ],
        ),
      ),
    ];
  }

  // ------------------------------------------------------------- soft keys --

  List<SoftKey> _keys() {
    final measuring = sim.nibpPhase != NibpPhase.idle;
    final paused = sim.alarmsPaused;
    return [
      SoftKey('Silence', Icons.notifications_off_outlined, () {
        widget.sounds.stopAlarm();
        _press(sim.silence);
      }),
      SoftKey(
        paused ? 'Resume Alarms' : 'Pause Alarms',
        Icons.notifications_paused_outlined,
        () => _press(() {
          widget.sounds.stopAlarm();
          paused ? sim.resumeAlarms() : sim.pauseAlarms();
        }),
        lit: paused,
        warn: true,
      ),
      SoftKey(
        measuring ? 'Stop NIBP' : 'Start NIBP',
        Icons.compress,
        () => _press(() => measuring ? sim.stopNibp() : sim.startNibp()),
        lit: measuring,
      ),
      SoftKey('NIBP Mode', Icons.timer_outlined, () => _open(_Win.nibp), lit: _win == _Win.nibp),
      SoftKey(
        _frozen ? 'Unfreeze' : 'Freeze Waves',
        Icons.ac_unit,
        () => _press(() {
          _snap.clear();
          _frozen = !_frozen;
        }),
        lit: _frozen,
      ),
      SoftKey('Record Strip', Icons.print_outlined, _record, lit: _win == _Win.strip || sim.recording > 0),
      SoftKey('Mark Event', Icons.flag_outlined, () => _press(sim.markEvent)),
      SoftKey('Vitals Trend', Icons.table_rows_outlined, () => _open(_Win.trends), lit: _win == _Win.trends),
      SoftKey('Alarm Limits', Icons.tune, () => _open(_Win.limits), lit: _win == _Win.limits),
      SoftKey('12-Lead ECG', Icons.monitor_heart_outlined, () => _press(() => _twelve = !_twelve), lit: _twelve),
      SoftKey('Change Screen', Icons.dashboard_outlined, () => _open(_Win.screen), lit: _win == _Win.screen),
      SoftKey('Main Setup', Icons.settings_outlined, () => _open(_Win.setup), lit: _win == _Win.setup),
      SoftKey(
        'Standby',
        Icons.power_settings_new,
        () => _press(() {
          widget.sounds.stopAlarm();
          _win = _Win.none;
          _standby = true;
        }),
      ),
    ];
  }

  Widget? _window() {
    void close() => setState(() => _win = _Win.none);
    return switch (_win) {
      _Win.none => null,
      _Win.setup => MainSetupWindow(settings: st, onClose: close),
      _Win.limits => AlarmLimitsWindow(sim: sim, onClose: close, onChanged: () => setState(() {})),
      _Win.trends => TrendsWindow(sim: sim, settings: st, onClose: close),
      _Win.nibp => NibpWindow(sim: sim, onClose: close),
      _Win.ecg1 => EcgWindow(settings: st, second: false, onClose: close),
      _Win.ecg2 => EcgWindow(settings: st, second: true, onClose: close),
      _Win.screen => ScreenWindow(settings: st, onClose: close),
      _Win.strip => MonitorWindow(
        title: 'Recorder Strip',
        width: 760,
        onClose: close,
        child: RecorderStrip(source: _strip!, header: _stripHeader),
      ),
    };
  }

  // ----------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final s = math.min(h / 760, w / 1180).clamp(0.42, 2.4).toDouble();
        final barH = math.max(30 * s, 22.0);
        final infoH = math.max(21 * s, 15.0);
        final lampH = math.max(5 * s, 3.0);
        final keyH = math.max(62 * s, 42.0);
        final numW = (w * 0.27).clamp(140.0, 440 * s).toDouble();
        final trendW = (w * 0.085).clamp(60.0, 150 * s).toDouble();
        final win = _window();

        return Scale(
          s: s,
          child: Builder(
            builder: (context) {
              final big = st.layout == ScreenLayout.big && !_twelve;
              final bands = big ? const <_Band>[] : _bands();
              return ColoredBox(
                color: MC.bg,
                child: Stack(
                  children: [
                    Column(
                      children: [
                        AlarmLamp(sim: sim, blink: _blink, height: lampH),
                        StatusBar(
                          sim: sim,
                          settings: st,
                          blink: _blink,
                          now: sim.clock(),
                          onSecret: togglePanel,
                          height: barH,
                        ),
                        InfoLine(sim: sim, settings: st, height: infoH),
                        Expanded(
                          flex: 100,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (big)
                                _bigNumbers()
                              else
                                Row(
                                  children: [
                                    Expanded(child: _twelve ? _twelveLead() : _stack(bands, (b) => b.wave)),
                                    if (st.miniTrendsOn && !_twelve)
                                      SizedBox(width: trendW, child: _stack(bands, (b) => b.trend)),
                                    SizedBox(width: numW, child: _stack(bands, (b) => b.tile)),
                                  ],
                                ),
                              if (_frozen)
                                Align(
                                  alignment: Alignment.topCenter,
                                  child: Container(
                                    margin: EdgeInsets.only(top: 4 * s),
                                    padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 3 * s),
                                    color: MC.text,
                                    child: Text('WAVES FROZEN', style: labelStyle(13 * s, Colors.black, weight: 700)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (!big) ..._lowerRows(),
                        SoftKeyBar(keys: _keys(), height: keyH),
                      ],
                    ),
                    if (win != null) ...[
                      Positioned.fill(
                        bottom: keyH,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => setState(() => _win = _Win.none),
                        ),
                      ),
                      Positioned(
                        left: 8 * s,
                        bottom: keyH + 6 * s,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: h - keyH - barH - infoH - lampH - 16 * s,
                            maxWidth: w - 16 * s,
                          ),
                          child: win,
                        ),
                      ),
                    ],
                    if (_panel)
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: math.min(400.0, w * 0.64),
                        child: ControlPanel(sim: sim, settings: st, onClose: togglePanel),
                      ),
                    if (_standby) Positioned.fill(child: _standbyScreen(s)),
                    if (_boot) Positioned.fill(child: _bootScreen(s)),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _standbyScreen(double s) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _standby = false),
    child: ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.power_settings_new, size: 54 * s, color: MC.dim),
            SizedBox(height: 14 * s),
            Text('STANDBY', style: labelStyle(34 * s, MC.text, weight: 650)),
            SizedBox(height: 10 * s),
            Text('Monitoring and alarms are suspended', style: labelStyle(16 * s, MC.dim)),
            SizedBox(height: 4 * s),
            Text('Touch the screen to resume', style: labelStyle(16 * s, MC.dim)),
          ],
        ),
      ),
    ),
  );

  Widget _bootScreen(double s) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _boot = false),
    child: ColoredBox(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 620 * s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.monitor_heart_outlined, size: 60 * s, color: MC.ecg),
              SizedBox(height: 10 * s),
              Text('PATIENT MONITOR SIMULATOR', style: labelStyle(26 * s, MC.text, weight: 650)),
              SizedBox(height: 6 * s),
              Text('Self-test complete', style: labelStyle(15 * s, MC.dim)),
              SizedBox(height: 22 * s),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 10 * s),
                decoration: BoxDecoration(border: Border.all(color: MC.alarmYellow)),
                child: Column(
                  children: [
                    Text(
                      'SIMULATION ONLY - NOT A MEDICAL DEVICE',
                      textAlign: TextAlign.center,
                      style: labelStyle(17 * s, MC.alarmYellow, weight: 700),
                    ),
                    SizedBox(height: 6 * s),
                    Text(
                      'Every waveform and number on this screen is generated by software for entertainment. '
                      'It measures nothing and must never be used to assess or treat a person.',
                      textAlign: TextAlign.center,
                      style: labelStyle(14 * s, MC.text),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 18 * s),
              Text('Touch to continue', style: labelStyle(14 * s, MC.dim)),
            ],
          ),
        ),
      ),
    ),
  );
}
