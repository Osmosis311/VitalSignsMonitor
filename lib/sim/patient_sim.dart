import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'alarms.dart';
import 'ecg_engine.dart';
import 'ecg_shapes.dart';
import 'rhythms.dart';
import 'scenarios.dart';
import 'wave_buffer.dart';

/// A value that moves toward its target at a steady pace instead of jumping.
class Slew {
  Slew(this.cur) : target = cur;
  double cur;
  double target;
  double _rate = 0;

  void set(double v, [double over = 0]) {
    target = v;
    if (over <= 0) {
      cur = v;
    } else {
      _rate = (v - cur).abs() / over;
    }
  }

  void step(double dt) {
    if (cur == target) return;
    final d = target - cur;
    final m = _rate * dt;
    cur = d.abs() <= m ? target : cur + m * d.sign;
  }
}

enum VentMode { spontaneous, assisted, none }

enum NibpPhase { idle, inflating, deflating }

class TrendRow {
  TrendRow(this.time, this.hr, this.spo2, this.rr, this.etco2, this.temp, {this.nibp});
  final DateTime time;
  final int? hr, spo2, rr, etco2;
  final double temp;
  final String? nibp;
}

/// One line of the alarm and event history.
class LogEvent {
  LogEvent(this.time, this.text, this.priority);
  final DateTime time;
  final String text;

  /// Null for things that are not alarms (a marked event, a recording).
  final AlarmPriority? priority;
}

/// A drug or fluid running on a pump beside the bed.
class Infusion {
  Infusion(this.name, this.dose, this.rate, this.remaining);
  final String name;

  /// Dose as the pump shows it, e.g. `0.06 mcg/kg/min`.
  final String dose;

  /// mL per hour.
  final double rate;

  /// mL left to give.
  double remaining;
}

class _Pulse {
  _Pulse(this.t0, this.amp, this.tej);
  final double t0, amp, tej;
  bool counted = false;
}

/// Derived ECG lead read straight out of the engine's base-lead buffers.
class LeadSource implements WaveSource {
  LeadSource(this._e, this.lead);
  final EcgEngine _e;
  final Lead lead;

  @override
  double get fs => EcgEngine.fs;
  @override
  double get tLast => _e.leads[0].tLast;
  @override
  int get length => _e.leads[0].length;

  @override
  double back(int i) {
    final l = _e.leads;
    switch (lead) {
      case Lead.i:
        return l[0].back(i);
      case Lead.ii:
        return l[1].back(i);
      case Lead.iii:
        return l[1].back(i) - l[0].back(i);
      case Lead.avr:
        return -(l[0].back(i) + l[1].back(i)) / 2;
      case Lead.avl:
        return l[0].back(i) - l[1].back(i) / 2;
      case Lead.avf:
        return l[1].back(i) - l[0].back(i) / 2;
      case Lead.v1:
        return l[2].back(i);
      case Lead.v2:
        return l[3].back(i);
      case Lead.v3:
        return l[4].back(i);
      case Lead.v4:
        return l[5].back(i);
      case Lead.v5:
        return l[6].back(i);
      case Lead.v6:
        return l[7].back(i);
    }
  }
}

/// The simulated patient and the measurements a monitor would take from them.
///
/// Everything on screen comes from here: the rhythm generator makes beats, the
/// beats make pulses, the pulses make the pleth and arterial traces, and the
/// numbers are measured back off those traces the way a real monitor does.
/// That is why a PVC shows up as a weak pulse and why HR and pulse rate can
/// disagree.
class PatientSim extends ChangeNotifier {
  PatientSim({int? seed, DateTime Function()? clock}) : rng = math.Random(seed), clock = clock ?? DateTime.now {
    ecg = EcgEngine(rng);
    rhythm = kRhythms.first;
    ecg.setGenerator(rhythm.build(ecg), delay: 0.3);
    _seedTrends();
    _seedHistory();
    _nextAuto = 4;
  }

  final math.Random rng;
  final DateTime Function() clock;
  late final EcgEngine ecg;

  static const double _h = EcgEngine.dt;

  /// Simulation clock, seconds.
  double t = 0;
  double _acc = 0;

  // -------------------------------------------------------------- inputs --

  late RhythmDef rhythm;
  double _rhythmSince = 0;
  final Slew rate = Slew(72);
  final Slew spo2 = Slew(98);
  final Slew sys = Slew(122);
  final Slew dia = Slew(78);
  final Slew respRate = Slew(14);
  final Slew etco2 = Slew(38);
  final Slew temp = Slew(36.8);
  final Slew obstruction = Slew(0);
  final Slew cvp = Slew(8);
  final Slew paSys = Slew(25);
  final Slew paDia = Slew(10);
  final Slew icp = Slew(10);

  /// Depth-of-sedation index the EEG is generated for: ~95 awake, 40-60
  /// under anaesthesia, near 0 with no brain activity.
  final Slew bis = Slew(96);

  /// Neuromuscular block, 0 (none) to 1 (complete).
  final Slew nmt = Slew(0);

  VentMode vent = VentMode.spontaneous;
  bool forcePulseless = false;
  bool probeOff = false;
  bool get cpr => ecg.cpr;
  bool get leadsOff => ecg.leadsOff;

  /// Which optional measurements are connected; alarms follow these.
  bool abpOn = true;
  bool co2On = true;
  bool papOn = true;
  bool cvpOn = true;
  bool icpOn = true;

  final Map<LimitKey, Limit> limits = defaultLimits();

  // ------------------------------------------------------------- outputs --

  final WaveBuffer pleth = WaveBuffer(EcgEngine.fs, 40);
  final WaveBuffer abp = WaveBuffer(EcgEngine.fs, 40);
  final WaveBuffer co2 = WaveBuffer(50, 90);
  final WaveBuffer resp = WaveBuffer(50, 90);

  final WaveBuffer pap = WaveBuffer(EcgEngine.fs, 40);
  final WaveBuffer cvpWave = WaveBuffer(EcgEngine.fs, 40);
  final WaveBuffer icpWave = WaveBuffer(EcgEngine.fs, 40);

  /// Single-channel EEG in microvolts.
  final WaveBuffer eeg = WaveBuffer(EcgEngine.fs, 40);

  WaveSource lead(Lead l) => LeadSource(ecg, l);

  /// Bumps on every detected QRS.
  final ValueNotifier<int> beatTick = ValueNotifier(0);

  /// Called on every detected QRS so the app can sound the pulse tone.
  void Function(Beat beat)? onBeat;

  int? hr;
  int pvcPerMin = 0;
  bool pacing = false;
  int? spo2Value;
  int? pulse;
  double perf = 0;
  int? abpS, abpD, abpM;
  int? etco2Value;
  int? awrr;
  double tempValue = 36.8;
  double temp2Value = 34.4;
  int? papS, papD, papM;
  int? cvpValue;
  int? icpValue;
  int? cpp;
  int? bisValue;
  int sqi = 95, emg = 40, suppression = 0;

  /// Continuous cardiac output estimated from the arterial pulse.
  double? cardiacOutput, cardiacIndex;
  int? strokeVolume, svr, svv;
  int? qt, qtc;

  /// ST deviation in mm for all twelve leads, in [Lead] order.
  List<double?> stAll = List.filled(12, null);

  /// Train-of-four twitch heights (0..1), refreshed every stimulation.
  List<double> tof = const [1, 1, 1, 1];
  final ValueNotifier<int> tofTick = ValueNotifier(0);

  /// Body surface area used for indexed values, m².
  double bsa = 2.0;

  final List<LogEvent> events = [];
  final List<Infusion> infusions = [
    Infusion('Norepinephrine', '0.06 mcg/kg/min', 5.5, 212),
    Infusion('Fentanyl', '50 mcg/h', 5.0, 38),
    Infusion('NaCl 0.9%', '75 mL/h', 75, 640),
  ];

  /// Sampled every [historyStep] seconds; newest last.
  final Map<String, List<double?>> history = {};
  static const double historyStep = 10;
  static const int historyLength = 360;

  /// Seconds of strip currently being "printed", counting down.
  double recording = 0;
  double? timerStart;
  double timerHeld = 0;

  NibpPhase nibpPhase = NibpPhase.idle;
  double cuff = 0;
  int? nibpS, nibpD, nibpM;
  DateTime? nibpTime;
  bool nibpFailed = false;

  /// Minutes between automatic cuff readings; 0 = manual only.
  int nibpAuto = 5;
  double _nextAuto = 0;
  double _cuffTarget = 160;
  double _deflateHold = 0;

  final List<Alarm> alarms = [];
  double _pausedUntil = -1;
  final List<TrendRow> trends = [];

  Scenario? scenario;
  double _scT0 = 0;
  int _scIdx = 0;
  String scenarioNote = '';

  // ------------------------------------------------------------ internals --

  final List<Beat> _beats = [];
  final List<double> _pvcTimes = [];
  int _ventRun = 0;
  double _lastPaced = -100;
  double _hrDrift = 0;

  final List<_Pulse> _pulses = [];
  final List<_Pulse> _plPulses = [];
  double _abp = 80, _abpW = 80, _abpF = 0;
  double _p0 = 30;
  double _pl = 0, _plW = 0, _plF = 0;
  double _plLo = 0, _plHi = 0.6;
  final List<double> _pulseTimes = [];
  double _lastPulse = -100;
  double _beatMax = 0, _beatSum = 0;
  int _beatN = 0;
  final List<List<double>> _abpBeats = [];
  double _meanRR = 0.83;
  double _kPP = 1.75, _kTau = 0.94, _lastAmp = 0;
  double _perfusion = 1;
  double _pulselessSince = -1;
  double _cprPhase = 0;
  double _spo2Noise = 0;

  double _respPhase = 0;
  double _breathPeriod = 60 / 14;
  double _breathDepth = 1;
  double _breathEt = 38;
  double _lastEt = 0;
  double _co2Now = 0;
  double _breathPeak = 0;
  bool _breathing = true;
  final List<double> _breathStarts = [0];
  int _slow = 0;

  double _respVol = 0;
  final List<_Pulse> _icpPulses = [];
  double _cvpShift = 0;
  double _abpSlow = 90, _paMean = 15;
  double _brain = 1;
  double _eegD = 0, _eegB = 0, _eegA = 0, _eegAmp = 1, _eegBurst = 0;
  bool _eegQuiet = false;
  double _quietTime = 0, _eegTime = 0;
  double _lastTof = 0;
  double _lastHistory = 0;
  final List<double> _stNoise = List.filled(12, 0);
  double _lastNumerics = 0;
  double _lastAlarmEval = 0;
  double _lastTrend = 0;
  double _postShockAt = -1;
  String? _postShockRhythm;
  int _postShockRate = 0;

  // ------------------------------------------------------------- controls --

  void setRhythm(String id, {int? bpm, double delay = 0.55}) {
    final def = rhythmById(id);
    rhythm = def;
    _rhythmSince = t;
    rate.set((bpm ?? def.rate).toDouble());
    ecg.rate = rate.cur;
    ecg.setGenerator(def.build(ecg), delay: delay);
    _postShockAt = -1;
    notifyListeners();
  }

  void setRate(double bpm, {double over = 2}) {
    if (rhythm.fixedRate) return;
    rate.set(bpm.clamp(rhythm.minRate, rhythm.maxRate).toDouble(), over);
  }

  void setBp(double s, double d, {double over = 6}) {
    sys.set(s, over);
    dia.set(math.min(d, s - 8), over);
  }

  void setCpr(bool on) {
    ecg.cpr = on;
    notifyListeners();
  }

  void setLeadsOff(bool off) {
    ecg.leadsOff = off;
    notifyListeners();
  }

  void setProbeOff(bool off) {
    probeOff = off;
    notifyListeners();
  }

  void setVent(VentMode m) {
    vent = m;
    notifyListeners();
  }

  void setForcePulseless(bool v) {
    forcePulseless = v;
    notifyListeners();
  }

  void injectPvcs(int n) => ecg.pvcQueue = n;

  void motionArtifact([double seconds = 5]) => ecg.artifactUntil = t + seconds;

  /// Defibrillation. A shockable rhythm converts to [then] (sinus by
  /// default); anything else carries on once the artifact settles.
  void shock({String? then, int rate = 96}) {
    ecg.shock();
    ecg.setGenerator(ChaoticGen(ecg, Chaos.asystole), delay: 0);
    _postShockAt = t + 2.4;
    _postShockRhythm = then ?? (rhythm.shockable ? 'nsr' : rhythm.id);
    _postShockRate = then == null && !rhythm.shockable ? this.rate.cur.round() : rate;
    _beats.clear();
  }

  void startNibp() {
    if (nibpPhase != NibpPhase.idle) return;
    nibpPhase = NibpPhase.inflating;
    nibpFailed = false;
    cuff = 0;
    _cuffTarget = ((nibpS ?? 125) + 42).clamp(150, 240).toDouble();
    if (nibpAuto > 0) _nextAuto = t + nibpAuto * 60;
    notifyListeners();
  }

  void stopNibp() {
    if (nibpPhase == NibpPhase.idle) return;
    nibpPhase = NibpPhase.idle;
    cuff = 0;
    notifyListeners();
  }

  void setNibpAuto(int minutes) {
    nibpAuto = minutes;
    _nextAuto = minutes > 0 ? t + minutes * 60 : double.infinity;
    notifyListeners();
  }

  /// Seconds until the next automatic cuff reading, if one is due.
  int? get nibpCountdown => nibpAuto > 0 && nibpPhase == NibpPhase.idle ? math.max(0, (_nextAuto - t).round()) : null;

  void runScenario(Scenario s) {
    scenario = s;
    _scT0 = t;
    _scIdx = 0;
    scenarioNote = '';
    notifyListeners();
  }

  void stopScenario() {
    scenario = null;
    scenarioNote = '';
    notifyListeners();
  }

  double get scenarioElapsed => scenario == null ? 0 : t - _scT0;

  /// Back to a healthy resting adult.
  void reset() {
    scenario = null;
    scenarioNote = '';
    forcePulseless = false;
    probeOff = false;
    ecg.cpr = false;
    ecg.leadsOff = false;
    vent = VentMode.spontaneous;
    spo2.set(98, 4);
    setBp(122, 78, over: 4);
    respRate.set(14, 4);
    etco2.set(38, 4);
    temp.set(36.8, 4);
    obstruction.set(0, 2);
    cvp.set(8, 4);
    paSys.set(25, 4);
    paDia.set(10, 4);
    icp.set(10, 4);
    bis.set(96, 4);
    nmt.set(0, 4);
    setRhythm('nsr');
  }

  // --------------------------------------------------------------- alarms --

  bool get alarmsPaused => t < _pausedUntil;
  int get pauseRemaining => math.max(0, (_pausedUntil - t).ceil());

  void pauseAlarms([double seconds = 120]) {
    _pausedUntil = t + seconds;
    notifyListeners();
  }

  void resumeAlarms() {
    _pausedUntil = -1;
    notifyListeners();
  }

  /// Acknowledge everything currently sounding.
  void silence() {
    for (final a in alarms) {
      a.acked = true;
    }
    notifyListeners();
  }

  Alarm? topAlarm(AlarmPriority p) {
    for (final a in alarms) {
      if (a.priority == p) return a;
    }
    return null;
  }

  /// Highest priority that still needs a tone, if any.
  AlarmPriority? get soundingPriority {
    if (alarmsPaused) return null;
    AlarmPriority? best;
    for (final a in alarms) {
      if (a.acked) continue;
      if (best == null || a.priority.index < best.index) best = a.priority;
    }
    return best;
  }

  Alarm? alarmFor(Param p) {
    if (alarmsPaused) return null;
    Alarm? best;
    for (final a in alarms) {
      if (a.param != p) continue;
      if (best == null || a.priority.index < best.priority.index) best = a;
    }
    return best;
  }

  void _raise(Set<String> seen, String text, AlarmPriority p, Param param, {double? hold}) {
    seen.add(text);
    for (final a in alarms) {
      if (a.id == text) {
        if (hold != null) a.until = t + hold;
        return;
      }
    }
    final a = Alarm(text, text, p, param, t);
    if (hold != null) a.until = t + hold;
    alarms.add(a);
    _log(a.marked, p);
  }

  void _log(String text, AlarmPriority? p) {
    events.add(LogEvent(clock(), text, p));
    if (events.length > 120) events.removeAt(0);
  }

  /// Operator pressed Mark Event.
  void markEvent() {
    _log('Event marked', null);
    notifyListeners();
  }

  /// Starts a recorder strip; purely cosmetic apart from the log entry.
  void recordStrip([double seconds = 10]) {
    recording = seconds;
    _log('Strip recorded', null);
    notifyListeners();
  }

  /// Stopwatch on the status row: start, stop, and reset when stopped twice.
  void toggleTimer() {
    if (timerStart != null) {
      timerHeld += t - timerStart!;
      timerStart = null;
    } else {
      timerStart = t;
    }
    notifyListeners();
  }

  void resetTimer() {
    timerStart = null;
    timerHeld = 0;
    notifyListeners();
  }

  double get timerSeconds => timerHeld + (timerStart == null ? 0 : t - timerStart!);

  void _transient(String text, Param param, [double hold = 8]) {
    for (final a in alarms) {
      if (a.id == text) {
        a.until = t + hold;
        return;
      }
    }
    final a = Alarm(text, text, AlarmPriority.medium, param, t)..until = t + hold;
    alarms.add(a);
    _log(a.marked, a.priority);
  }

  void _evalAlarms() {
    final seen = <String>{};
    const hi = AlarmPriority.high, med = AlarmPriority.medium, tech = AlarmPriority.technical;
    final since = t - _rhythmSince;

    if (ecg.leadsOff) {
      _raise(seen, 'ECG LEADS OFF', tech, Param.hr);
    } else {
      final lim = limits[LimitKey.hr]!;
      final h = hr;
      var lethal = false;
      if (rhythm.alarm != null && rhythm.alarmPriority == hi && since > rhythm.alarmDelay && _postShockAt < 0) {
        _raise(seen, rhythm.alarm!, hi, Param.hr);
        lethal = true;
      } else if (h == 0 && t > 5) {
        _raise(seen, 'ASYSTOLE', hi, Param.hr);
        lethal = true;
      }
      if (!lethal && h != null) {
        if (h > math.max(lim.hi + 40, 180)) {
          _raise(seen, 'EXTREME TACHY', hi, Param.hr);
        } else if (h < math.min(lim.lo - 12, 35)) {
          _raise(seen, 'EXTREME BRADY', hi, Param.hr);
        } else if (h > lim.hi) {
          _raise(seen, 'HR HIGH', med, Param.hr);
        } else if (h < lim.lo) {
          _raise(seen, 'HR LOW', med, Param.hr);
        }
        if (rhythm.alarm != null && rhythm.alarmPriority == med && since > rhythm.alarmDelay) {
          _raise(seen, rhythm.alarm!, med, Param.hr);
        }
        if (pvcPerMin > 10) _raise(seen, 'PVCs/min HIGH', med, Param.hr);
      }
    }

    if (probeOff) {
      _raise(seen, 'SpO₂ SENSOR OFF', tech, Param.spo2);
    } else if (spo2Value == null) {
      if (t > 6) _raise(seen, 'SpO₂ NO PULSE', tech, Param.spo2);
    } else {
      final lim = limits[LimitKey.spo2]!;
      if (spo2Value! < math.min(lim.lo - 5, 80)) {
        _raise(seen, 'DESAT', hi, Param.spo2);
      } else if (spo2Value! < lim.lo) {
        _raise(seen, 'SpO₂ LOW', med, Param.spo2);
      }
    }

    if (abpOn && abpS != null && t > 6) {
      final lim = limits[LimitKey.abpSys]!;
      if (abpS! < lim.lo) {
        _raise(seen, 'ABPs LOW', med, Param.abp);
      } else if (abpS! > lim.hi) {
        _raise(seen, 'ABPs HIGH', med, Param.abp);
      }
    }

    if (papOn && papS != null && t > 6) {
      final lim = limits[LimitKey.papSys]!;
      if (papS! > lim.hi) _raise(seen, 'PAPs HIGH', med, Param.pap);
    }
    if (cvpOn && cvpValue != null && t > 6) {
      final lim = limits[LimitKey.cvp]!;
      if (cvpValue! > lim.hi) {
        _raise(seen, 'CVP HIGH', med, Param.cvp);
      } else if (cvpValue! < lim.lo) {
        _raise(seen, 'CVP LOW', med, Param.cvp);
      }
    }
    if (icpOn && icpValue != null && t > 6) {
      if (icpValue! > limits[LimitKey.icp]!.hi) {
        _raise(seen, 'ICP HIGH', med, Param.icp);
      } else if (cpp != null && cpp! < limits[LimitKey.cpp]!.lo) {
        _raise(seen, 'CPP LOW', med, Param.icp);
      }
    }

    if (nibpFailed) {
      _raise(seen, 'NIBP MEASURE FAILED', tech, Param.nibp);
    } else if (nibpS != null) {
      final lim = limits[LimitKey.nibpSys]!;
      if (nibpS! < lim.lo) {
        _raise(seen, 'NIBPs LOW', med, Param.nibp);
      } else if (nibpS! > lim.hi) {
        _raise(seen, 'NIBPs HIGH', med, Param.nibp);
      }
    }

    if (co2On && t > 8) {
      final sinceBreath = t - _breathStarts.last;
      if (sinceBreath > 20) {
        _raise(seen, 'APNEA', hi, Param.co2);
      } else {
        final le = limits[LimitKey.etco2]!;
        final lr = limits[LimitKey.awrr]!;
        final e = etco2Value, r = awrr;
        if (e != null && e > le.hi) {
          _raise(seen, 'etCO₂ HIGH', med, Param.co2);
        } else if (e != null && e < le.lo) {
          _raise(seen, 'etCO₂ LOW', med, Param.co2);
        }
        if (r != null && r > lr.hi) {
          _raise(seen, 'awRR HIGH', med, Param.co2);
        } else if (r != null && r < lr.lo) {
          _raise(seen, 'awRR LOW', med, Param.co2);
        }
      }
    }

    final lt = limits[LimitKey.temp]!;
    if (tempValue > lt.hi) {
      _raise(seen, 'TEMP HIGH', med, Param.temp);
    } else if (tempValue < lt.lo) {
      _raise(seen, 'TEMP LOW', med, Param.temp);
    }

    alarms.removeWhere((a) => a.until != null ? t > a.until! : !seen.contains(a.id));
    alarms.sort((a, b) {
      final p = a.priority.index.compareTo(b.priority.index);
      return p != 0 ? p : b.since.compareTo(a.since);
    });
  }

  // ---------------------------------------------------------------- clock --

  /// Advances the simulation by [dt] seconds of real time.
  void advance(double dt) {
    _acc += math.min(dt, 0.25);
    while (_acc >= _h) {
      _acc -= _h;
      _step();
    }
  }

  bool get _pulselessRhythm => rhythm.pulseless || forcePulseless;

  void _step() {
    t += _h;
    rate.step(_h);
    spo2.step(_h);
    sys.step(_h);
    dia.step(_h);
    respRate.step(_h);
    etco2.step(_h);
    temp.step(_h);
    obstruction.step(_h);
    cvp.step(_h);
    paSys.step(_h);
    paDia.step(_h);
    icp.step(_h);
    bis.step(_h);
    nmt.step(_h);

    final sc = scenario;
    if (sc != null) {
      while (_scIdx < sc.steps.length && t - _scT0 >= sc.steps[_scIdx].at) {
        final s = sc.steps[_scIdx++];
        scenarioNote = s.note;
        s.run(this);
      }
    }

    if (_postShockAt > 0 && t >= _postShockAt) {
      final id = _postShockRhythm!;
      _postShockAt = -1;
      setRhythm(id, bpm: _postShockRate, delay: 0.2);
      if (id == 'nsr') rate.set(82, 25);
    }

    _hrDrift += (-_hrDrift / 20) * _h + 0.006 * math.sqrt(_h) * ecg.gauss();
    ecg.rate = rate.cur * (1 + _hrDrift);

    _stepBreathing();
    ecg.respPhase = _respPhase;
    ecg.respHz = 1 / _breathPeriod;
    ecg.breathing = _breathing;
    ecg.step(t);

    final pend = ecg.pending;
    for (var i = 0; i < pend.length;) {
      if (pend[i].t <= t) {
        _onBeat(pend.removeAt(i));
      } else {
        i++;
      }
    }
    final notes = ecg.notes;
    for (var i = 0; i < notes.length;) {
      if (notes[i].t <= t) {
        final n = notes.removeAt(i);
        if (n.code == 'missed') _transient('MISSED BEAT', Param.hr);
        if (n.code == 'nocapture') _transient('PACER NOT CAPTURING', Param.hr, 12);
      } else {
        i++;
      }
    }

    _stepCpr();
    _stepPressure();
    _stepExtra();
    _stepNibp();

    if (t - _lastNumerics >= 1) {
      _lastNumerics = t;
      _updateNumerics();
    }
    if (t - _lastAlarmEval >= 0.5) {
      _lastAlarmEval = t;
      _evalAlarms();
      notifyListeners();
    }
    if (t - _lastTrend >= 60) {
      _lastTrend = t;
      _addTrend();
    }
    if (t - _lastHistory >= historyStep) {
      _lastHistory = t;
      _addHistory();
    }
  }

  // ---------------------------------------------------------------- beats --

  void _onBeat(Beat b) {
    final prev = _beats.isEmpty ? null : _beats.last;
    _beats.add(b);
    if (_beats.length > 24) _beats.removeAt(0);
    beatTick.value++;
    onBeat?.call(b);

    if (b.kind == BeatKind.paced) _lastPaced = t;
    if (b.kind == BeatKind.ventricular) {
      _ventRun++;
      if (_ventRun <= 8) {
        _pvcTimes.add(t);
      } else {
        // Sustained: this is a rhythm now, not ectopy.
        _pvcTimes.clear();
      }
    } else {
      if (_ventRun == 2) _transient('PAIR PVCs', Param.hr);
      if (_ventRun >= 3 && rhythm.alarmPriority != AlarmPriority.high) _transient('RUN PVCs', Param.hr, 10);
      _ventRun = 0;
    }
    if (prev != null && b.t - prev.t > 2.2 && (hr ?? 0) > 38) _transient('PAUSE', Param.hr);

    final s = _pulselessRhythm ? 0.0 : b.strength;
    if (s > 0.03) {
      final tej = 0.2 * math.sqrt(b.rr.clamp(0.3, 1.3));
      _pulses.add(_Pulse(b.t + 0.15, s, tej));
      _plPulses.add(_Pulse(b.t + 0.27, s, tej * 1.2));
      _icpPulses.add(_Pulse(b.t + 0.12, s, math.sqrt(b.rr.clamp(0.3, 1.3))));
    }
  }

  void _stepCpr() {
    if (!ecg.cpr) return;
    _cprPhase += 1.83 * _h;
    if (_cprPhase >= 1) {
      _cprPhase -= 1;
      final s = 0.36 + 0.12 * rng.nextDouble();
      _icpPulses.add(_Pulse(t, s * 0.6, 0.7));
      _pulses.add(_Pulse(t, s, 0.15));
      _plPulses.add(_Pulse(t + 0.1, s * 0.7, 0.18));
    }
  }

  // ------------------------------------------------------------- pressure --

  /// Flow into the arterial tree across one beat: the ejection, then the
  /// smaller reflected wave that leaves the dicrotic notch between them.
  static double _inflow(double x) {
    if (x < 0) return 0;
    if (x < 1) {
      final s = math.sin(math.pi * math.pow(x, 0.75));
      return s * s;
    }
    if (x > 1.55 && x < 2.7) {
      final s = math.sin(math.pi * (x - 1.55) / 1.15);
      return 0.2 * s * s;
    }
    return 0;
  }

  double _drive(List<_Pulse> list) {
    var q = 0.0;
    for (var i = 0; i < list.length;) {
      final p = list[i];
      final x = (t - p.t0) / p.tej;
      if (x > 2.75) {
        list.removeAt(i);
        continue;
      }
      if (x >= 0) q += p.amp * _inflow(x) / (p.tej * 0.5);
      i++;
    }
    return q;
  }

  void _stepPressure() {
    final s = sys.cur, d = math.min(dia.cur, sys.cur - 6);
    final output = t - _lastPulse < 2.6 && !ecg.cpr;

    // Arterial pressure. Each beat pushes a slug of blood into a compliant
    // reservoir that drains between beats (the slow part), on top of a brief
    // surge that makes the sharp systolic peak (the fast part).
    final p0Target = output ? 10 + 0.24 * d : 14.0;
    _p0 += (p0Target - _p0) * _h / 6;
    final ratio = math.max(1.05, (s - _p0) / math.max(d - _p0, 4));
    final tau = (_kTau * _meanRR / math.log(ratio)).clamp(0.25, 5.0);
    final pp = (s - d) * _kPP;
    for (final p in _pulses) {
      if (!p.counted && t >= p.t0) {
        p.counted = true;
        final now = _abpW + _abpF;
        if (_beatN > 0) {
          _abpBeats.add([_beatMax, now, _beatSum / _beatN]);
          if (_abpBeats.length > 6) _abpBeats.removeAt(0);
          // Trim the model against what was just measured, on clean beats
          // only, so the numbers settle on the values that were asked for.
          final gap = t - _lastPulse;
          if (_lastAmp >= 0.95 && p.amp >= 0.95 && (gap - _meanRR).abs() < 0.1 * _meanRR) {
            final ppT = math.max(s - d, 6), ppM = _beatMax - now;
            _kPP = (_kPP * (1 + 0.2 * (ppT - ppM) / ppT)).clamp(0.6, 3.2).toDouble();
            _kTau = (_kTau * (1 + 0.2 * (d - now) / math.max(d - _p0, 8))).clamp(0.25, 2.5).toDouble();
          }
        }
        _lastAmp = p.amp;
        _beatMax = now;
        _beatSum = 0;
        _beatN = 0;
        if (p.amp > 0.2) {
          if (_lastPulse > 0 && t - _lastPulse < 3 && !ecg.cpr) {
            _meanRR += ((t - _lastPulse) - _meanRR) * 0.25;
          }
          _pulseTimes.add(t);
          if (_pulseTimes.length > 12) _pulseTimes.removeAt(0);
          _lastPulse = t;
        }
      }
    }
    final q = _drive(_pulses);
    _abpW += (-(_abpW - _p0) / tau + q * pp * 0.45) * _h;
    _abpF += (-_abpF / 0.06 + q * pp * 0.55) * _h;
    _abp = _abpW + _abpF;
    if (_abp > _beatMax) _beatMax = _abp;
    _beatSum += _abp;
    _beatN++;
    abp.add(_abp + 0.2 * ecg.gauss(), t);

    // Pleth: the same pulse seen at the fingertip, rounder and auto-gained.
    final qp = _drive(_plPulses);
    final tp = 0.36 * math.sqrt(_meanRR.clamp(0.3, 1.3));
    _plW += (-_plW / tp + qp * 0.64) * _h;
    _plF += (-_plF / 0.12 + qp * 0.36) * _h;
    _pl = _plW + _plF;
    final target = _pl;
    _plHi += (target > _plHi ? (target - _plHi) * 0.2 : (target - _plHi) * _h / 2.5);
    _plLo += (target < _plLo ? (target - _plLo) * 0.2 : (target - _plLo) * _h / 2.5);
    final span = math.max(_plHi - _plLo, 0.3);
    var y = 0.1 + (_pl - _plLo) / span * 0.72;
    if (probeOff) y = 0.08;
    y += 0.02 * (_breathing ? math.sin(2 * math.pi * _respPhase) : 0) + 0.003 * ecg.gauss();
    pleth.add(y.clamp(0.0, 1.0).toDouble(), t);

    // How much blood is actually moving, for the capnogram.
    final perfTarget = output ? 1.0 : (ecg.cpr ? 0.42 : 0.1);
    _perfusion += (perfTarget - _perfusion) * _h / 5;
    if (output) {
      _pulselessSince = -1;
    } else if (_pulselessSince < 0) {
      _pulselessSince = t;
    }
  }

  // ------------------------------------------------------------ breathing --

  void _stepBreathing() {
    final wants =
        vent == VentMode.assisted ||
        (vent == VentMode.spontaneous && (_pulselessSince < 0 || t - _pulselessSince < 7) && respRate.cur >= 1);
    if (_breathing) {
      _respPhase += _h / _breathPeriod;
      if (_respPhase >= 1) {
        _respPhase -= 1;
        _lastEt = _co2Now;
        etco2Peak = _breathPeak;
        _breathPeak = 0;
        if (wants) {
          _newBreath();
        } else {
          _breathing = false;
          _respPhase = 0;
        }
      }
    } else if (wants) {
      _breathing = true;
      _respPhase = 0;
      _newBreath();
    }

    _slow++;
    if (_slow < 5) return;
    _slow = 0;

    final obs = obstruction.cur;
    final fi = 0.38 - 0.1 * obs;
    double c, v;
    if (!_breathing) {
      _lastEt *= 0.72;
      c = _lastEt;
      v = 0;
    } else if (_respPhase < fi) {
      c = _lastEt * math.exp(-(_respPhase * _breathPeriod) / 0.05);
      v = 0.5 * (1 - math.cos(math.pi * _respPhase / fi));
    } else {
      final te = (_respPhase - fi) * _breathPeriod;
      final span = math.max(0.25, (1 - fi) * _breathPeriod - 0.1);
      final x = ((te - 0.1) / span).clamp(0.0, 1.0);
      final k = 0.045 + 0.5 * obs;
      c = te < 0.1 ? 0 : _breathEt * (1 - math.exp(-x / k)) / (1 - math.exp(-1 / k)) * (0.93 + 0.07 * x);
      final xe = (_respPhase - fi) / (1 - fi);
      v = (math.exp(-3.4 * xe) - math.exp(-3.4)) / (1 - math.exp(-3.4));
    }
    _respVol = v;
    _co2Now = c;
    if (c > _breathPeak) _breathPeak = c;
    co2.add(c + 0.12 * ecg.gauss(), t);
    final cardiac = 0.02 * (_pl.clamp(0, 1) - 0.3);
    resp.add((v * _breathDepth + cardiac + 0.004 * ecg.gauss()).toDouble(), t);
  }

  /// Highest CO₂ seen in the last completed breath.
  double etco2Peak = 0;

  void _newBreath() {
    final rr = respRate.cur.clamp(2, 60);
    _breathPeriod = 60 / rr * (1 + 0.05 * ecg.gauss()).clamp(0.8, 1.25);
    _breathDepth = (1 + 0.09 * ecg.gauss()).clamp(0.7, 1.3).toDouble();
    _breathEt = math.max(2, etco2.cur * (0.14 + 0.86 * _perfusion) + 0.7 * ecg.gauss());
    _breathStarts.add(t);
    if (_breathStarts.length > 6) _breathStarts.removeAt(0);
  }

  // ------------------------------------------------------- other pressures --

  static double _bump(double x, double c, double w) {
    final d = (x - c) / w;
    return d.abs() > 4 ? 0 : math.exp(-0.5 * d * d);
  }

  void _stepExtra() {
    final output = t - _lastPulse < 2.6 && !ecg.cpr;
    final insp = _breathing ? _respVol : 0.0;

    // Pulmonary artery: the pulsatile part of the same ejection, scaled to
    // the low-pressure circuit. Without output it settles to a flat line.
    final s = sys.cur, d = math.min(dia.cur, sys.cur - 6);
    final ps = paSys.cur, pd = math.min(paDia.cur, paSys.cur - 3);
    _abpSlow += (_abp - _abpSlow) * _h / 1.5;
    _paMean += ((output || ecg.cpr ? pd + (ps - pd) / 3 : 12.0) - _paMean) * _h / 5;
    final swing = ((_abp - _abpSlow) * (ps - pd) / (s - d)).clamp(-(ps - pd), 1.4 * (ps - pd));
    pap.add(math.max(1, _paMean + swing - 2.2 * insp) + 0.12 * ecg.gauss(), t);

    // Central venous pressure: a, c and v waves around each beat, falling
    // a little with every breath in. With no output it climbs and flattens.
    _cvpShift += ((output ? 0 : 7) - _cvpShift) * _h / 8;
    var cv = cvp.cur + _cvpShift - 1.6 * insp;
    void wave(Beat b) {
      final x = t - b.t;
      if (x < -0.4 || x > 1.2) return;
      final k = math.sqrt(b.rr.clamp(0.3, 1.3));
      final g = output ? 1.0 : 0.35;
      if (b.kind == BeatKind.normal || b.kind == BeatKind.atrial) cv += 2.6 * g * _bump(x, -0.09, 0.04);
      cv += g * (1.2 * _bump(x, 0.07, 0.03) - 1.8 * _bump(x, 0.2 * k, 0.06) + 2.2 * _bump(x, 0.4 * k, 0.07));
    }

    for (var i = math.max(0, _beats.length - 3); i < _beats.length; i++) {
      wave(_beats[i]);
    }
    for (final b in ecg.pending) {
      wave(b);
    }
    cvpWave.add(cv + 0.08 * ecg.gauss(), t);

    // Intracranial pressure: three peaks per pulse. As the pressure rises
    // the brain stiffens and the second peak overtakes the first.
    final base = icp.cur;
    final stiff = ((base - 12) / 14).clamp(0.0, 1.0);
    final amp = 2.2 + 0.2 * base;
    var ic = base + 0.9 * insp;
    for (var i = 0; i < _icpPulses.length;) {
      final p = _icpPulses[i];
      final x = t - p.t0;
      if (x > 1.3) {
        _icpPulses.removeAt(i);
        continue;
      }
      if (x > -0.1) {
        final k = p.tej;
        ic +=
            amp *
            p.amp *
            ((1 - 0.25 * stiff) * _bump(x, 0.09, 0.04) +
                (0.62 + 0.55 * stiff) * _bump(x, 0.22 * k, 0.055) +
                0.42 * _bump(x, 0.38 * k, 0.07));
      }
      i++;
    }
    icpWave.add(ic + 0.06 * ecg.gauss(), t);

    // EEG. The brain needs blood flow: with no output the trace flattens
    // over the next half minute whatever sedation level was set.
    final brainTarget = output ? 1.0 : (ecg.cpr ? 0.45 : 0.05);
    _brain += (brainTarget - _brain) * _h / (brainTarget < _brain ? 12 : 18);
    final level = bis.cur * (0.08 + 0.92 * _brain);
    final b = level / 100;
    _eegTime += _h;
    _eegD += (-_eegD / 0.11) * _h + 4.3 * math.sqrt(_h) * ecg.gauss();
    _eegB += (-_eegB / 0.009) * _h + 14.9 * math.sqrt(_h) * ecg.gauss();
    _eegA += 2 * math.pi * (10 + 0.8 * math.sin(_eegTime * 0.7)) * _h + 0.05 * ecg.gauss();
    _eegAmp += (-(_eegAmp - 1) / 0.8) * _h + 0.9 * math.sqrt(_h) * ecg.gauss();
    final alpha = (3 + 12 * math.exp(-math.pow((level - 70) / 22, 2))) * _eegAmp.clamp(0.2, 2.0) * math.sin(_eegA);
    var v = (4 + 46 * (1 - b)) * _eegD + 9 * math.pow(b, 1.5) * _eegB + alpha;
    if (level < 24) {
      // Burst suppression: stretches of near silence between bursts.
      _eegBurst -= _h;
      if (_eegBurst <= 0) {
        _eegQuiet = !_eegQuiet;
        final quietShare = (1 - level / 24).clamp(0.15, 0.97);
        _eegBurst = _eegQuiet ? 1 + 7 * quietShare * rng.nextDouble() + 3 * quietShare : 0.6 + 2.2 * (1 - quietShare);
      }
      if (_eegQuiet) {
        v *= 0.04;
        _quietTime += _h;
      }
    } else {
      _eegQuiet = false;
    }
    if (t < ecg.artifactUntil) v += 60 * ecg.gauss();
    eeg.add(v, t);

    // Train-of-four: four twitches every 15 seconds.
    if (t - _lastTof >= 15) {
      _lastTof = t;
      final blk = nmt.cur;
      tof = [for (var i = 0; i < 4; i++) (1 - blk * (0.5 + 0.45 * i)).clamp(0.0, 1.0).toDouble()];
      tofTick.value++;
    }

    if (recording > 0) recording = math.max(0, recording - _h);
    for (final inf in infusions) {
      inf.remaining = math.max(0, inf.remaining - inf.rate * _h / 3600);
    }
  }

  /// Twitches still visible, and the fourth-to-first ratio in percent.
  int get tofCount => tof.where((h) => h > 0.04).length;
  int get tofRatio => tof[0] <= 0.04 ? 0 : (100 * tof[3] / tof[0]).round();

  (double, double, double) _window(WaveBuffer b, double seconds) {
    final n = math.min(b.length, (b.fs * seconds).round());
    if (n == 0) return (0, 0, 0);
    var lo = double.infinity, hi = -double.infinity, sum = 0.0;
    for (var i = 0; i < n; i++) {
      final v = b.back(i);
      if (v < lo) lo = v;
      if (v > hi) hi = v;
      sum += v;
    }
    return (lo, hi, sum / n);
  }

  void _updateExtras() {
    final pulsing = t - _lastPulse < 3.2;
    final span = math.max(3.0, 2.5 * _meanRR);

    final (pLo, pHi, pMean) = _window(pap, span);
    papS = pHi.round();
    papD = pLo.round();
    papM = pMean.round();
    cvpValue = _window(cvpWave, math.max(span, _breathPeriod)).$3.round();
    icpValue = _window(icpWave, math.max(span, _breathPeriod)).$3.round();
    final map = abpOn ? abpM : nibpM;
    cpp = map == null || icpValue == null ? null : map - icpValue!;

    // Second temperature is a skin probe: it falls away from core as the
    // circulation shuts down.
    final gap = 2.4 + (sys.cur < 95 ? (95 - sys.cur) * 0.07 : 0) + (pulsing ? 0 : 1.5);
    temp2Value += ((temp.cur - gap) - temp2Value) * 0.02 + 0.01 * ecg.gauss();

    // Pulse-contour cardiac output.
    if (pulsing && !ecg.cpr && abpS != null && pulse != null && pulse! > 0) {
      final pp = (abpS! - abpD!).clamp(2, 120);
      final fill = math.sqrt(_meanRR / 0.83).clamp(0.5, 1.15);
      strokeVolume = (78 * math.pow(pp / 44, 0.8) * fill).round().clamp(5, 120);
      cardiacOutput = strokeVolume! * pulse! / 1000;
      cardiacIndex = cardiacOutput! / bsa;
      svr = cardiacOutput! < 0.3 ? null : (((abpM! - (cvpValue ?? 8)) / cardiacOutput!) * 80).round();
      svv = (6 + (40 - pp) * 0.32 + 1.2 * ecg.gauss()).round().clamp(3, 30);
    } else {
      cardiacOutput = cardiacIndex = null;
      strokeVolume = svr = svv = null;
    }

    // Processed EEG.
    final level = bis.cur * (0.08 + 0.92 * _brain);
    final moving = t < ecg.artifactUntil;
    bisValue = (level + (moving ? 12 : 0) + 1.2 * ecg.gauss()).round().clamp(0, 98);
    sqi = (moving ? 38 : 94 + 2 * ecg.gauss()).round().clamp(0, 100);
    emg = (27 + 20 * math.pow(level / 100, 2) + (moving ? 16 : 0) + ecg.gauss()).round();
    suppression = (100 * _quietTime / 1).round().clamp(0, 100);
    _srAvg += (suppression - _srAvg) * 0.12;
    suppression = _srAvg.round();
    _quietTime = 0;

    // QT and ST, when there are conducted beats to measure.
    final shape = rhythm.shape;
    final h = hr;
    if (shape != null && h != null && h > 25 && !ecg.leadsOff && ecg.gen?.chaoticRate == null) {
      final rr = (60 / h).clamp(0.3, 1.5);
      final wide = shape.wide ? 45 : 0;
      qt = (392 * math.sqrt(rr) + wide + 4 * ecg.gauss()).round();
      qtc = (qt! / math.sqrt(rr)).round();
      for (final l in Lead.values) {
        _stNoise[l.index] += -0.3 * _stNoise[l.index] + 0.05 * ecg.gauss();
        final st = shape.st;
        stAll[l.index] = (st == null ? 0.0 : mixLead(l, (k) => st[k]) * 10) + _stNoise[l.index];
      }
    } else {
      qt = qtc = null;
      stAll = List.filled(12, null);
    }
  }

  double _srAvg = 0;

  void _addHistory() {
    void put(String k, num? v) {
      final list = history.putIfAbsent(k, () => []);
      list.add(v?.toDouble());
      if (list.length > historyLength) list.removeAt(0);
    }

    put('hr', hr);
    put('spo2', spo2Value);
    put('abpS', abpS);
    put('abpD', abpD);
    put('abpM', abpM);
    put('pap', papM);
    put('cvp', cvpValue);
    put('icp', icpValue);
    put('etco2', etco2Value);
    put('rr', awrr);
    put('bis', bisValue);
    put('temp', tempValue);
    put('co', cardiacOutput);
  }

  /// Fills the trend memory with a quiet hour so the graphs are not empty
  /// at start-up. With [fromNow] the hour is built around the present
  /// readings instead of a textbook-normal patient.
  void seedHistory({bool fromNow = false}) => _seedHistory(fromNow: fromNow);

  void _seedHistory({bool fromNow = false}) {
    double v(num? now, double normal) => fromNow && now != null ? now.toDouble() : normal;
    final base = {
      'hr': (v(hr, 72), 1.6),
      'spo2': (v(spo2Value, 98), 0.5),
      'abpS': (v(abpS, 122), 3.0),
      'abpD': (v(abpD, 78), 2.0),
      'abpM': (v(abpM, 95), 2.0),
      'pap': (v(papM, 16), 1.0),
      'cvp': (v(cvpValue, 8), 0.6),
      'icp': (v(icpValue, 10), 0.7),
      'etco2': (v(etco2Value, 38), 1.0),
      'rr': (v(awrr, 14), 0.8),
      'bis': (v(bisValue, 96), 1.0),
      'temp': (v(tempValue, 36.8), 0.03),
      'co': (v(cardiacOutput, 5.5), 0.2),
    };
    for (final e in base.entries) {
      var w = 0.0;
      final (mean, sd) = e.value;
      history[e.key] = [
        for (var i = 0; i < historyLength; i++)
          () {
            w += -0.06 * w + sd * 0.35 * ecg.gauss();
            final v = mean + w;
            return e.key == 'spo2' ? math.min(100.0, v) : v;
          }(),
      ];
    }
  }

  // ----------------------------------------------------------------- NIBP --

  void _stepNibp() {
    if (nibpPhase == NibpPhase.idle) {
      if (nibpAuto > 0 && t >= _nextAuto) startNibp();
      return;
    }
    if (nibpPhase == NibpPhase.inflating) {
      cuff += 36 * _h;
      if (cuff >= _cuffTarget) {
        nibpPhase = NibpPhase.deflating;
        _deflateHold = 0.8;
      }
      return;
    }
    // Step deflation, the way an oscillometric cuff bleeds down.
    _deflateHold -= _h;
    if (_deflateHold <= 0) {
      cuff -= 7 + rng.nextInt(3);
      _deflateHold = 0.95;
    }
    final hasPulse = t - _lastPulse < 2.6 && !ecg.cpr;
    final stopAt = hasPulse ? dia.cur - 14 : 35;
    if (cuff <= stopAt) {
      nibpPhase = NibpPhase.idle;
      cuff = 0;
      if (hasPulse) {
        nibpS = (sys.cur + 2 * ecg.gauss()).round();
        nibpD = (dia.cur + 2 * ecg.gauss()).round();
        nibpM = (nibpD! + (nibpS! - nibpD!) / 3).round();
        nibpFailed = false;
      } else {
        nibpS = nibpD = nibpM = null;
        nibpFailed = true;
      }
      nibpTime = clock();
      _addTrend(withNibp: true);
      notifyListeners();
    }
  }

  // ------------------------------------------------------------- numerics --

  void _updateNumerics() {
    // Heart rate, counted from QRS complexes.
    final chaotic = ecg.gen?.chaoticRate;
    if (ecg.leadsOff) {
      hr = null;
    } else if (chaotic != null) {
      hr = chaotic;
      _pvcTimes.clear();
    } else {
      final recent = [
        for (final b in _beats)
          if (t - b.t < 12) b.t,
      ];
      if (recent.isEmpty || t - recent.last > 4.0) {
        hr = t < 3 ? null : 0;
      } else if (recent.length >= 2) {
        final n = math.min(8, recent.length - 1);
        final span = recent.last - recent[recent.length - 1 - n];
        hr = (60 * n / span).round();
      }
    }
    _pvcTimes.removeWhere((x) => t - x > 60);
    pvcPerMin = _pvcTimes.length;
    pacing = t - _lastPaced < 4;

    // SpO2 and pulse rate, from the pleth.
    final pulsing = t - _lastPulse < 3.2;
    _spo2Noise += -_spo2Noise * 0.2 + 0.25 * ecg.gauss();
    if (probeOff || !pulsing) {
      spo2Value = null;
      pulse = null;
      perf = 0;
    } else {
      spo2Value = (spo2.cur + _spo2Noise).round().clamp(40, 100);
      final pt = [
        for (final x in _pulseTimes)
          if (t - x < 12) x,
      ];
      if (pt.length >= 2) {
        final n = math.min(8, pt.length - 1);
        pulse = (60 * n / (pt.last - pt[pt.length - 1 - n])).round();
      }
      final pp = (sys.cur - dia.cur).clamp(5, 80);
      perf = (0.06 * pp * (ecg.cpr ? 0.3 : 1) * (0.9 + 0.2 * rng.nextDouble())).clamp(0.1, 9.9).toDouble();
    }

    // Arterial line, averaged over the last few beats.
    if (_abpBeats.isNotEmpty && t - _lastPulse < 3.2 || ecg.cpr && _abpBeats.isNotEmpty) {
      final n = math.min(4, _abpBeats.length);
      var a = 0.0, b = 0.0, c = 0.0;
      for (final x in _abpBeats.sublist(_abpBeats.length - n)) {
        a += x[0];
        b += x[1];
        c += x[2];
      }
      abpS = (a / n).round();
      abpD = (b / n).round();
      abpM = (c / n).round();
    } else {
      abpS = abpD = abpM = _abp.round();
    }

    // Capnography.
    final sinceBreath = t - _breathStarts.last;
    if (sinceBreath > 12) {
      awrr = 0;
      etco2Value = 0;
    } else {
      etco2Value = etco2Peak.round();
      if (_breathStarts.length >= 3) {
        final n = math.min(4, _breathStarts.length - 1);
        awrr = (60 * n / (_breathStarts.last - _breathStarts[_breathStarts.length - 1 - n])).round();
      }
    }

    tempValue = temp.cur;
    _updateExtras();
    notifyListeners();
  }

  /// ST deviation in millimetres for [lead], when the rhythm has conducted
  /// beats to measure it on.
  double? stFor(Lead lead) => stAll[lead.index];

  // --------------------------------------------------------------- trends --

  void _addTrend({bool withNibp = false}) {
    trends.add(
      TrendRow(
        clock(),
        hr,
        spo2Value,
        awrr,
        etco2Value,
        tempValue,
        nibp: withNibp ? (nibpS == null ? '-?-' : '$nibpS/$nibpD ($nibpM)') : null,
      ),
    );
    if (trends.length > 60) trends.removeAt(0);
  }

  void _seedTrends() {
    final now = clock();
    for (var i = 9; i >= 1; i--) {
      final s = 120 + rng.nextInt(7) - 3, d = 78 + rng.nextInt(5) - 2;
      trends.add(
        TrendRow(
          now.subtract(Duration(minutes: i)),
          70 + rng.nextInt(6),
          97 + rng.nextInt(2),
          13 + rng.nextInt(3),
          37 + rng.nextInt(3),
          36.8,
          nibp: i == 9 || i == 4 ? '$s/$d (${(d + (s - d) / 3).round()})' : null,
        ),
      );
    }
  }
}
