import 'dart:math' as math;
import 'dart:typed_data';

import 'ecg_shapes.dart';
import 'wave_buffer.dart';

/// How the monitor would label a detected beat.
enum BeatKind { normal, atrial, junctional, ventricular, paced, escape }

/// A QRS the monitor can count, with how much of a pulse it produces.
class Beat {
  Beat(this.t, this.kind, this.strength, this.rr);
  final double t;
  final BeatKind kind;

  /// 0 = no output at all, 1 = a full normal pulse.
  final double strength;

  /// Interval the generator intended before this beat, in seconds.
  final double rr;
}

class _Wi {
  _Wi(this.c, this.sl, this.sr, this.a, this.g);
  final double c, sl, sr, g;
  final List<double> a;
}

class _Spike {
  _Spike(this.t, this.amp);
  final double t, amp;
}

/// Sums scheduled deflections, pacing spikes, rhythm baselines and noise into
/// eight lead buffers at [fs] samples per second.
class EcgEngine {
  EcgEngine(this.rng) {
    for (var i = 0; i < kBaseLeads; i++) {
      leads.add(WaveBuffer(fs, 40));
    }
  }

  static const double fs = 250;
  static const double dt = 1 / fs;

  final math.Random rng;
  final List<WaveBuffer> leads = [];

  double now = 0;

  /// Rate the active rhythm should run at, in beats per minute.
  double rate = 75;

  /// Breathing, supplied by the patient model; drives sinus arrhythmia and
  /// baseline movement.
  double respPhase = 0;
  double respHz = 0.25;
  bool breathing = true;

  bool leadsOff = false;
  bool cpr = false;
  double artifactUntil = -1;
  double _shockAt = -100;

  /// Extra ventricular beats requested from the control panel.
  int pvcQueue = 0;

  RhythmGen? gen;

  final List<_Wi> _w = [];
  final List<_Spike> _spikes = [];

  /// Beats scheduled but not yet reached, oldest first.
  final List<Beat> pending = [];

  /// One-off notes from a generator ("missed beat", "not capturing").
  final List<({double t, String code})> notes = [];

  final Float64List _acc = Float64List(kBaseLeads);
  final Float64List _hf = Float64List(kBaseLeads);
  final Float64List _motion = Float64List(kBaseLeads);
  double _wander = 0;
  double _cprPhase = 0;
  double _cprAmp = 0.7;
  double _lastPrune = 0;

  static const List<double> _artScale = [.7, 1, .5, .6, .7, .8, .8, .7];
  static const List<double> _respScale = [.4, 1, .3, .5, .6, .7, .7, .6];

  // ------------------------------------------------------------ helpers --

  double gauss() {
    final u = math.max(rng.nextDouble(), 1e-12);
    final v = rng.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  /// Breathing waveform (-1..1) expected at future time [t].
  double respAt(double t) {
    if (!breathing) return 0;
    return math.sin(2 * math.pi * (respPhase + (t - now) * respHz));
  }

  static double qtScale(double rr) => math.sqrt(rr.clamp(0.27, 1.4));

  // --------------------------------------------------------- scheduling --

  void addP(double centre, List<Wv> shape, {double gain = 1}) {
    for (final w in shape) {
      _w.add(_Wi(centre + w.t, w.sl, w.sr, w.a, gain));
    }
  }

  /// Schedules a ventricular complex with its R point at [tR].
  void addQrs(double tR, BeatShape shape, double rr, {double gain = 1, double tGain = 1}) {
    for (final w in shape.qrs) {
      _w.add(_Wi(tR + w.t, w.sl, w.sr, w.a, gain));
    }
    final k = qtScale(rr);
    final ks = math.pow(k, 0.8).toDouble();
    for (final w in shape.t) {
      _w.add(_Wi(tR + w.t * k, w.sl * ks, w.sr * ks, w.a, gain * tGain));
    }
  }

  void addSpike(double t, {double amp = 1.6}) => _spikes.add(_Spike(t, amp));

  void addBeat(double t, BeatKind kind, double strength, double rr) {
    pending.add(Beat(t, kind, strength, rr));
  }

  void note(double t, String code) => notes.add((t: t, code: code));

  /// Atrial centre time for a P wave whose PR interval ends at R point [tR].
  static double pCentre(double tR, double pr) => tR - 0.04 - pr + 0.045;

  /// Swaps the rhythm. Deflections already on screen finish; everything not
  /// yet started is discarded.
  void setGenerator(RhythmGen g, {double delay = 0.55}) {
    _w.removeWhere((w) => w.c - 3 * w.sl > now);
    _spikes.removeWhere((s) => s.t > now);
    pending.removeWhere((b) => b.t > now);
    notes.removeWhere((n) => n.t > now);
    gen = g;
    g.start(now + delay);
  }

  void shock() {
    _shockAt = now;
    _w.clear();
    _spikes.clear();
    pending.clear();
  }

  // ----------------------------------------------------------- sampling --

  /// Produces the sample for time [t] (one [dt] after the previous call).
  void step(double t) {
    final prev = now;
    now = t;
    gen?.schedule(t + 1.3);

    final acc = _acc;
    for (var k = 0; k < kBaseLeads; k++) {
      acc[k] = 0;
    }

    if (leadsOff) {
      for (var k = 0; k < kBaseLeads; k++) {
        leads[k].add(0, t);
      }
      return;
    }

    for (var i = 0; i < _w.length; i++) {
      final w = _w[i];
      final d = t - w.c;
      final s = d < 0 ? w.sl : w.sr;
      final x = d / s;
      if (x < -4 || x > 4) continue;
      final v = w.g * math.exp(-0.5 * x * x);
      final a = w.a;
      for (var k = 0; k < kBaseLeads; k++) {
        acc[k] += v * a[k];
      }
    }
    if (t - _lastPrune > 0.5) {
      _lastPrune = t;
      _w.removeWhere((w) => w.c + 4.5 * w.sr < t);
      _spikes.removeWhere((s) => s.t < t - 0.1);
    }

    gen?.baseline(t, acc);

    for (final s in _spikes) {
      if (s.t > prev && s.t <= t) {
        for (var k = 0; k < kBaseLeads; k++) {
          acc[k] += s.amp * (k == 2 || k == 3 ? -0.8 : 1);
        }
      } else if (s.t > prev - dt && s.t <= prev) {
        for (var k = 0; k < kBaseLeads; k++) {
          acc[k] -= s.amp * 0.18 * (k == 2 || k == 3 ? -0.8 : 1);
        }
      }
    }

    // Slow baseline movement: breathing plus a little electrode drift.
    _wander += (-_wander / 3.0) * dt + 0.012 * math.sqrt(dt) * gauss();
    final resp = breathing ? math.sin(2 * math.pi * respPhase) : 0.0;

    final moving = t < artifactUntil;
    double cprV = 0;
    if (cpr) {
      _cprPhase += 1.83 * dt * (1 + 0.02 * gauss());
      if (_cprPhase >= 1) {
        _cprPhase -= 1;
        _cprAmp = 0.55 + 0.35 * rng.nextDouble();
      }
      final p = 2 * math.pi * _cprPhase;
      cprV = _cprAmp * (math.sin(p) + 0.45 * math.sin(2 * p + 0.6) + 0.15 * math.sin(3 * p + 1.1));
    }
    final sinceShock = t - _shockAt;

    for (var k = 0; k < kBaseLeads; k++) {
      _hf[k] += (-_hf[k] / 0.004) * dt + 0.11 * math.sqrt(dt) * gauss();
      var v = acc[k] + _hf[k] + _wander * _artScale[k] + 0.035 * resp * _respScale[k];
      if (moving) {
        _motion[k] += (-_motion[k] / 0.12) * dt + 2.6 * math.sqrt(dt) * gauss();
        v += _motion[k] * _artScale[k] + 0.05 * gauss();
      } else if (_motion[k] != 0) {
        _motion[k] *= 0.97;
        if (_motion[k].abs() < 1e-4) _motion[k] = 0;
        v += _motion[k] * _artScale[k];
      }
      if (cpr) v += cprV * _artScale[k] * (k.isEven ? 1 : 0.85);
      if (sinceShock >= 0 && sinceShock < 3) {
        final sign = k == 2 || k == 3 ? -1.0 : 1.0;
        v = sinceShock < 0.12 ? sign * 9 : v + sign * 6 * math.exp(-(sinceShock - 0.12) / 0.3);
      }
      leads[k].add(v, t);
    }
  }
}

/// Decides when beats happen and what they look like.
abstract class RhythmGen {
  RhythmGen(this.e);
  final EcgEngine e;
  double next = 0;

  void start(double t) => next = t;

  /// Schedule everything due before [horizon].
  void schedule(double horizon);

  /// Continuous activity that is not made of discrete beats.
  void baseline(double t, Float64List out) {}

  /// Rate a monitor would show when there are no countable beats.
  int? get chaoticRate => null;
}

enum Ectopy { none, pac, pvcOccasional, pvcFrequent, bigeminy, trigeminy, couplets, multifocal, runs }

enum AvBlock { none, first, wenckebach, mobitz2 }

/// Sinus node driving the ventricles, with optional conduction faults and
/// ectopic beats.
class SinusGen extends RhythmGen {
  SinusGen(
    super.e, {
    this.shape = kNormal,
    this.pr = 0.16,
    this.rsa = 0.035,
    this.ectopy = Ectopy.none,
    this.block = AvBlock.none,
    this.strength = 1,
    this.pShape = kPNormal,
    this.pGain = 1,
  });

  final BeatShape shape;
  final double pr;
  final double rsa;
  final Ectopy ectopy;
  final AvBlock block;
  final double strength;
  final List<Wv> pShape;
  final double pGain;

  int _cycle = 0;
  int _sinceEctopic = 0;

  double _gain(double t) => 1 + 0.04 * e.respAt(t) + 0.015 * e.gauss();

  @override
  void schedule(double horizon) {
    while (next < horizon) {
      final base = 60 / e.rate.clamp(20, 260);
      final rr = base * (1 + rsa * e.respAt(next) + 0.012 * e.gauss());
      _sinceEctopic++;

      var thisPr = pr;
      var conducted = true;
      switch (block) {
        case AvBlock.none:
          break;
        case AvBlock.first:
          thisPr = 0.3;
        case AvBlock.wenckebach:
          const steps = [0.2, 0.29, 0.36, 0.4];
          if (_cycle >= 3) {
            conducted = false;
            thisPr = steps[3];
            _cycle = 0;
          } else {
            thisPr = steps[_cycle];
            _cycle++;
          }
        case AvBlock.mobitz2:
          thisPr = 0.2;
          _cycle++;
          if (_cycle >= 3 && (e.rng.nextDouble() < 0.6 || _cycle >= 4)) {
            conducted = false;
            _cycle = 0;
          }
      }

      // The atria stay on time; a longer PR pushes the QRS later.
      final tSinus = next;
      final tR = tSinus + (thisPr - pr);
      e.addP(EcgEngine.pCentre(tSinus, pr), pShape, gain: pGain * _gain(tSinus));
      if (!conducted) {
        e.note(tSinus, 'missed');
        next = tSinus + rr;
        continue;
      }
      e.addQrs(tR, shape, rr, gain: _gain(tR));
      e.addBeat(tR, BeatKind.normal, strength, rr);
      next = tSinus + rr;

      var extra = 0;
      var atrial = false;
      if (e.pvcQueue > 0) {
        extra = e.pvcQueue;
        e.pvcQueue = 0;
      } else {
        switch (ectopy) {
          case Ectopy.none:
            break;
          case Ectopy.pac:
            atrial = _sinceEctopic > 3 && e.rng.nextDouble() < 0.16;
          case Ectopy.pvcOccasional:
            if (_sinceEctopic > 4 && e.rng.nextDouble() < 0.08) extra = 1;
          case Ectopy.pvcFrequent:
            if (_sinceEctopic > 2 && e.rng.nextDouble() < 0.26) extra = 1;
          case Ectopy.bigeminy:
            extra = 1;
          case Ectopy.trigeminy:
            if (_sinceEctopic >= 2) extra = 1;
          case Ectopy.couplets:
            if (_sinceEctopic > 4 && e.rng.nextDouble() < 0.13) extra = 2;
          case Ectopy.multifocal:
            if (_sinceEctopic > 2 && e.rng.nextDouble() < 0.24) extra = 1;
          case Ectopy.runs:
            if (_sinceEctopic > 6 && e.rng.nextDouble() < 0.1) extra = 4 + e.rng.nextInt(5);
        }
      }

      if (atrial) {
        final tA = tR + rr * 0.62;
        e.addP(EcgEngine.pCentre(tA, 0.15), kPEctopic);
        e.addQrs(tA, shape, rr * 0.62, gain: 0.95);
        e.addBeat(tA, BeatKind.atrial, strength * 0.7, rr * 0.62);
        next = tA + rr * 1.05;
        _sinceEctopic = 0;
      } else if (extra > 0) {
        final multi = ectopy == Ectopy.multifocal;
        var tV = tR + (rr * 0.56).clamp(0.3, 0.6);
        var prevGap = tV - tR;
        final run = multi ? null : kPvcA;
        for (var i = 0; i < extra; i++) {
          final s = run ?? (e.rng.nextBool() ? kPvcA : kPvcB);
          e.addQrs(tV, extra > 2 ? kVt : s, extra > 2 ? 0.36 : rr, gain: 0.92 + 0.12 * e.rng.nextDouble());
          e.addBeat(tV, BeatKind.ventricular, strength * (i == 0 ? 0.35 : 0.22), prevGap);
          prevGap = extra > 2 ? 0.36 + 0.015 * e.gauss() : 0.42;
          if (i < extra - 1) tV += prevGap;
        }
        // The sinus node keeps time underneath; the next conducted beat is
        // the first one clear of the refractory period.
        var resume = tSinus + 2 * rr;
        while (resume < tV + 0.5) {
          resume += rr;
        }
        next = resume;
        _sinceEctopic = 0;
      }
    }
  }
}

/// Fibrillating atria: no P waves, a restless baseline and R-R intervals
/// with no pattern at all.
class AfibGen extends RhythmGen {
  AfibGen(super.e, {this.shape = kNormalSmallT, this.strength = 1});
  final BeatShape shape;
  final double strength;
  double _prev = 0.8;
  final List<double> _ph = [0, 1.3, 2.9, 4.1];
  double _mod = 0;

  @override
  void schedule(double horizon) {
    while (next < horizon) {
      final mean = 60 / e.rate.clamp(30, 220);
      final rr = (mean * math.exp(0.24 * e.gauss() - 0.03)).clamp(0.29, 2.4).toDouble();
      final tR = next;
      if (e.pvcQueue > 0) {
        e.pvcQueue--;
        e.addQrs(tR, kPvcA, mean);
        e.addBeat(tR, BeatKind.ventricular, strength * 0.35, _prev);
      } else {
        e.addQrs(tR, shape, _prev, gain: 0.9 + 0.2 * e.rng.nextDouble());
        final fill = math.pow(_prev / mean, 0.6).toDouble().clamp(0.35, 1.12);
        e.addBeat(tR, BeatKind.normal, strength * fill, _prev);
      }
      _prev = rr;
      next = tR + rr;
    }
  }

  @override
  void baseline(double t, Float64List out) {
    const f = [5.3, 6.6, 7.9, 4.4];
    const amp = [1.0, .8, .55, .5];
    _mod += EcgEngine.dt;
    var v = 0.0;
    for (var i = 0; i < 4; i++) {
      _ph[i] += 2 * math.pi * f[i] * EcgEngine.dt + 0.05 * e.gauss();
      v += amp[i] * math.sin(_ph[i]);
    }
    v *= 0.032 * (0.75 + 0.25 * math.sin(_mod * 0.9));
    const scale = [.35, .8, 1.3, .7, .4, .35, .3, .3];
    for (var k = 0; k < kBaseLeads; k++) {
      out[k] += v * scale[k];
    }
  }
}

/// Atrial flutter: a 300/min sawtooth with every [ratio]-th wave conducted.
class FlutterGen extends RhythmGen {
  FlutterGen(super.e, {this.ratio = 4});

  /// Flutter waves per QRS; 0 means the block keeps changing.
  final int ratio;
  static const double cycle = 0.2;
  double _t0 = 0;
  double _prev = 0.8;

  @override
  void start(double t) {
    super.start(t);
    _t0 = t - 0.11;
  }

  @override
  void schedule(double horizon) {
    while (next < horizon) {
      final n = ratio > 0 ? ratio : const [2, 3, 4, 4, 4, 2, 3][e.rng.nextInt(7)];
      final rr = n * cycle;
      e.addQrs(next, kNormalSmallT, _prev, gain: 0.95 + 0.08 * e.rng.nextDouble());
      e.addBeat(next, BeatKind.normal, 1, _prev);
      _prev = rr;
      next += rr;
    }
  }

  @override
  void baseline(double t, Float64List out) {
    final ph = 2 * math.pi * ((t - _t0) / cycle);
    // First harmonics of a sawtooth: slow fall, quick rise.
    final saw = math.sin(ph) + math.sin(2 * ph) / 2 + math.sin(3 * ph) / 3 + math.sin(4 * ph) / 4;
    const scale = [.12, 1, -.5, -.3, -.15, .1, .2, .25];
    for (var k = 0; k < kBaseLeads; k++) {
      out[k] += 0.14 * saw * scale[k];
    }
  }
}

enum PMode { none, retroAfter, invertedBefore }

/// A single focus firing regularly: SVT, junctional and ventricular rhythms.
class RegularGen extends RhythmGen {
  RegularGen(
    super.e, {
    required this.shape,
    required this.kind,
    this.p = PMode.none,
    this.jitter = 0.01,
    this.strength = 1,
    this.gainDrift = 0,
  });

  final BeatShape shape;
  final BeatKind kind;
  final PMode p;
  final double jitter;
  final double strength;
  final double gainDrift;
  double _g = 1;

  @override
  void schedule(double horizon) {
    while (next < horizon) {
      final rr = 60 / e.rate.clamp(6, 300) * (1 + jitter * e.gauss()).clamp(0.5, 1.8).toDouble();
      _g = (_g + gainDrift * e.gauss()).clamp(0.45, 1.15).toDouble();
      final g = _g * (1 + 0.03 * e.respAt(next));
      if (p == PMode.invertedBefore) e.addP(EcgEngine.pCentre(next, 0.1), kPRetro);
      if (p == PMode.retroAfter) e.addP(next + 0.075, kPRetro, gain: 0.9);
      e.addQrs(next, shape, rr, gain: g, tGain: p == PMode.retroAfter ? 0.75 : 1);
      e.addBeat(next, kind, strength, rr);
      next += rr;
    }
  }
}

/// Complete heart block: the atria carry on at their own rate while a slow
/// escape focus drives the ventricles, with no relationship between them.
class CompleteBlockGen extends RhythmGen {
  CompleteBlockGen(super.e, {this.atrialRate = 84});
  final double atrialRate;
  double _nextP = 0;

  @override
  void start(double t) {
    super.start(t);
    _nextP = t - 0.3;
  }

  @override
  void schedule(double horizon) {
    while (_nextP < horizon) {
      e.addP(_nextP, kPNormal, gain: 1.1);
      _nextP += 60 / atrialRate * (1 + 0.02 * e.gauss());
    }
    while (next < horizon) {
      final rr = 60 / e.rate.clamp(15, 80) * (1 + 0.012 * e.gauss());
      e.addQrs(next, kEscape, rr);
      e.addBeat(next, BeatKind.escape, 0.85, rr);
      next += rr;
    }
  }
}

enum PaceMode { atrial, ventricular, dual, failing }

class PacedGen extends RhythmGen {
  PacedGen(super.e, this.mode);
  final PaceMode mode;
  int _missed = 0;

  @override
  void schedule(double horizon) {
    while (next < horizon) {
      final rr = 60 / e.rate.clamp(30, 180);
      final t = next;
      switch (mode) {
        case PaceMode.atrial:
          e.addSpike(t, amp: 1.0);
          e.addP(t + 0.05, kPPaced);
          e.addQrs(t + 0.2, kNormal, rr);
          e.addBeat(t + 0.2, BeatKind.paced, 1, rr);
        case PaceMode.ventricular:
          e.addSpike(t);
          e.addQrs(t, kPacedV, rr);
          e.addBeat(t + 0.075, BeatKind.paced, 0.9, rr);
        case PaceMode.dual:
          e.addSpike(t - 0.16, amp: 1.0);
          e.addP(t - 0.11, kPPaced);
          e.addSpike(t);
          e.addQrs(t, kPacedV, rr);
          e.addBeat(t + 0.075, BeatKind.paced, 0.95, rr);
        case PaceMode.failing:
          e.addSpike(t);
          final capture = _missed >= 2 || e.rng.nextDouble() < 0.62;
          if (capture) {
            _missed = 0;
            e.addQrs(t, kPacedV, rr);
            e.addBeat(t + 0.075, BeatKind.paced, 0.9, rr);
          } else {
            _missed++;
            e.note(t, 'nocapture');
          }
      }
      next = t + rr;
    }
  }
}

enum Chaos { vfCoarse, vfFine, torsades, asystole }

/// Rhythms with no organised beats at all.
class ChaoticGen extends RhythmGen {
  ChaoticGen(super.e, this.kind) {
    for (var i = 0; i < _n; i++) {
      _ph.add(e.rng.nextDouble() * 6.28);
      _fm.add(0);
    }
    for (var k = 0; k < kBaseLeads; k++) {
      _mix.add([for (var i = 0; i < _n; i++) (0.4 + 0.6 * e.rng.nextDouble()) * (e.rng.nextBool() ? 1 : -1)]);
    }
  }

  final Chaos kind;
  static const int _n = 5;
  static const List<double> _f = [3.1, 4.3, 5.2, 6.4, 7.7];
  static const List<double> _a = [.8, 1, .9, .55, .35];
  final List<double> _ph = [];
  final List<double> _fm = [];
  final List<List<double>> _mix = [];
  double _t = 0;
  double _env = 1;
  int _shown = 0;
  double _shownAt = -10;

  @override
  void schedule(double horizon) {}

  @override
  int? get chaoticRate {
    if (kind == Chaos.asystole) return null;
    if (e.now - _shownAt > 1.5) {
      _shownAt = e.now;
      _shown = switch (kind) {
        Chaos.vfCoarse => 190 + e.rng.nextInt(120),
        Chaos.vfFine => e.rng.nextInt(3) == 0 ? 0 : 40 + e.rng.nextInt(160),
        Chaos.torsades => 205 + e.rng.nextInt(45),
        Chaos.asystole => 0,
      };
    }
    return _shown;
  }

  @override
  void baseline(double t, Float64List out) {
    const dt = EcgEngine.dt;
    _t += dt;
    switch (kind) {
      case Chaos.asystole:
        return;
      case Chaos.torsades:
        final twist = math.sin(2 * math.pi * _t / 5.2);
        _ph[0] += 2 * math.pi * 3.9 * dt * (1 + 0.04 * math.sin(_t * 1.7));
        final c = math.sin(_ph[0]) + 0.22 * math.sin(2 * _ph[0] + 0.5);
        final v = 1.25 * twist * c;
        const scale = [.45, 1, -.8, -.9, -.5, .4, .75, .8];
        for (var k = 0; k < kBaseLeads; k++) {
          out[k] += v * scale[k] + 0.12 * (1 - twist.abs()) * math.sin(_ph[0] * 0.5 + k);
        }
      case Chaos.vfCoarse:
      case Chaos.vfFine:
        _env += (-(_env - 1) / 1.2) * dt + 0.5 * math.sqrt(dt) * e.gauss();
        final env = _env.clamp(0.35, 1.6);
        final amp = kind == Chaos.vfCoarse ? 0.36 : 0.075;
        for (var i = 0; i < _n; i++) {
          _fm[i] += (-_fm[i] / 0.6) * dt + 0.9 * math.sqrt(dt) * e.gauss();
          _ph[i] += 2 * math.pi * (_f[i] + _fm[i]) * dt;
        }
        for (var k = 0; k < kBaseLeads; k++) {
          var v = 0.0;
          final m = _mix[k];
          for (var i = 0; i < _n; i++) {
            v += _a[i] * m[i] * math.sin(_ph[i] + k * 0.3 * i);
          }
          out[k] += v * amp * env;
        }
    }
  }
}

/// Irregular, widely spaced beats that fade out.
class AgonalGen extends RhythmGen {
  AgonalGen(super.e);

  @override
  void schedule(double horizon) {
    while (next < horizon) {
      final rr = 60 / e.rate.clamp(5, 40) * (0.7 + 0.7 * e.rng.nextDouble());
      e.addQrs(next, kAgonal, rr, gain: 0.6 + 0.6 * e.rng.nextDouble());
      e.addBeat(next, BeatKind.escape, 0, rr);
      next += rr;
    }
  }
}
