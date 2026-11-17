import 'patient_sim.dart';

class ScenarioStep {
  const ScenarioStep(this.at, this.note, this.run);

  /// Seconds after the scenario starts.
  final double at;

  /// What is happening, shown in the control panel only.
  final String note;
  final void Function(PatientSim sim) run;
}

/// A scripted sequence of changes that plays out on its own.
class Scenario {
  const Scenario(this.id, this.name, this.summary, this.steps);
  final String id;
  final String name;
  final String summary;
  final List<ScenarioStep> steps;

  double get length => steps.last.at;
}

void _baseline(PatientSim s) {
  s.cvp.set(8, 5);
  s.paSys.set(25, 5);
  s.paDia.set(10, 5);
  s.icp.set(10, 5);
  s.bis.set(96, 5);
  s.nmt.set(0, 5);
  s.setForcePulseless(false);
  s.setCpr(false);
  s.setVent(VentMode.spontaneous);
  s.obstruction.set(0, 2);
}

final List<Scenario> kScenarios = [
  Scenario('stable', 'Stable patient', 'Healthy resting adult. Use this to reset everything.', [
    ScenarioStep(0, 'Normal sinus rhythm, normal vitals', (s) => s.reset()),
  ]),

  Scenario(
    'arrest',
    'Chest pain to cardiac arrest',
    'Inferior STEMI, ectopy, V-tach, V-fib, CPR, two shocks, return of pulse. About 3½ minutes.',
    [
      ScenarioStep(0, 'Anxious, chest pain', (s) {
        _baseline(s);
        s.setRhythm('sinus_tach', bpm: 104);
        s.setBp(152, 94, over: 5);
        s.spo2.set(96, 5);
        s.respRate.set(20, 5);
        s.etco2.set(34, 8);
      }),
      ScenarioStep(18, 'ST elevation appears', (s) {
        s.setRhythm('stemi_inf', bpm: 96);
        s.setRate(66, over: 25);
        s.setBp(108, 64, over: 30);
      }),
      ScenarioStep(55, 'Ventricular ectopy', (s) {
        s.setRhythm('pvc_freq', bpm: 70);
        s.spo2.set(93, 20);
      }),
      ScenarioStep(80, 'Runs of VT', (s) => s.setRhythm('nsvt', bpm: 76)),
      ScenarioStep(100, 'Sustained V-tach, still a pulse', (s) {
        s.setRhythm('vt', bpm: 178);
        s.setBp(82, 52, over: 6);
      }),
      ScenarioStep(114, 'Ventricular fibrillation', (s) => s.setRhythm('vf_coarse')),
      ScenarioStep(126, 'CPR started', (s) {
        s.setCpr(true);
        s.setVent(VentMode.assisted);
        s.respRate.set(10, 1);
      }),
      ScenarioStep(150, 'Shock 1 - still in VF', (s) {
        s.setCpr(false);
        s.shock(then: 'vf_coarse');
      }),
      ScenarioStep(156, 'CPR resumed', (s) => s.setCpr(true)),
      ScenarioStep(186, 'Shock 2', (s) {
        s.setCpr(false);
        s.shock(then: 'sinus_tach', rate: 118);
        s.setBp(94, 56, over: 8);
        s.spo2.set(90, 2);
      }),
      ScenarioStep(190, 'Return of spontaneous circulation', (s) {
        s.etco2.set(52, 2);
        s.spo2.set(97, 40);
      }),
      ScenarioStep(204, 'Post-arrest, occasional PVCs', (s) {
        s.setRhythm('pvc_occ', bpm: 112);
        s.setRate(98, over: 40);
        s.setBp(108, 66, over: 30);
        s.etco2.set(40, 40);
        s.respRate.set(14, 10);
      }),
    ],
  ),

  Scenario('flatline', 'Flatline', 'Slows, widens and stops. About 50 seconds.', [
    ScenarioStep(0, 'Bradycardia', (s) {
      _baseline(s);
      s.setRhythm('sinus_brady', bpm: 52);
      s.setRate(34, over: 16);
      s.setBp(74, 40, over: 14);
      s.spo2.set(84, 20);
      s.respRate.set(6, 12);
    }),
    ScenarioStep(18, 'Idioventricular', (s) {
      s.setRhythm('idio', bpm: 30);
      s.setRate(20, over: 14);
      s.setBp(48, 26, over: 8);
    }),
    ScenarioStep(34, 'Agonal', (s) => s.setRhythm('agonal', bpm: 12)),
    ScenarioStep(48, 'Asystole', (s) => s.setRhythm('asystole')),
  ]),

  Scenario('svt', 'SVT and adenosine', 'Narrow-complex tachycardia, a long pause, then sinus. About 1 minute.', [
    ScenarioStep(0, 'SVT at 196', (s) {
      _baseline(s);
      s.setRhythm('svt', bpm: 196);
      s.setBp(96, 62, over: 5);
      s.spo2.set(96, 5);
      s.respRate.set(22, 5);
    }),
    ScenarioStep(35, 'Adenosine given - pause', (s) => s.setRhythm('asystole')),
    ScenarioStep(40.5, 'A few escape beats', (s) => s.setRhythm('pvc_freq', bpm: 54)),
    ScenarioStep(48, 'Sinus rhythm', (s) {
      s.setRhythm('nsr', bpm: 92);
      s.setRate(80, over: 20);
      s.setBp(118, 74, over: 12);
      s.respRate.set(16, 10);
    }),
  ]),

  Scenario('afib', 'Rapid A-fib', 'Fast and irregular, slowed with medication, then cardioverted. About 1½ minutes.', [
    ScenarioStep(0, 'A-fib with RVR', (s) {
      _baseline(s);
      s.setRhythm('afib_rvr', bpm: 152);
      s.setBp(98, 60, over: 5);
      s.spo2.set(95, 5);
      s.respRate.set(20, 5);
    }),
    ScenarioStep(30, 'Rate control working', (s) {
      s.setRate(92, over: 30);
      s.setBp(112, 70, over: 30);
    }),
    ScenarioStep(75, 'Synchronized cardioversion', (s) => s.shock(then: 'nsr', rate: 78)),
    ScenarioStep(80, 'Sinus rhythm', (s) {
      s.setBp(120, 76, over: 10);
      s.respRate.set(15, 10);
    }),
  ]),

  Scenario(
    'asthma',
    'Severe asthma',
    'Shark-fin capnogram, falling sats, then responds to treatment. About 2 minutes.',
    [
      ScenarioStep(0, 'Bronchospasm', (s) {
        _baseline(s);
        s.setRhythm('sinus_tach', bpm: 116);
        s.setRate(132, over: 40);
        s.obstruction.set(0.75, 15);
        s.respRate.set(30, 10);
        s.spo2.set(88, 40);
        s.etco2.set(52, 40);
        s.setBp(146, 90, over: 10);
        s.paSys.set(40, 40);
        s.paDia.set(18, 40);
      }),
      ScenarioStep(60, 'Tiring', (s) {
        s.respRate.set(34, 10);
        s.spo2.set(84, 15);
        s.etco2.set(60, 20);
      }),
      ScenarioStep(80, 'Nebulizer and oxygen', (s) {
        s.obstruction.set(0.2, 35);
        s.spo2.set(96, 30);
        s.etco2.set(40, 35);
        s.respRate.set(20, 35);
        s.setRate(108, over: 40);
        s.setBp(128, 80, over: 30);
        s.paSys.set(28, 40);
        s.paDia.set(11, 40);
      }),
    ],
  ),

  Scenario('overdose', 'Opioid overdose', 'Breathing slows to nothing, sats fall, then naloxone. About 1½ minutes.', [
    ScenarioStep(0, 'Slow, shallow breathing', (s) {
      _baseline(s);
      s.setRhythm('sinus_brady', bpm: 58);
      s.setRate(48, over: 30);
      s.respRate.set(5, 12);
      s.etco2.set(64, 30);
      s.spo2.set(86, 35);
      s.setBp(96, 58, over: 20);
      s.bis.set(62, 25);
    }),
    ScenarioStep(34, 'Apnea', (s) {
      s.setVent(VentMode.none);
      s.spo2.set(74, 25);
      s.bis.set(48, 20);
    }),
    ScenarioStep(62, 'Naloxone', (s) {
      s.setVent(VentMode.spontaneous);
      s.respRate.set(18, 6);
      s.etco2.set(40, 20);
      s.spo2.set(98, 20);
      s.setRhythm('sinus_tach', bpm: 60);
      s.setRate(104, over: 15);
      s.setBp(134, 84, over: 15);
      s.bis.set(95, 12);
    }),
  ]),

  Scenario('sepsis', 'Septic shock', 'Fast heart, low pressure, fever, quick breathing.', [
    ScenarioStep(0, 'Septic shock', (s) {
      _baseline(s);
      s.setRhythm('sinus_tach', bpm: 112);
      s.setRate(128, over: 30);
      s.setBp(84, 44, over: 30);
      s.temp.set(39.4, 30);
      s.respRate.set(28, 15);
      s.spo2.set(92, 25);
      s.etco2.set(27, 30);
      s.cvp.set(3, 30);
    }),
  ]),

  Scenario('bleed', 'Hemorrhagic shock', 'Pressure falls as the rate climbs, ending in PEA. About 2 minutes.', [
    ScenarioStep(0, 'Compensating', (s) {
      _baseline(s);
      s.setRhythm('sinus_tach', bpm: 108);
      s.setRate(138, over: 70);
      s.setBp(104, 76, over: 30);
      s.respRate.set(24, 20);
      s.spo2.set(95, 20);
      s.cvp.set(3, 40);
    }),
    ScenarioStep(45, 'Decompensating', (s) {
      s.setBp(72, 50, over: 30);
      s.etco2.set(26, 30);
      s.spo2.set(90, 30);
    }),
    ScenarioStep(95, 'Peri-arrest', (s) {
      s.setRate(60, over: 14);
      s.setBp(46, 30, over: 12);
    }),
    ScenarioStep(112, 'PEA', (s) => s.setRhythm('pea', bpm: 52)),
  ]),

  Scenario('pacing', 'Heart block and pacing', 'Complete heart block, then a pacemaker takes over. About 1 minute.', [
    ScenarioStep(0, 'Complete heart block', (s) {
      _baseline(s);
      s.setRhythm('avb3', bpm: 34);
      s.setBp(82, 42, over: 6);
      s.spo2.set(94, 6);
    }),
    ScenarioStep(30, 'Pacing, not capturing yet', (s) => s.setRhythm('paced_fail', bpm: 70)),
    ScenarioStep(46, 'Capture', (s) {
      s.setRhythm('paced_v', bpm: 70);
      s.setBp(116, 70, over: 12);
      s.spo2.set(98, 15);
    }),
  ]),

  Scenario('head', 'Head injury', 'ICP climbs, then pressure up and pulse down (Cushing response). About 1½ minutes.', [
    ScenarioStep(0, 'Rising intracranial pressure', (s) {
      _baseline(s);
      s.setRhythm('nsr', bpm: 84);
      s.icp.set(26, 35);
      s.bis.set(70, 40);
      s.setBp(138, 80, over: 30);
    }),
    ScenarioStep(40, 'Cushing response', (s) {
      s.icp.set(42, 30);
      s.setRhythm('sinus_brady', bpm: 78);
      s.setRate(44, over: 30);
      s.setBp(196, 92, over: 30);
      s.respRate.set(8, 30);
      s.bis.set(38, 30);
    }),
  ]),

  Scenario('exercise', 'Just ran up the stairs', 'Sinus tachycardia that settles over a minute and a half.', [
    ScenarioStep(0, 'Recovering', (s) {
      _baseline(s);
      s.setRhythm('nsr', bpm: 142);
      s.setRate(78, over: 85);
      s.setBp(158, 82, over: 2);
      s.respRate.set(28, 2);
    }),
    ScenarioStep(3, 'Recovering', (s) {
      s.setBp(124, 78, over: 70);
      s.respRate.set(15, 70);
    }),
  ]),
];
