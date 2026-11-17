import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sim/ecg_shapes.dart';

/// Which arrangement of the screen is showing.
enum ScreenLayout { full, standard, big, trends, review }

const Map<ScreenLayout, String> kLayoutNames = {
  ScreenLayout.full: 'ICU full',
  ScreenLayout.standard: 'Standard',
  ScreenLayout.big: 'Big numbers',
  ScreenLayout.trends: 'Graphical trends',
  ScreenLayout.review: 'ST and events',
};

/// How the monitor is set up. Saved between launches so a prop only has to
/// be configured once.
class MonitorSettings extends ChangeNotifier {
  String bedLabel = 'BED 4';
  String patientName = '';
  String category = 'Adult';

  /// Age, sex and weight as one line for the information bar.
  String patientInfo = '58 y   M   82 kg';

  ScreenLayout layout = ScreenLayout.full;

  Lead ecg1 = Lead.ii;
  Lead ecg2 = Lead.v1;
  bool showEcg2 = true;
  bool showAbp = true;
  bool showCo2 = true;
  bool showResp = false;
  bool showPap = false;
  bool showCvp = false;
  bool showIcp = false;
  bool showEeg = false;

  /// Small trend graphs between the waves and the numbers.
  bool showMiniTrends = true;

  /// The lower rows: temperatures, cardiac output, TOF, ST, infusions.
  bool showExtras = true;

  // What is actually on screen: the ICU layout turns everything on, the
  // others follow the switches above.
  bool get _all => layout == ScreenLayout.full;
  bool get ecg2On => _all || showEcg2;
  bool get abpOn => layout != ScreenLayout.standard || showAbp;
  bool get co2On => layout != ScreenLayout.standard || showCo2;
  bool get respOn => _all || showResp;
  bool get papOn => _all || showPap;
  bool get cvpOn => _all || showCvp;
  bool get icpOn => _all || showIcp;
  bool get eegOn => _all || showEeg;
  bool get miniTrendsOn => _all || (layout == ScreenLayout.standard && showMiniTrends);
  bool get extrasOn => _all || (layout == ScreenLayout.standard && showExtras);

  /// ECG trace size multiplier.
  double ecgGain = 1;

  /// Sweep speed in mm/s for the cardiac traces.
  double sweep = 25;

  /// 0 (off) to 5.
  int qrsVolume = 2;
  int alarmVolume = 3;

  bool fahrenheit = false;

  /// The small DEMO tag in the status bar.
  bool showDemoTag = true;

  static const _key = 'monitor_settings_v2';

  void update(VoidCallback change) {
    change();
    notifyListeners();
    save();
  }

  Map<String, dynamic> toJson() => {
    'bedLabel': bedLabel,
    'patientName': patientName,
    'category': category,
    'patientInfo': patientInfo,
    'layout': layout.name,
    'showPap': showPap,
    'showCvp': showCvp,
    'showIcp': showIcp,
    'showEeg': showEeg,
    'showMiniTrends': showMiniTrends,
    'showExtras': showExtras,
    'ecg1': ecg1.name,
    'ecg2': ecg2.name,
    'showEcg2': showEcg2,
    'showAbp': showAbp,
    'showCo2': showCo2,
    'showResp': showResp,
    'ecgGain': ecgGain,
    'sweep': sweep,
    'qrsVolume': qrsVolume,
    'alarmVolume': alarmVolume,
    'fahrenheit': fahrenheit,
    'showDemoTag': showDemoTag,
  };

  void fromJson(Map<String, dynamic> j) {
    Lead lead(Object? v, Lead d) => Lead.values.firstWhere((l) => l.name == v, orElse: () => d);
    bedLabel = j['bedLabel'] as String? ?? bedLabel;
    patientName = j['patientName'] as String? ?? patientName;
    category = j['category'] as String? ?? category;
    patientInfo = j['patientInfo'] as String? ?? patientInfo;
    layout = ScreenLayout.values.firstWhere((l) => l.name == j['layout'], orElse: () => layout);
    showPap = j['showPap'] as bool? ?? showPap;
    showCvp = j['showCvp'] as bool? ?? showCvp;
    showIcp = j['showIcp'] as bool? ?? showIcp;
    showEeg = j['showEeg'] as bool? ?? showEeg;
    showMiniTrends = j['showMiniTrends'] as bool? ?? showMiniTrends;
    showExtras = j['showExtras'] as bool? ?? showExtras;
    ecg1 = lead(j['ecg1'], ecg1);
    ecg2 = lead(j['ecg2'], ecg2);
    showEcg2 = j['showEcg2'] as bool? ?? showEcg2;
    showAbp = j['showAbp'] as bool? ?? showAbp;
    showCo2 = j['showCo2'] as bool? ?? showCo2;
    showResp = j['showResp'] as bool? ?? showResp;
    ecgGain = (j['ecgGain'] as num?)?.toDouble() ?? ecgGain;
    sweep = (j['sweep'] as num?)?.toDouble() ?? sweep;
    qrsVolume = (j['qrsVolume'] as num?)?.toInt() ?? qrsVolume;
    alarmVolume = (j['alarmVolume'] as num?)?.toInt() ?? alarmVolume;
    fahrenheit = j['fahrenheit'] as bool? ?? fahrenheit;
    showDemoTag = j['showDemoTag'] as bool? ?? showDemoTag;
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        fromJson(jsonDecode(raw) as Map<String, dynamic>);
        notifyListeners();
      }
    } catch (_) {
      // First run, or storage unavailable: the defaults stand.
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(toJson()));
    } catch (_) {
      // Not being able to save settings should never stop the monitor.
    }
  }
}
