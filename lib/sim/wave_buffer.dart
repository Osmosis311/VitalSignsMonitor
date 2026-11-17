import 'dart:typed_data';

/// A stream of evenly spaced samples that a trace can be drawn from.
abstract class WaveSource {
  /// Samples per second.
  double get fs;

  /// Simulation time of the newest sample, in seconds.
  double get tLast;

  int get length;

  /// Sample [i] steps back in time; 0 is the newest.
  double back(int i);
}

/// Fixed-size ring buffer of samples.
class WaveBuffer implements WaveSource {
  WaveBuffer(this.fs, double seconds) : _d = Float32List((fs * seconds).ceil());

  @override
  final double fs;
  final Float32List _d;
  int _head = 0;
  int _n = 0;

  @override
  double tLast = 0;

  void add(double v, double t) {
    _d[_head] = v;
    _head++;
    if (_head == _d.length) _head = 0;
    if (_n < _d.length) _n++;
    tLast = t;
  }

  @override
  int get length => _n;

  @override
  double back(int i) {
    var k = _head - 1 - i;
    if (k < 0) k += _d.length;
    return _d[k];
  }
}

/// A frozen copy of another source, used while the display is frozen.
class WaveSnapshot implements WaveSource {
  WaveSnapshot(WaveSource src, double seconds)
    : fs = src.fs,
      tLast = src.tLast,
      _d = Float32List(_count(src, seconds)) {
    for (var i = 0; i < _d.length; i++) {
      _d[i] = src.back(i);
    }
  }

  static int _count(WaveSource src, double seconds) {
    final want = (src.fs * seconds).ceil();
    return want < src.length ? want : src.length;
  }

  @override
  final double fs;
  @override
  final double tLast;
  final Float32List _d;

  @override
  int get length => _d.length;

  @override
  double back(int i) => _d[i];
}
