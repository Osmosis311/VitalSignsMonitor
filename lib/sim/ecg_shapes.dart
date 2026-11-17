/// Beat morphology tables for the ECG synthesiser.
///
/// Every deflection is an asymmetric Gaussian with one amplitude (in mV) for
/// each of the eight independent leads. The remaining limb leads (III, aVR,
/// aVL, aVF) are derived from I and II, so the twelve leads always agree with
/// each other the way they do on a real recording.
library;

/// Independent lead order used by every amplitude list in this file.
/// `[I, II, V1, V2, V3, V4, V5, V6]`
const int kBaseLeads = 8;

enum Lead { i, ii, iii, avr, avl, avf, v1, v2, v3, v4, v5, v6 }

const Map<Lead, String> kLeadNames = {
  Lead.i: 'I',
  Lead.ii: 'II',
  Lead.iii: 'III',
  Lead.avr: 'aVR',
  Lead.avl: 'aVL',
  Lead.avf: 'aVF',
  Lead.v1: 'V1',
  Lead.v2: 'V2',
  Lead.v3: 'V3',
  Lead.v4: 'V4',
  Lead.v5: 'V5',
  Lead.v6: 'V6',
};

/// Value of [lead] given the eight base-lead values.
double mixLead(Lead lead, double Function(int) b) {
  switch (lead) {
    case Lead.i:
      return b(0);
    case Lead.ii:
      return b(1);
    case Lead.iii:
      return b(1) - b(0);
    case Lead.avr:
      return -(b(0) + b(1)) / 2;
    case Lead.avl:
      return b(0) - b(1) / 2;
    case Lead.avf:
      return b(1) - b(0) / 2;
    case Lead.v1:
      return b(2);
    case Lead.v2:
      return b(3);
    case Lead.v3:
      return b(4);
    case Lead.v4:
      return b(5);
    case Lead.v5:
      return b(6);
    case Lead.v6:
      return b(7);
  }
}

/// One deflection: centre time [t] (s), left/right width [sl]/[sr] (s) and
/// per-lead amplitudes [a] (mV).
class Wv {
  const Wv(this.t, this.sl, this.sr, this.a);
  final double t, sl, sr;
  final List<double> a;

  Wv scaled(double k) => Wv(t, sl, sr, [for (final v in a) v * k]);
  Wv widened(double k) => Wv(t * k, sl * k, sr * k, a);
}

/// A ventricular complex.
///
/// [qrs] deflections are placed at fixed offsets from the R point. [t]
/// deflections are written for a 1 s R-R interval and are pulled earlier and
/// narrowed as the rate rises, which is what keeps the QT interval believable
/// from 30 to 220 bpm.
class BeatShape {
  const BeatShape({required this.qrs, required this.t, this.wide = false, this.st});
  final List<Wv> qrs;
  final List<Wv> t;
  final bool wide;

  /// ST deviation per base lead in mV, when the shape has any.
  final List<double>? st;
}

// ---------------------------------------------------------------- P waves --

const List<Wv> kPNormal = [
  Wv(0, .024, .024, [.06, .12, .035, .045, .05, .05, .05, .045]),
  Wv(.03, .014, .016, [0, 0, -.035, 0, 0, 0, 0, 0]),
];

/// Ectopic atrial focus: small, partly inverted.
const List<Wv> kPEctopic = [
  Wv(0, .02, .022, [.03, -.06, .05, .03, .02, .02, .02, .02]),
];

/// Retrograde P wave (junctional / re-entrant rhythms).
const List<Wv> kPRetro = [
  Wv(0, .018, .02, [-.02, -.11, .05, .02, 0, -.02, -.03, -.03]),
];

/// Atrial-paced P wave.
const List<Wv> kPPaced = [
  Wv(0, .028, .03, [.05, .09, .03, .04, .04, .04, .04, .04]),
];

// ------------------------------------------------------------ Narrow QRS --

const List<Wv> _qrsNormal = [
  Wv(-.024, .007, .007, [-.03, -.07, 0, 0, 0, -.03, -.07, -.07]),
  Wv(0, .0095, .0095, [.62, 1.15, 0, 0, 0, 1.55, 1.35, 1.0]),
  Wv(-.012, .008, .008, [0, 0, .2, .42, .85, 0, 0, 0]),
  Wv(.014, .011, .012, [0, 0, -.95, -1.55, -1.05, 0, 0, 0]),
  Wv(.027, .009, .010, [-.09, -.17, 0, 0, 0, -.5, -.22, -.08]),
];

const List<Wv> _tNormal = [
  Wv(.27, .062, .04, [.17, .27, -.04, .33, .4, .4, .3, .2]),
];

const BeatShape kNormal = BeatShape(qrs: _qrsNormal, t: _tNormal);

/// Normal conduction with a flatter T wave, used where the baseline is busy
/// (flutter, fibrillation) so the atrial activity stays readable.
const BeatShape kNormalSmallT = BeatShape(
  qrs: _qrsNormal,
  t: [
    Wv(.27, .062, .04, [.09, .13, -.02, .16, .2, .2, .15, .1]),
  ],
);

List<double> _stInferior = const [-.08, .28, -.05, -.12, -.08, 0, .03, .05];
List<double> _stAnterior = const [.05, -.04, .15, .38, .42, .3, .1, .02];
List<double> _stLateral = const [.2, .06, -.03, -.05, 0, .05, .2, .2];

BeatShape _stemi(List<double> st, List<double> tGain) => BeatShape(
  qrs: [
    ..._qrsNormal,
    Wv(.05, .014, .05, [for (final v in st) v * .55]),
  ],
  t: [
    Wv(.15, .06, .07, [for (final v in st) v * .8]),
    Wv(.275, .07, .045, [for (var i = 0; i < kBaseLeads; i++) _tNormal[0].a[i] * tGain[i]]),
  ],
  st: st,
);

final BeatShape kStemiInferior = _stemi(_stInferior, const [.8, 1.3, 1, 1, 1, 1, 1, 1]);
final BeatShape kStemiAnterior = _stemi(_stAnterior, const [1, .9, -2, 1.5, 1.6, 1.5, 1.1, 1]);
final BeatShape kStemiLateral = _stemi(_stLateral, const [1.5, 1, 1, 1, 1, 1, 1.4, 1.5]);

/// Subendocardial ischaemia: horizontal ST depression with flattened T waves.
final BeatShape kIschemia = BeatShape(
  qrs: [
    ..._qrsNormal,
    const Wv(.058, .016, .045, [-.08, -.14, 0, -.05, -.12, -.2, -.2, -.15]),
  ],
  t: const [
    Wv(.13, .05, .08, [-.1, -.17, 0, -.06, -.14, -.22, -.22, -.17]),
    Wv(.28, .062, .04, [.08, .12, -.02, .16, .18, .16, .12, .08]),
  ],
  st: const [-.1, -.17, 0, -.06, -.14, -.22, -.22, -.17],
);

/// Hyperkalaemia: broad QRS and tall, narrow "tented" T waves.
final BeatShape kHyperK = BeatShape(
  qrs: [for (final w in _qrsNormal) w.widened(1.55)],
  t: const [
    Wv(.25, .034, .03, [.4, .75, .1, .9, 1.1, 1.0, .75, .5]),
  ],
  wide: true,
);

/// Pre-excitation: slurred delta wave ahead of the QRS.
const BeatShape kWpw = BeatShape(
  qrs: [
    Wv(-.05, .022, .014, [.2, .32, .1, .22, .32, .42, .36, .26]),
    ..._qrsNormal,
  ],
  t: [
    Wv(.28, .062, .04, [.1, .14, -.08, .15, .2, .2, .15, .1]),
  ],
);

const BeatShape kLbbb = BeatShape(
  qrs: [
    Wv(-.005, .014, .016, [.5, .55, .04, .06, .1, .35, .6, .6]),
    Wv(.045, .02, .024, [.6, .5, 0, 0, 0, .4, .8, .8]),
    Wv(.03, .03, .035, [0, 0, -1.3, -1.9, -1.4, -.5, 0, 0]),
  ],
  t: [
    Wv(.3, .07, .05, [-.22, -.12, .3, .5, .4, .1, -.22, -.22]),
  ],
  wide: true,
);

const BeatShape kRbbb = BeatShape(
  qrs: [
    Wv(-.024, .007, .007, [-.03, -.06, 0, 0, 0, -.03, -.06, -.06]),
    Wv(0, .0095, .0095, [.55, 1.0, 0, 0, 0, 1.3, 1.2, .9]),
    Wv(-.01, .008, .008, [0, 0, .22, .4, .7, 0, 0, 0]),
    Wv(.014, .01, .011, [0, 0, -.35, -.8, -.7, 0, 0, 0]),
    Wv(.06, .016, .02, [0, 0, .85, .6, .2, 0, 0, 0]),
    Wv(.058, .018, .024, [-.33, -.3, 0, 0, 0, -.35, -.4, -.35]),
  ],
  t: [
    Wv(.27, .062, .04, [.17, .25, -.2, -.12, .2, .35, .3, .2]),
  ],
  wide: true,
);

// -------------------------------------------------------- Ventricular QRS --

/// Ectopic beat from the right ventricle (left-bundle pattern).
const BeatShape kPvcA = BeatShape(
  qrs: [
    Wv(0, .03, .04, [.4, 1.3, -1.0, -1.35, -.65, .45, 1.0, 1.05]),
    Wv(.085, .028, .03, [-.12, -.35, .2, .3, .15, -.1, -.2, -.25]),
  ],
  t: [
    Wv(.3, .075, .06, [-.18, -.5, .38, .55, .35, -.18, -.38, -.4]),
  ],
  wide: true,
);

/// Ectopic beat from the left ventricle (right-bundle pattern).
const BeatShape kPvcB = BeatShape(
  qrs: [
    Wv(0, .03, .04, [-.5, -1.3, 1.2, 1.0, .4, -.5, -.9, -1.0]),
    Wv(.085, .028, .03, [.15, .3, -.25, -.2, -.1, .1, .2, .2]),
  ],
  t: [
    Wv(.3, .075, .06, [.2, .45, -.4, -.35, -.15, .2, .32, .35]),
  ],
  wide: true,
);

/// Monomorphic VT: the complex and its recovery wave run together.
const BeatShape kVt = BeatShape(
  qrs: [
    Wv(0, .042, .05, [.4, 1.35, -1.0, -1.3, -.6, .4, .9, 1.0]),
    Wv(.165, .05, .05, [-.3, -.95, .75, .95, .4, -.3, -.65, -.7]),
  ],
  t: [],
  wide: true,
);

/// Slow ventricular escape focus.
const BeatShape kEscape = BeatShape(
  qrs: [
    Wv(0, .036, .046, [.4, 1.25, -1.0, -1.3, -.6, .45, .95, 1.0]),
    Wv(.1, .03, .034, [-.1, -.3, .2, .25, .12, -.1, -.18, -.2]),
  ],
  t: [
    Wv(.34, .085, .07, [-.16, -.42, .32, .45, .3, -.15, -.32, -.34]),
  ],
  wide: true,
);

/// Dying heart: low, broad, shapeless complexes.
const BeatShape kAgonal = BeatShape(
  qrs: [
    Wv(0, .07, .09, [.18, .5, -.3, -.4, -.2, .2, .35, .4]),
    Wv(.24, .09, .1, [-.1, -.28, .18, .22, .1, -.1, -.2, -.22]),
  ],
  t: [],
  wide: true,
);

/// Right-ventricular paced complex; the fiducial point is the pacing spike.
const BeatShape kPacedV = BeatShape(
  qrs: [
    Wv(.02, .012, .012, [.1, -.2, -.2, -.3, -.3, -.2, -.1, -.05]),
    Wv(.075, .032, .05, [.5, -1.05, -1.25, -1.6, -1.5, -1.2, -.8, -.4]),
  ],
  t: [
    Wv(.34, .07, .06, [-.15, .42, .42, .6, .55, .45, .3, .15]),
  ],
  wide: true,
);
