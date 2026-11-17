import 'package:flutter_test/flutter_test.dart';
import 'package:heart_monitor/sim/ecg_shapes.dart';
import 'package:heart_monitor/sim/patient_sim.dart';
import 'package:heart_monitor/sim/rhythms.dart';
import 'package:heart_monitor/sim/scenarios.dart';

PatientSim run(String rhythm, {double seconds = 30, int seed = 7}) {
  final sim = PatientSim(seed: seed)..setRhythm(rhythm);
  for (var i = 0; i < seconds * 50; i++) {
    sim.advance(0.02);
  }
  return sim;
}

List<String> alarms(PatientSim s) => [for (final a in s.alarms) a.text];

void main() {
  test('normal sinus rhythm reads back the values that were set', () {
    final s = run('nsr', seconds: 45);
    expect(s.hr, inInclusiveRange(68, 76));
    expect(s.pulse, inInclusiveRange(68, 76));
    expect(s.spo2Value, inInclusiveRange(97, 99));
    expect(s.abpS, inInclusiveRange(118, 126));
    expect(s.abpD, inInclusiveRange(75, 81));
    expect(s.etco2Value, inInclusiveRange(35, 41));
    expect(s.awrr, inInclusiveRange(12, 16));
    expect(s.nibpS, isNotNull, reason: 'the first automatic cuff reading should have finished');
    expect(alarms(s), isEmpty);
  });

  test('rate follows the slider for every adjustable rhythm', () {
    for (final r in kRhythms.where((r) => !r.fixedRate && !r.pulseless)) {
      final s = run(r.id, seconds: 25);
      expect(s.hr, isNotNull, reason: r.id);
      // Dropped and non-captured beats legitimately pull the count down.
      // An eight-beat count of an irregular rhythm wanders.
      final slack = r.id.startsWith('avb2') || r.id == 'paced_fail' ? 30 : (r.id.startsWith('afib') ? 24 : 12);
      expect((s.hr! - r.rate).abs(), lessThanOrEqualTo(slack), reason: '${r.id} hr=${s.hr}');
    }
  });

  test('arrest rhythms lose the pulse and raise the right alarms', () {
    final vf = run('vf_coarse');
    expect(vf.spo2Value, isNull);
    expect(vf.abpS, lessThan(30));
    expect(alarms(vf), containsAll(['V-FIB', 'APNEA']));

    final flat = run('asystole');
    expect(flat.hr, 0);
    expect(alarms(flat), contains('ASYSTOLE'));

    final pea = run('pea');
    expect(pea.hr, inInclusiveRange(50, 66));
    expect(pea.pulse, isNull);
  });

  test('ectopy is counted and weak beats lower the pressure', () {
    final s = run('bigeminy', seconds: 40);
    expect(s.pvcPerMin, greaterThan(10));
    expect(alarms(s), contains('VENT BIGEMINY'));
    expect(s.abpS, lessThan(118));
  });

  test('silence acknowledges, pause suppresses', () {
    final s = run('sinus_tach');
    expect(s.soundingPriority, isNotNull);
    s.silence();
    expect(s.soundingPriority, isNull);
    expect(s.alarms, isNotEmpty);
    s.setRhythm('vt');
    for (var i = 0; i < 500; i++) {
      s.advance(0.02);
    }
    expect(s.soundingPriority, isNotNull, reason: 'a new alarm sounds even after silencing the old one');
    s.pauseAlarms();
    expect(s.soundingPriority, isNull);
  });

  test('a shock converts a shockable rhythm', () {
    final s = run('vf_coarse', seconds: 15);
    s.shock();
    for (var i = 0; i < 20 * 50; i++) {
      s.advance(0.02);
    }
    expect(s.rhythm.id, 'nsr');
    expect(s.hr, inInclusiveRange(70, 110));
    expect(s.spo2Value, isNotNull);
  });

  test('the extra measurements stay coherent with the circulation', () {
    final s = run('nsr', seconds: 45);
    expect(s.papS, inInclusiveRange(22, 29));
    expect(s.papD, inInclusiveRange(6, 12));
    expect(s.cvpValue, inInclusiveRange(6, 10));
    expect(s.icpValue, inInclusiveRange(9, 13));
    expect(s.cpp, s.abpM! - s.icpValue!);
    expect(s.cardiacOutput, inInclusiveRange(4.5, 6.5));
    expect(s.bisValue, greaterThan(90));
    expect(s.qtc, inInclusiveRange(380, 420));
    expect(s.stAll.every((v) => v != null && v.abs() < 0.5), isTrue);
    expect(s.tofCount, 4);

    final st = run('stemi_inf', seconds: 20);
    expect(st.stFor(Lead.iii)!, greaterThan(2.5));
    expect(st.stFor(Lead.avl)!, lessThan(-1));

    final vf = run('vf_coarse', seconds: 60);
    expect(vf.cardiacOutput, isNull);
    expect(vf.bisValue, lessThan(25), reason: 'no blood flow, no EEG');
    expect(vf.cvpValue, greaterThan(11));
    expect([for (final e in vf.events) e.text], contains('!!! V-FIB'));
  });

  test('every scenario runs to the end with finite output', () {
    for (final sc in kScenarios) {
      final s = PatientSim(seed: 3)..runScenario(sc);
      for (var i = 0; i < (sc.length + 30) * 50; i++) {
        s.advance(0.02);
      }
      for (var i = 0; i < 2000; i++) {
        expect(s.abp.back(i).isFinite, isTrue, reason: sc.id);
        expect(s.pleth.back(i).isFinite, isTrue, reason: sc.id);
        expect(s.pap.back(i).isFinite && s.cvpWave.back(i).isFinite, isTrue, reason: sc.id);
        expect(s.icpWave.back(i).isFinite && s.eeg.back(i).isFinite, isTrue, reason: sc.id);
        expect(s.lead(s.rhythm.shape == null ? Lead.ii : Lead.v1).back(i).isFinite, isTrue, reason: sc.id);
      }
    }
    final arrest = PatientSim(seed: 3)..runScenario(kScenarios.firstWhere((s) => s.id == 'arrest'));
    for (var i = 0; i < 260 * 50; i++) {
      arrest.advance(0.02);
    }
    expect(arrest.spo2Value, isNotNull, reason: 'pulse should be back after the second shock');
    expect(arrest.cpr, isFalse);
  });
}
