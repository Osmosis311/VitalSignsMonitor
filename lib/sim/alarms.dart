/// Alarm priorities, in the order a monitor ranks them.
enum AlarmPriority { high, medium, technical }

/// Which numeric an alarm belongs to, so the right tile can flash.
enum Param { hr, spo2, abp, pap, cvp, icp, nibp, co2, resp, temp, none }

class Alarm {
  Alarm(this.id, this.text, this.priority, this.param, this.since);
  final String id;
  final String text;
  final AlarmPriority priority;
  final Param param;
  final double since;
  bool acked = false;

  /// Simulation time after which a one-off alarm clears itself.
  double? until;

  /// IEC 60601-1-8 style priority marker.
  String get marked => switch (priority) {
    AlarmPriority.high => '!!! $text',
    AlarmPriority.medium => '!! $text',
    AlarmPriority.technical => text,
  };
}

enum LimitKey { hr, spo2, abpSys, papSys, cvp, icp, cpp, nibpSys, etco2, awrr, temp }

class Limit {
  Limit(this.label, this.unit, this.lo, this.hi, this.min, this.max, {this.step = 1, this.decimals = 0});
  final String label;
  final String unit;
  double lo;
  double hi;
  final double min;
  final double max;
  final double step;
  final int decimals;

  String fmt(double v) => v.toStringAsFixed(decimals);
}

/// Adult default alarm limits.
Map<LimitKey, Limit> defaultLimits() => {
  LimitKey.hr: Limit('HR', 'bpm', 50, 120, 20, 250, step: 5),
  LimitKey.spo2: Limit('SpO₂', '%', 90, 100, 50, 100),
  LimitKey.abpSys: Limit('ABP sys', 'mmHg', 90, 160, 30, 260, step: 5),
  LimitKey.papSys: Limit('PAP sys', 'mmHg', 10, 35, 0, 100),
  LimitKey.cvp: Limit('CVP', 'mmHg', 0, 15, -5, 40),
  LimitKey.icp: Limit('ICP', 'mmHg', 0, 20, -5, 80),
  LimitKey.cpp: Limit('CPP', 'mmHg', 60, 130, 20, 180, step: 5),
  LimitKey.nibpSys: Limit('NIBP sys', 'mmHg', 90, 160, 30, 260, step: 5),
  LimitKey.etco2: Limit('etCO₂', 'mmHg', 30, 50, 5, 90),
  LimitKey.awrr: Limit('awRR', 'rpm', 8, 30, 2, 60),
  LimitKey.temp: Limit('Temp', '°C', 36.0, 39.0, 30, 42, step: 0.1, decimals: 1),
};
