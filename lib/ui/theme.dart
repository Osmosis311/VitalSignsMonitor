import 'package:flutter/widgets.dart';

import '../sim/alarms.dart';

/// Trace and numeric colours, following the conventions bedside monitors
/// share: green ECG, cyan SpO₂, red arterial pressure, yellow respiration.
abstract final class MC {
  static const bg = Color(0xFF000000);
  static const ecg = Color(0xFF2BEA4B);
  static const spo2 = Color(0xFF19E3F5);
  static const abp = Color(0xFFFF3B36);
  static const nibp = Color(0xFFF58BFF);
  static const co2 = Color(0xFFF2F2F2);
  static const resp = Color(0xFFFFE51F);
  static const temp = Color(0xFFFFA630);
  static const pap = Color(0xFFFFD60A);
  static const cvp = Color(0xFF5AA2FF);
  static const icp = Color(0xFFB49CFF);
  static const eeg = Color(0xFFE6C36A);
  static const cco = Color(0xFFFF9E8A);
  static const nmt = Color(0xFF9AD1D4);

  static const alarmRed = Color(0xFFFF1E1E);
  static const alarmYellow = Color(0xFFFFE600);
  static const alarmCyan = Color(0xFF3FE0F5);

  static const bar = Color(0xFF17212B);
  static const barLine = Color(0xFF34424F);
  static const field = Color(0xFF0C1218);
  static const text = Color(0xFFE6EDF3);
  static const dim = Color(0xFF8FA0AF);
  static const key = Color(0xFF3B4B5B);
  static const keyHi = Color(0xFF54687C);
  static const keyLo = Color(0xFF25313D);
  static const keyOn = Color(0xFFBFD4E6);
  static const window = Color(0xFF1B2733);
  static const windowTitle = Color(0xFF2E4A66);
  static const select = Color(0xFF2D6CB0);

  static Color alarm(AlarmPriority p) => switch (p) {
    AlarmPriority.high => alarmRed,
    AlarmPriority.medium => alarmYellow,
    AlarmPriority.technical => alarmCyan,
  };

  static Color onAlarm(AlarmPriority p) => p == AlarmPriority.high ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
}

/// Labels, units and menu text.
TextStyle labelStyle(double size, Color color, {double weight = 500, double width = 88}) => TextStyle(
  fontFamily: 'RobotoVariable',
  fontSize: size,
  color: color,
  height: 1.05,
  fontVariations: [FontVariation('wght', weight), FontVariation('wdth', width)],
  decoration: TextDecoration.none,
);

/// The big measured values.
TextStyle numericStyle(double size, Color color) => TextStyle(
  fontFamily: 'Nimbus',
  fontSize: size,
  color: color,
  height: 0.92,
  letterSpacing: -size * 0.025,
  fontFeatures: const [FontFeature.tabularFigures()],
  decoration: TextDecoration.none,
);

/// Size multiplier for the whole screen, so the layout holds its proportions
/// from a phone to a desktop window.
class Scale extends InheritedWidget {
  const Scale({super.key, required this.s, required super.child});
  final double s;

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<Scale>()?.s ?? 1;

  @override
  bool updateShouldNotify(Scale oldWidget) => oldWidget.s != s;
}
