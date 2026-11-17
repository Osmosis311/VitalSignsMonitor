import 'package:flutter/foundation.dart';

class GlobalVitals extends ChangeNotifier {
  int _bpm = 75;

  int get bpm => _bpm;

  set bpm(int value) {
    if (_bpm != value) {
      _bpm = value;
      notifyListeners();
    }
  }
}
