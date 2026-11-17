import 'alarms.dart';
import 'ecg_engine.dart';
import 'ecg_shapes.dart';

/// One entry in the hidden rhythm list.
class RhythmDef {
  RhythmDef(
    this.id,
    this.name,
    this.group,
    this.rate,
    this.build, {
    this.minRate = 30,
    this.maxRate = 200,
    this.fixedRate = false,
    this.pulseless = false,
    this.shockable = false,
    this.alarm,
    this.alarmPriority = AlarmPriority.medium,
    this.alarmDelay = 6,
    this.shape,
  });

  final String id;
  final String name;
  final String group;

  /// Rate it starts at when picked from the list.
  final int rate;
  final int minRate;
  final int maxRate;

  /// True when the rhythm sets its own rate (flutter, VF, asystole).
  final bool fixedRate;
  final bool pulseless;
  final bool shockable;

  /// Arrhythmia message the monitor raises once it has "recognised" it.
  final String? alarm;
  final AlarmPriority alarmPriority;
  final double alarmDelay;

  /// Conducted-beat shape, used for the ST readout.
  final BeatShape? shape;

  final RhythmGen Function(EcgEngine) build;
}

const String gSinus = 'Sinus';
const String gAtrial = 'Atrial';
const String gJunctional = 'Junctional';
const String gBlocks = 'AV blocks';
const String gConduction = 'Conduction & ST';
const String gEctopy = 'Ventricular ectopy';
const String gVentricular = 'Ventricular rhythms';
const String gArrest = 'Cardiac arrest';
const String gPaced = 'Paced';

RhythmDef _sinus(
  String id,
  String name,
  String group,
  int rate, {
  BeatShape shape = kNormal,
  double pr = 0.16,
  double rsa = 0.035,
  Ectopy ectopy = Ectopy.none,
  AvBlock block = AvBlock.none,
  double strength = 1,
  double pGain = 1,
  String? alarm,
  AlarmPriority priority = AlarmPriority.medium,
  double alarmDelay = 6,
  bool pulseless = false,
}) => RhythmDef(
  id,
  name,
  group,
  rate,
  (e) => SinusGen(e, shape: shape, pr: pr, rsa: rsa, ectopy: ectopy, block: block, strength: strength, pGain: pGain),
  alarm: alarm,
  alarmPriority: priority,
  alarmDelay: alarmDelay,
  pulseless: pulseless,
  shape: shape,
);

final List<RhythmDef> kRhythms = [
  // Sinus
  _sinus('nsr', 'Normal sinus rhythm', gSinus, 72),
  _sinus('sinus_brady', 'Sinus bradycardia', gSinus, 46),
  _sinus('sinus_tach', 'Sinus tachycardia', gSinus, 128),
  _sinus('sinus_arr', 'Sinus arrhythmia', gSinus, 66, rsa: 0.17),
  _sinus('sinus_pac', 'Sinus with PACs', gSinus, 74, ectopy: Ectopy.pac),

  // Atrial
  RhythmDef(
    'afib',
    'Atrial fibrillation',
    gAtrial,
    86,
    (e) => AfibGen(e),
    shockable: true,
    alarm: 'A-FIB',
    alarmDelay: 10,
  ),
  RhythmDef(
    'afib_rvr',
    'A-fib with rapid ventricular response',
    gAtrial,
    148,
    (e) => AfibGen(e, strength: 0.8),
    shockable: true,
    alarm: 'A-FIB',
    alarmDelay: 10,
  ),
  RhythmDef(
    'flutter_4',
    'Atrial flutter 4:1',
    gAtrial,
    75,
    (e) => FlutterGen(e, ratio: 4),
    fixedRate: true,
    shockable: true,
  ),
  RhythmDef(
    'flutter_2',
    'Atrial flutter 2:1',
    gAtrial,
    150,
    (e) => FlutterGen(e, ratio: 2),
    fixedRate: true,
    shockable: true,
  ),
  RhythmDef(
    'flutter_var',
    'Atrial flutter, variable block',
    gAtrial,
    95,
    (e) => FlutterGen(e, ratio: 0),
    fixedRate: true,
    shockable: true,
    alarm: 'IRREGULAR HR',
    alarmDelay: 12,
  ),
  RhythmDef(
    'svt',
    'SVT',
    gAtrial,
    188,
    (e) => RegularGen(e, shape: kNormal, kind: BeatKind.normal, p: PMode.retroAfter, jitter: 0.004, strength: 0.7),
    minRate: 140,
    maxRate: 250,
    shockable: true,
    alarm: 'SVT',
    alarmDelay: 4,
  ),
  _sinus('wpw', 'WPW (pre-excitation)', gAtrial, 76, shape: kWpw, pr: 0.09),

  // Junctional
  RhythmDef(
    'junctional',
    'Junctional rhythm',
    gJunctional,
    48,
    (e) => RegularGen(e, shape: kNormal, kind: BeatKind.junctional, p: PMode.invertedBefore),
    minRate: 30,
    maxRate: 130,
  ),
  RhythmDef(
    'junctional_acc',
    'Accelerated junctional rhythm',
    gJunctional,
    84,
    (e) => RegularGen(e, shape: kNormal, kind: BeatKind.junctional),
    minRate: 30,
    maxRate: 130,
  ),

  // AV blocks
  _sinus('avb1', '1st-degree AV block', gBlocks, 68, block: AvBlock.first),
  _sinus(
    'avb2_1',
    '2nd-degree AV block, type I (Wenckebach)',
    gBlocks,
    74,
    block: AvBlock.wenckebach,
    rsa: 0.01,
    alarm: 'IRREGULAR HR',
    alarmDelay: 12,
  ),
  _sinus(
    'avb2_2',
    '2nd-degree AV block, type II',
    gBlocks,
    72,
    block: AvBlock.mobitz2,
    shape: kRbbb,
    rsa: 0.01,
    alarm: 'IRREGULAR HR',
    alarmDelay: 12,
  ),
  RhythmDef(
    'avb3',
    '3rd-degree (complete) AV block',
    gBlocks,
    36,
    (e) => CompleteBlockGen(e),
    minRate: 20,
    maxRate: 60,
    alarm: 'VENT RHYTHM',
    alarmDelay: 8,
  ),

  // Conduction and ST changes
  _sinus('lbbb', 'Left bundle branch block', gConduction, 74, shape: kLbbb),
  _sinus('rbbb', 'Right bundle branch block', gConduction, 74, shape: kRbbb),
  _sinus('stemi_inf', 'Inferior STEMI', gConduction, 64, shape: kStemiInferior),
  _sinus('stemi_ant', 'Anterior STEMI', gConduction, 96, shape: kStemiAnterior),
  _sinus('stemi_lat', 'Lateral STEMI', gConduction, 88, shape: kStemiLateral),
  _sinus('ischemia', 'ST depression (ischemia)', gConduction, 104, shape: kIschemia),
  _sinus('hyperk', 'Hyperkalemia (peaked T waves)', gConduction, 62, shape: kHyperK, pr: 0.22, pGain: 0.35),

  // Ventricular ectopy
  _sinus('pvc_occ', 'Sinus with occasional PVCs', gEctopy, 76, ectopy: Ectopy.pvcOccasional),
  _sinus('pvc_freq', 'Sinus with frequent PVCs', gEctopy, 80, ectopy: Ectopy.pvcFrequent),
  _sinus(
    'pvc_multi',
    'Multifocal PVCs',
    gEctopy,
    82,
    ectopy: Ectopy.multifocal,
    alarm: 'MULTIFORM PVCs',
    alarmDelay: 14,
  ),
  _sinus('bigeminy', 'Ventricular bigeminy', gEctopy, 76, ectopy: Ectopy.bigeminy, alarm: 'VENT BIGEMINY'),
  _sinus(
    'trigeminy',
    'Ventricular trigeminy',
    gEctopy,
    78,
    ectopy: Ectopy.trigeminy,
    alarm: 'VENT TRIGEMINY',
    alarmDelay: 8,
  ),
  _sinus('couplets', 'PVC couplets', gEctopy, 78, ectopy: Ectopy.couplets),
  _sinus('nsvt', 'Runs of non-sustained VT', gEctopy, 84, ectopy: Ectopy.runs),

  // Ventricular rhythms
  RhythmDef(
    'idio',
    'Idioventricular rhythm',
    gVentricular,
    34,
    (e) => RegularGen(e, shape: kEscape, kind: BeatKind.escape, strength: 0.75),
    minRate: 15,
    maxRate: 50,
    alarm: 'VENT RHYTHM',
  ),
  RhythmDef(
    'aivr',
    'Accelerated idioventricular rhythm',
    gVentricular,
    78,
    (e) => RegularGen(e, shape: kEscape, kind: BeatKind.escape, strength: 0.8),
    minRate: 50,
    maxRate: 110,
    alarm: 'VENT RHYTHM',
  ),
  RhythmDef(
    'vt',
    'Ventricular tachycardia (with pulse)',
    gVentricular,
    168,
    (e) => RegularGen(e, shape: kVt, kind: BeatKind.ventricular, jitter: 0.006, strength: 0.42),
    minRate: 110,
    maxRate: 250,
    shockable: true,
    alarm: 'V-TACH',
    alarmPriority: AlarmPriority.high,
    alarmDelay: 2.5,
  ),
  RhythmDef(
    'torsades',
    'Torsades de pointes',
    gVentricular,
    230,
    (e) => ChaoticGen(e, Chaos.torsades),
    fixedRate: true,
    pulseless: true,
    shockable: true,
    alarm: 'V-TACH',
    alarmPriority: AlarmPriority.high,
    alarmDelay: 2.5,
  ),

  // Cardiac arrest
  RhythmDef(
    'vt_pulseless',
    'Pulseless ventricular tachycardia',
    gArrest,
    196,
    (e) => RegularGen(e, shape: kVt, kind: BeatKind.ventricular, jitter: 0.006, strength: 0),
    minRate: 130,
    maxRate: 280,
    pulseless: true,
    shockable: true,
    alarm: 'V-TACH',
    alarmPriority: AlarmPriority.high,
    alarmDelay: 2.5,
  ),
  RhythmDef(
    'vf_coarse',
    'Ventricular fibrillation (coarse)',
    gArrest,
    0,
    (e) => ChaoticGen(e, Chaos.vfCoarse),
    fixedRate: true,
    pulseless: true,
    shockable: true,
    alarm: 'V-FIB',
    alarmPriority: AlarmPriority.high,
    alarmDelay: 3,
  ),
  RhythmDef(
    'vf_fine',
    'Ventricular fibrillation (fine)',
    gArrest,
    0,
    (e) => ChaoticGen(e, Chaos.vfFine),
    fixedRate: true,
    pulseless: true,
    shockable: true,
    alarm: 'V-FIB',
    alarmPriority: AlarmPriority.high,
    alarmDelay: 3,
  ),
  RhythmDef('asystole', 'Asystole', gArrest, 0, (e) => ChaoticGen(e, Chaos.asystole), fixedRate: true, pulseless: true),
  RhythmDef('agonal', 'Agonal rhythm', gArrest, 14, (e) => AgonalGen(e), minRate: 6, maxRate: 30, pulseless: true),
  _sinus('pea', 'PEA (organized rhythm, no pulse)', gArrest, 58, strength: 0, pulseless: true),

  // Paced
  RhythmDef('paced_a', 'Atrial paced', gPaced, 70, (e) => PacedGen(e, PaceMode.atrial), minRate: 40, maxRate: 150),
  RhythmDef(
    'paced_v',
    'Ventricular paced',
    gPaced,
    70,
    (e) => PacedGen(e, PaceMode.ventricular),
    minRate: 40,
    maxRate: 150,
  ),
  RhythmDef(
    'paced_av',
    'AV sequential paced',
    gPaced,
    70,
    (e) => PacedGen(e, PaceMode.dual),
    minRate: 40,
    maxRate: 150,
  ),
  RhythmDef(
    'paced_fail',
    'Pacemaker, failure to capture',
    gPaced,
    70,
    (e) => PacedGen(e, PaceMode.failing),
    minRate: 40,
    maxRate: 150,
  ),
];

RhythmDef rhythmById(String id) => kRhythms.firstWhere((r) => r.id == id, orElse: () => kRhythms.first);
